# syntax=docker/dockerfile:1.7
ARG WOLFI_IMAGE=cgr.dev/chainguard/wolfi-base:latest@sha256:8acb3a7694eda954b3ad4256aec3291bdd92715d7a8c030abd1a21546337b4e4

FROM --platform=$BUILDPLATFORM ${WOLFI_IMAGE} AS unpack
ARG TARGETARCH
ARG KIBANA_VERSION=8.19.19
ARG KIBANA_SHA512_AMD64=bf831e2a1b65e48087fbf9fdeadb6da9ed85bf52965d4b4b9dab84e955e6459bc682aba0895cd2aa8c2feff334268f1f3e634f8ac8e3f6c6df3d7dcd44cbf690
ARG KIBANA_SHA512_ARM64=9612a73735d51819bdba35664fac0ad80ec6ed1115553a0ea0a8777bdafd198773252b7deb50b4a50a410c268384332007b50f302284089f9c330ec9f916513c
ARG CONTEXT_SHA512=e7f62c2b1e7ee1053f4ddf5d5fe0e70a03d97798999c58c6d78541a0de52e671efe9ae336ace1414e5730c90733216792047b15555b0b4206b0cf2926fa73438
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
RUN if [ -d /work/build/patches ]; then \
      for p in /work/build/patches/*.patch; do patch -p1 -d /out < "$p"; done; \
    fi \
    && rm -rf /out/node \
    && mkdir -p /out/node/glibc-217/bin \
    && ln -s /usr/bin/node /out/node/glibc-217/bin/node \
    && chmod -R g=u /out

FROM ${WOLFI_IMAGE}
ARG KIBANA_VERSION=8.19.19
ARG APK_REPOSITORY
RUN --mount=type=bind,source=build/apk-install.sh,target=/tmp/apk-install.sh \
    sh /tmp/apk-install.sh bash ca-certificates findutils font-liberation fontconfig libnss libstdc++ nodejs-24 shadow tini \
    && test -x /usr/bin/node && test -x /sbin/tini \
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
      org.opencontainers.image.version="${KIBANA_VERSION}.1-patched" \
      org.opencontainers.image.source="https://github.com/elastic/kibana" \
      org.opencontainers.image.licenses="Elastic-2.0 OR AGPL-3.0-only"
USER 1000:0
EXPOSE 5601
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/local/bin/kibana-docker"]
