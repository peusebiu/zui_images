#!/bin/bash

ROOT_DIR=$(git rev-parse --show-toplevel)
IMAGES_DIR=${ROOT_DIR}/images
DOCKER_DOCS_DIR=${ROOT_DIR}/docs

DOCKER_DOCS_URL="https://raw.githubusercontent.com/docker-library/repo-info/master/repos/"
DOCKER_TAGS_URL="https://registry.hub.docker.com/v2/repositories/library"

COSIGN_KEY_PATH="cosign.key"

REGISTRY=$1
image=$2
tag=$3
COSIGN_PASSWORD=$4
metafile=$5
multiarch=$6
USERNAME=$7
PASSWORD=$8

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
echo ${repo}
sed -i "s|%%GITHUB-REPO%%|${repo}|g" ${DOCKER_DOCS_DIR}/${image}/maintainer.md
sed -i "s|%%IMAGE%%|${image}|g" ${DOCKER_DOCS_DIR}/${image}/content.md
doc=$(cat ${DOCKER_DOCS_DIR}/${image}/content.md)

local_image_ref_skopeo=oci:${IMAGES_DIR}:${image}
local_image_ref_regtl=ocidir://${IMAGES_DIR}:${image}

multiarch_arg=""
if [ ! -z "${multiarch}" ]; then
    multiarch_arg="--multi-arch=${multiarch}"
fi

# Copy image in local oci layout
skopeo --insecure-policy copy --format=oci ${multiarch_arg} docker://${image}:${tag} ${local_image_ref_skopeo}

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
skopeo copy --dest-tls-verify=false ${multiarch_arg} ${credentials_args} ${local_image_ref_skopeo} docker://${REGISTRY}/${image}:${tag}

# Sign new updated image
COSIGN_PASSWORD=${COSIGN_PASSWORD} cosign sign ${REGISTRY}/${image}:${tag} --key ${COSIGN_KEY_PATH} --allow-insecure-registry

details=$(jq -n \
    --arg org.opencontainers.image.title "${image}" \
    --arg org.opencontainers.image.description " $description" \
    --arg org.opencontainers.image.url "${repo}" \
    --arg org.opencontainers.image.source "${repo}" \
    --arg org.opencontainers.image.licenses "${license}" \
    --arg org.opencontainers.image.vendor "${vendor}" \
    --arg org.opencontainers.image.documentation "${description}" \
    --arg multiarch "${multiarch}" \
    '$ARGS.named'
)

jq -n --arg image "${image}" --arg tag "${tag}"  --argjson details "${details}" '.[$image][$tag]=$details' > ${metafile}
