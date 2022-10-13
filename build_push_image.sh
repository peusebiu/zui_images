#!/bin/bash

ROOT_DIR=$(git rev-parse --show-toplevel)
IMAGES_DIR=${ROOT_DIR}/images
DOCKER_DOCS_DIR=${ROOT_DIR}/docs

DOCKER_DOCS_URL="https://raw.githubusercontent.com/docker-library/repo-info/master/repos/"
DOCKER_TAGS_URL="https://registry.hub.docker.com/v2/repositories/library"

REGISTRY=$1
image=$2
tag=$3
USERNAME=$4
PASSWORD=$5

credentials_args=""
if [ ! -z "$USERNAME" ]; then
        credentials_args="--username $USERNAME --password $PASSWORD"
fi

function verify_prerequisites {
    if [ ! command -v stacker ] &>/dev/null; then
        echo "you need to install stacker as a prerequisite" >&3
        return 1
    fi

    return 0
}

verify_prerequisites

# pull docker docs repo
if [ ! -d ${DOCKER_DOCS_DIR} ]
then
    git -C ${ROOT_DIR} clone https://github.com/docker-library/docs.git
fi

repo=$(cat ${DOCKER_DOCS_DIR}/$image/github-repo)
logo=$(base64 -w 0 ${DOCKER_DOCS_DIR}/$image/logo.png)
echo $repo
sed -i "s|%%GITHUB-REPO%%|$repo|g" ${DOCKER_DOCS_DIR}/$image/maintainer.md
sed -i "s|%%IMAGE%%|$image|g" ${DOCKER_DOCS_DIR}/$image/content.md
doc=$(cat ${DOCKER_DOCS_DIR}/$image/content.md)
sudo stacker --oci-dir $IMAGES_DIR build -f stacker.yaml \
    --substitute IMAGE_NAME=$image \
    --substitute IMAGE_TAG=$tag \
    --substitute LOGO=$logo \
    --substitute LICENSES="$(cat ${DOCKER_DOCS_DIR}/$image/license.md)" \
    --substitute DESCRIPTION="$(cat ${DOCKER_DOCS_DIR}/$image/README-short.txt)" \
    --substitute URL="${repo}" \
    --substitute SOURCE="${repo}" \
    --substitute VENDOR="$(cat ${DOCKER_DOCS_DIR}/$image/maintainer.md)" \
    --substitute DOCUMENTATION="$(cat ${DOCKER_DOCS_DIR}/$image/README-short.txt)" \

sudo stacker --oci-dir $IMAGES_DIR publish $credentials_args --url docker://$REGISTRY --tag $tag --skip-tls -f stacker.yaml \
    --substitute IMAGE_NAME=$image \
    --substitute IMAGE_TAG=$tag \
    --substitute LOGO=$logo \
    --substitute LICENSES="$(cat ${DOCKER_DOCS_DIR}/$image/license.md)" \
    --substitute DESCRIPTION="$(cat ${DOCKER_DOCS_DIR}/$image/README-short.txt)" \
    --substitute URL="${repo}" \
    --substitute SOURCE="${repo}" \
    --substitute VENDOR="$(cat ${DOCKER_DOCS_DIR}/$image/maintainer.md)" \
    --substitute DOCUMENTATION="$(cat ${DOCKER_DOCS_DIR}/$image/README-short.txt)" \

