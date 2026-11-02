# syntax=docker/dockerfile:1.7
ARG WOLFI_IMAGE=cgr.dev/chainguard/wolfi-base:latest@sha256:fd50bd0cdeb808cf4f45c9c9189e0cc7f7fcc27195d69abd6622c80527e7e021
FROM --platform=$BUILDPLATFORM ${WOLFI_IMAGE} AS build
ARG TARGETARCH
ARG KIBANA_VERSION=9.5.6
ARG KIBANA_COMMIT=6b06ce57188008d15d48928b2c828ecceaa7e8fd
RUN apk add --no-cache bash build-base corepack git nodejs-24 npm python-3 yarn
ENV NODE_OPTIONS=--max-old-space-size=6144
WORKDIR /src
RUN git -c advice.detachedHead=false clone --quiet --depth 1 --branch "v${KIBANA_VERSION}" \
      https://github.com/elastic/kibana.git . \
    && test "$(git rev-parse HEAD)" = "${KIBANA_COMMIT}"
RUN yarn kbn bootstrap
RUN node scripts/build --release --all-platforms --skip-os-packages --skip-cdn-assets
RUN case "${TARGETARCH}" in \
      amd64) archive="$(find target -maxdepth 1 -name '*linux-x86_64.tar.gz' -type f | head -1)" ;; \
      arm64) archive="$(find target -maxdepth 1 -name '*linux-aarch64.tar.gz' -type f | head -1)" ;; \
      *) exit 1 ;; \
    esac \
    && test -n "${archive}" \
    && mkdir -p /out \
    && tar -xzf "${archive}" -C /out --strip-components=1 \
    && cp src/dev/build/tasks/os_packages/docker_generator/resources/base/bin/kibana-docker /out/bin/kibana-docker \
    && chmod 0555 /out/bin/kibana-docker \
    && chmod -R g=u /out

FROM ${WOLFI_IMAGE}
ARG KIBANA_VERSION=9.5.6
RUN apk upgrade --no-cache \
    && apk add --no-cache bash ca-certificates curl findutils font-liberation fontconfig libnss libstdc++ shadow \
    && addgroup -S -g 1000 kibana \
    && adduser -S -D -H -u 1000 -G kibana -G root kibana
ENV ELASTIC_CONTAINER=true \
    GLIBC_TUNABLES=glibc.malloc.hugetlb=0 \
    PATH=/usr/share/kibana/bin:$PATH
WORKDIR /usr/share/kibana
COPY --from=build --chown=1000:0 /out/ /usr/share/kibana/
COPY --chown=1000:0 --chmod=0660 kibana.yml /usr/share/kibana/config/kibana.yml
RUN chgrp -R 0 /usr/share/kibana \
    && chmod -R g=u /usr/share/kibana
LABEL org.opencontainers.image.title="Kibana" \
      org.opencontainers.image.version="${KIBANA_VERSION}-patched" \
      org.opencontainers.image.source="https://github.com/elastic/kibana" \
      org.opencontainers.image.licenses="Elastic-2.0 OR AGPL-3.0-only"
USER 1000:0
EXPOSE 5601
ENTRYPOINT ["/usr/share/kibana/bin/kibana-docker"]
