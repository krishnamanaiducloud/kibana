.PHONY: build hotfix-build smoke scan builder push hotfix-push all
IMAGENAME=mohankrishna999/kibana
VERSION=9.5.6.2-patched
PLATFORMS=linux/amd64,linux/arm64
BUILDER=securebridge
build:
	docker buildx build --load --platform linux/amd64 -t ${IMAGENAME}:${VERSION} .
hotfix-build:
	docker buildx build --load --platform linux/amd64 -f Dockerfile.hotfix -t ${IMAGENAME}:${VERSION} .
smoke: build
	docker run --rm ${IMAGENAME}:${VERSION} kibana --version
scan: build
	trivy image --scanners vuln --severity UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL --exit-code 1 ${IMAGENAME}:${VERSION}
	grype ${IMAGENAME}:${VERSION} --fail-on negligible
builder:
	docker buildx inspect ${BUILDER} >/dev/null 2>&1 || docker buildx create --name ${BUILDER} --driver docker-container >/dev/null
push: builder
	docker buildx build --builder ${BUILDER} --platform ${PLATFORMS} --sbom=true --provenance=mode=max -t ${IMAGENAME}:${VERSION} -t ${IMAGENAME}:latest --push .
hotfix-push: builder
	docker buildx build --builder ${BUILDER} --platform ${PLATFORMS} --sbom=true --provenance=mode=max -f Dockerfile.hotfix -t ${IMAGENAME}:${VERSION} -t ${IMAGENAME}:latest --push .
all: smoke scan push
