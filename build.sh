#!/bin/bash

set -euo pipefail

if ! which jq > /dev/null; then
  apt-get install jq
fi

# All version numbers excluding the v prefix
echo "Fetch dart version"
DART_STABLE_DIGEST="$(curl -sSL https://hub.docker.com/v2/repositories/library/dart/tags | jq -r '[.results[] | select(.name|test("stable")) | .digest] | last')"
echo "DART_STABLE_DIGEST=${DART_STABLE_DIGEST}"
DART_VERSION=$(curl -sSL https://hub.docker.com/v2/repositories/library/dart/tags | jq -r "[.results[] | select(.name|test(\"^[0-9]+[.][0-9]+[.][0-9]+\$\")) | select(.digest|test(\"^${DART_STABLE_DIGEST}\$\")) | .name] | last")
echo "DART_VERSION=${DART_VERSION}"
echo "Fetch protoc version"
PROTOC_VERSION="$(curl -sSL https://api.github.com/repos/protocolbuffers/protobuf/releases/latest | jq -r '.tag_name[1:]')"
echo "PROTOC_VERSION=${PROTOC_VERSION}"
echo "Fetch protoc_plugin version"
PROTOC_PLUGIN_VERSION="$(curl -sSL --compressed https://pub.dev/api/packages/protoc_plugin | jq -r .latest.version)"
echo "PROTOC_PLUGIN_VERSION=${PROTOC_PLUGIN_VERSION}"

image_name="micheljung/protoc-dart"
unique_tag="${PROTOC_PLUGIN_VERSION}-dart${DART_VERSION}-protoc${PROTOC_VERSION}"

tagDoesNotExist() {
  local tag_name=${1}
  if curl -sflSL https://index.docker.io/v1/repositories/${image_name}/tags/${tag_name} > /dev/null; then
    echo "Tag ${tag_name} exists"
    return 1
  else
    echo "Tag ${image_name}:${tag_name} does not exist"
    return 0
  fi
}

build() {
  docker build --build-arg DART_VERSION=${DART_VERSION} \
    --build-arg PROTOC_VERSION=${PROTOC_VERSION} \
    --build-arg PROTOC_PLUGIN_VERSION=${PROTOC_PLUGIN_VERSION} \
    --tag "${image_name}:${unique_tag}" \
    .
}

run_test() {
  docker run --rm -v "${PWD}/test:/project" "${image_name}:${unique_tag}" protoc -I protos --dart_out=output protos/test.proto
}

tag_and_push() {
  tag=${1}
  docker tag "${image_name}:${unique_tag}" "${tag}"
  docker push "${tag}"
}

main() {
  docker login --username "${DOCKER_HUB_USERNAME}" --password "${DOCKER_HUB_ACCESS_TOKEN}"

  if tagDoesNotExist "${unique_tag}"; then
    echo starting build...

    build

    echo starting test...
    run_test

    echo pushing tags...
    docker push "${image_name}:${unique_tag}"
    tag_and_push "${image_name}:${PROTOC_PLUGIN_VERSION}-dart${DART_VERSION}"
    tag_and_push "${image_name}:${PROTOC_PLUGIN_VERSION}-protoc${PROTOC_VERSION}"
    tag_and_push "${image_name}:${PROTOC_PLUGIN_VERSION}"

    tag_and_push "${image_name}:latest"
  else
    echo Current build is up to date
  fi
}

main
