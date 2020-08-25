ARG FROM_TAG=release
FROM ponylang/shared-docker-ci-x86-64-unknown-linux-builder:${FROM_TAG}

RUN apk add --update --no-cache \
  curl \
  libressl-dev \
  pcre2-dev
