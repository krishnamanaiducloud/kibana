# syntax=docker/dockerfile:1.7
ARG WOLFI_IMAGE=cgr.dev/chainguard/wolfi-base:latest@sha256:24f549a7fcace88e69b9557941168c74645688ecc4acf7fb6d734a6b74e9019d

FROM --platform=$BUILDPLATFORM ${WOLFI_IMAGE} AS unpack
ARG TARGETARCH
ARG KIBANA_VERSION=9.5.6
ARG KIBANA_SHA512_AMD64=41629eb64565796ea5caeb42a635671297cd13ea98ace5a791ad53c32fe66fd2b81d851fcba462bde420f318718f15c18d805ec2c54088054478444da3590696
ARG KIBANA_SHA512_ARM64=b868c59340a2512c6b58c5dc27888b6fd85165bf18802ef29e24393f11509138fdcd0242f0fc8f38acdf847bf16bf54d29155eb147aa6a1f0a320912b9d4fdcf
ARG CONTEXT_SHA512=d8c7b3a471769ec8b05722229d3534c50b014568d3956ebab007b46f67699136c0a6328064020a5a680b064c15415fdc8865b4538f45e3aaa0b638acb53fd86d
ARG NOTO_SHA256=5dcd1c336cc9344cb77c03a0cd8982ca8a7dc97d620fd6c9c434e02dcb1ceeb3
ARG APK_REPOSITORY
RUN --mount=type=bind,source=build/apk-install.sh,target=/tmp/apk-install.sh \
    sh /tmp/apk-install.sh bash coreutils curl findutils gnutar gzip nodejs-24 patch
WORKDIR /work
RUN case "${TARGETARCH}" in \
      amd64) arch=x86_64 sum="${KIBANA_SHA512_AMD64}" ;; \
      arm64) arch=aarch64 sum="${KIBANA_SHA512_ARM64}" ;; \
      *) exit 1 ;; \
    esac \
    && base=https://artifacts.elastic.co/downloads/kibana \
    && curl -fsSL --retry 8 --retry-all-errors --speed-limit 1024 --speed-time 60 -o kibana.tar.gz "${base}/kibana-${KIBANA_VERSION}-linux-${arch}.tar.gz" \
    && echo "${sum}  kibana.tar.gz" | sha512sum -c - \
    && curl -fsSL --retry 8 --retry-all-errors --speed-limit 1024 --speed-time 60 -o ctx.tar.gz "${base}/kibana-wolfi-${KIBANA_VERSION}-docker-build-context.tar.gz" \
    && echo "${CONTEXT_SHA512}  ctx.tar.gz" | sha512sum -c - \
    && curl -fsSL --retry 8 --retry-all-errors --speed-limit 1024 --speed-time 60 -o NotoSansCJK-Regular.ttc \
         https://github.com/googlefonts/noto-cjk/raw/NotoSansV2.001/NotoSansCJK-Regular.ttc \
    && echo "${NOTO_SHA256}  NotoSansCJK-Regular.ttc" | sha256sum -c - \
    && mkdir -p /out ctx \
    && tar -xzf kibana.tar.gz -C /out --strip-components=1 \
    && tar -xzf ctx.tar.gz -C ctx \
    && rm -f kibana.tar.gz ctx.tar.gz
COPY build/ /work/build/
RUN --mount=type=cache,id=kibana-npm,target=/tmp/npm-patch-cache,sharing=locked \
    node /work/build/npm-patch.mjs /out /work/build/npm-manifest.json
# bin/kibana runs node/default/bin/node and falls back to node/glibc-217/bin/node; both point at Wolfi's nodejs-24.
RUN if [ -d /work/build/patches ]; then \
      for p in /work/build/patches/*.patch; do patch -p1 -d /out < "$p"; done; \
    fi \
    && rm -rf /out/node \
    && mkdir -p /out/node/default/bin /out/node/glibc-217/bin \
    && ln -s /usr/bin/node /out/node/default/bin/node \
    && ln -s /usr/bin/node /out/node/glibc-217/bin/node

FROM ${WOLFI_IMAGE}
ARG KIBANA_VERSION=9.5.6
ARG APK_REPOSITORY
RUN --mount=type=bind,source=build/apk-install-runtime.sh,target=/tmp/apk-install.sh \
    sh /tmp/apk-install.sh bash ca-certificates curl findutils font-liberation fontconfig libnss libstdc++ nodejs-24 shadow tini \
    && test -x /usr/bin/node && test -x /sbin/tini && test -x /bin/tini \
    && groupadd --gid 1000 kibana \
    && useradd --uid 1000 --gid 1000 -G 0 --home-dir /usr/share/kibana --no-create-home kibana
ENV ELASTIC_CONTAINER=true \
    GLIBC_TUNABLES=glibc.malloc.hugetlb=0 \
    PATH=/usr/share/kibana/bin:$PATH
WORKDIR /usr/share/kibana
COPY --from=unpack --chown=1000:0 /out/ /usr/share/kibana/
COPY --from=unpack --chown=0:0 --chmod=0555 /work/ctx/bin/kibana-docker /usr/local/bin/kibana-docker
COPY --from=unpack --chown=0:0 --chmod=0444 /work/NotoSansCJK-Regular.ttc /usr/share/fonts/local/NotoSansCJK-Regular.ttc
COPY --chown=1000:0 --chmod=0660 kibana.yml /usr/share/kibana/config/kibana.yml
# Kibana requires the exact Node.js version recorded in package.json; pin it to the runtime's patched nodejs-24.
RUN node -e "const fs=require('fs');const f='/usr/share/kibana/package.json';const p=JSON.parse(fs.readFileSync(f,'utf8'));p.engines.node=process.versions.node;fs.writeFileSync(f,JSON.stringify(p,null,2)+'\n')" \
    && ln -s /usr/local/bin/kibana-docker /usr/share/kibana/bin/kibana-docker \
    && ln -s /usr/share/kibana /opt/kibana \
    && fc-cache -f \
    && chmod g+ws /usr/share/kibana \
    && find /usr/share/kibana -gid 0 -not -type l -not -perm /g+w -exec chmod g+w {} + \
    && find / -xdev -perm -4000 -exec chmod u-s {} +
LABEL org.opencontainers.image.title="Kibana" \
      org.opencontainers.image.version="${KIBANA_VERSION}.2-patched" \
      org.opencontainers.image.source="https://github.com/elastic/kibana" \
      org.opencontainers.image.licenses="Elastic-2.0 OR AGPL-3.0-only"
USER 1000:0
EXPOSE 5601
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/local/bin/kibana-docker"]
