#!/bin/bash

ROOT_DIR=$(git rev-parse --show-toplevel)
IMAGES_DIR=${ROOT_DIR}/images
DOCKER_DOCS_DIR=${ROOT_DIR}/docs

COSIGN_KEY_PATH="cosign.key"

REGISTRY=""
image=""
tag=""
COSIGN_PASSWORD=""
metafile=""
multiarch=""
USERNAME=""
PASSWORD=""
debug=0

options=$(getopt -o dr:i:t:u:p:c:m:f: -l debug,registry:,image:,tag:,username:,password:,cosign-password:,multiarch:,file: -- "$@")
if [ $? -ne 0 ]; then
   usage $0
   exit 0
fi

eval set -- "$options"
while :; do
    case "$1" in
        -r|--registry)  REGISTRY=$2; shift 2;;
        -i|--image)   image=$2; shift 2;;
        -t|--tag)   tag=$2; shift 2;;
        -u|--username) USERNAME=$2; shift 2;;
        -p|--password) PASSWORD=$2; shift 2;;
        -c|--cosign-password) COSIGN_PASSWORD=$2; shift 2;;
        -m|--multiarch) multiarch=$2; shift 2;;
        -f|--file) metafile=$2; shift 2;;
        -d|--debug) debug=1; shift 1;;
        --)         shift 1; break;;
        *)          usage $0; exit 1;;
    esac
done

if [ ${debug} -eq 1 ]; then
    set -x
fi

function verify_prerequisites {
    if [ ! command -v regctl ] &>/dev/null; then
        echo "you need to install regctl as a prerequisite" >&3
        return 1
    fi

    if [ ! command -v skopeo ] &>/dev/null; then
        echo "you need to install skopeo as a prerequisite" >&3
        return 1
    fi

    if [ ! command -v cosign ] &>/dev/null; then
        echo "you need to install cosign as a prerequisite" >&3
        return 1
    fi

    if [ ! command -v jq ] &>/dev/null; then
        echo "you need to install jq as a prerequisite" >&3
        return 1
    fi

    if [ ! -f "${COSIGN_KEY_PATH}" ]; then
        COSIGN_PASSWORD=${COSIGN_PASSWORD} cosign generate-key-pair
    fi

    # pull docker docs repo
    if [ ! -d ${DOCKER_DOCS_DIR} ]
    then
        git -C ${ROOT_DIR} clone https://github.com/docker-library/docs.git
    fi

    return 0
}

verify_prerequisites

repo=$(cat ${DOCKER_DOCS_DIR}/${image}/github-repo)
description="$(cat ${DOCKER_DOCS_DIR}/${image}/README-short.txt)"
license="$(cat ${DOCKER_DOCS_DIR}/${image}/license.md)"
vendor="$(cat ${DOCKER_DOCS_DIR}/${image}/maintainer.md)"
logo=$(base64 -w 0 ${DOCKER_DOCS_DIR}/${image}/logo.png)
echo ${repo}
sed -i "s|%%GITHUB-REPO%%|${repo}|g" ${DOCKER_DOCS_DIR}/${image}/maintainer.md
sed -i "s|%%IMAGE%%|${image}|g" ${DOCKER_DOCS_DIR}/${image}/content.md
doc=$(cat ${DOCKER_DOCS_DIR}/${image}/content.md)

local_image_ref_skopeo=oci:${IMAGES_DIR}:${image}-${tag}
local_image_ref_regtl=ocidir://${IMAGES_DIR}:${image}-${tag}
remote_src_image_ref=docker://${image}:${tag}
remote_dest_image_ref=${REGISTRY}/${image}:${tag}

multiarch_arg=""
if [ ! -z "${multiarch}" ]; then
    multiarch_arg="--multi-arch=${multiarch}"
fi

# Verify if image is already present in local oci layout
skopeo inspect ${local_image_ref_skopeo}
if [ $? -eq 0 ]; then
    echo "Image ${local_image_ref_skopeo} found locally"
else
    echo "Image ${local_image_ref_skopeo} will be copied"
    skopeo --insecure-policy copy --format=oci ${multiarch_arg} ${remote_src_image_ref} ${local_image_ref_skopeo}
    if [ $? -ne 0 ]; then
        exit 1
    fi
fi

# Mofify image in local oci layout and update the old reference to point to the new index
regctl image mod --replace --annotation org.opencontainers.image.title=${image} ${local_image_ref_regtl}
regctl image mod --replace --annotation org.opencontainers.image.description="${description}" ${local_image_ref_regtl}
regctl image mod --replace --annotation org.opencontainers.image.url=${repo} ${local_image_ref_regtl}
regctl image mod --replace --annotation org.opencontainers.image.source=${repo} ${local_image_ref_regtl}
regctl image mod --replace --annotation org.opencontainers.image.licenses="${license}" ${local_image_ref_regtl}
regctl image mod --replace --annotation org.opencontainers.image.vendor="${vendor}" ${local_image_ref_regtl}
regctl image mod --replace --annotation org.opencontainers.image.documentation="${description}" ${local_image_ref_regtl}

credentials_args=""
if [ ! -z "${USERNAME}" ]; then
    credentials_args="--dest-creds ${USERNAME}:${PASSWORD}"
fi

# Upload image to target registry
skopeo copy --dest-tls-verify=false ${multiarch_arg} ${credentials_args} ${local_image_ref_skopeo} docker://${remote_dest_image_ref}
if [ $? -ne 0 ]; then
    exit 1
fi

# Upload image logo as artifact media type
# regctl artifact put --media-type "application/vnd.oci.artifact.manifest.v1+json" --annotation artifact.type=com.zot.logo.artifact --annotation format=oci \
#     --artifact-type "application/vnd.zot.logo.v1" --subject ${remote_dest_image_ref} ${remote_dest_image_ref}-logo-artifact << EOF
# ${logo}
# EOF
# if [ $? -ne 0 ]; then
#     exit 1
# fi

# Upload image logo as image media type
regctl artifact put --annotation artifact.type=com.zot.logo.image --annotation format=oci \
    --artifact-type "application/vnd.zot.logo.v1" --subject ${remote_dest_image_ref} ${remote_dest_image_ref}-logo-image << EOF
${logo}
EOF
if [ $? -ne 0 ]; then
    exit 1
fi

# Sign new updated image
COSIGN_PASSWORD=${COSIGN_PASSWORD} cosign sign ${remote_dest_image_ref} --key ${COSIGN_KEY_PATH} --allow-insecure-registry
if [ $? -ne 0 ]; then
    exit 1
fi

details=$(jq -n \
    --arg org.opencontainers.image.title "${image}" \
    --arg org.opencontainers.image.description " $description" \
    --arg org.opencontainers.image.url "${repo}" \
    --arg org.opencontainers.image.source "${repo}" \
    --arg org.opencontainers.image.licenses "${license}" \
    --arg org.opencontainers.image.vendor "${vendor}" \
    --arg org.opencontainers.image.documentation "${description}" \
    '$ARGS.named'
)

jq -n --arg image "${image}" --arg tag "${tag}"  --argjson details "${details}" '.[$image][$tag]=$details' > ${metafile}
