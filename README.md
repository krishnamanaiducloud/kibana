# Kibana hardened image

Kibana 8.19.24 repackaged from Elastic's official Linux release archive (SHA-512 verified) on a
current Chainguard Wolfi runtime. The bundled Node.js is replaced by Wolfi's patched `nodejs-24`,
and npm packages with known vulnerabilities are replaced by fixed releases from the npm registry,
each pinned by integrity hash in `build/npm-manifest.json`. The build fails if any replaced package
is left with an unmet dependency.

Published as `mohankrishna999/kibana:8.19.24.2-patched` for amd64 and arm64.

The image preserves the standard `/usr/share/kibana` layout, `kibana-docker` environment
translation, `curl`, UID 1000 and port 5601. Primary GID 0 and group-writable paths support OpenShift
arbitrary UIDs.

## 8.19.24.2-patched

- `nodemailer` 10.1.4 to 10.5.0.
- All four installed `@opentelemetry/sdk-trace-base` copies (2.8.0 and 2.9.0) to 2.12.1,
  each with private, version-aligned `core`, `resources` and `sdk-trace` 2.12.1 dependencies.
- `basic-ftp` 6.2.1 to 6.2.6. It is used by `get-uri` for `ftp://` proxy auto-config URLs.
  6.2.2 to 6.2.6 fix four advisories published in October and November 2026:
  GHSA-5rfr-xx34-2xxv, GHSA-r4jh-29pc-gfqr, GHSA-5pm8-86m8-9m6r and GHSA-2w5v-vj22-jp27.
- `curl` is installed, as in Elastic's image; `8.19.24-patched` and `8.19.24.1-patched` left it out.
  Health checks such as the ones in Elastic's Docker Compose examples call it.

## 8.19.24.1-patched

npm package changes in `build/npm-manifest.json`:

- `@hapi/hapi` 21.4.10 to 21.4.13, Kibana's HTTP server. Also raised: `@hapi/ammo` 6.0.2, `@hapi/pez` 6.1.3, `@hapi/shot` 6.0.3, `@hapi/subtext` 8.1.5 and `@hapi/wreck` 18.1.3, which it requires.
- `systeminformation` 5.33.16 to 5.33.19.
- `openpgp` 5.11.3 to 6.3.2. The 5.x line is deprecated and gets no more security fixes.
  - Fleet's package signature check is its only user.
  - With Kibana's bundled Elastic key and the same call sequence, openpgp 6.3.2 verifies the Elastic Package Registry signature of `system` 3.5.0 and rejects a tampered archive, exactly as 5.11.3 does.
- `@aws-sdk/core` 3.977.3 to 3.980.1 and `@smithy/core` 3.31.1 to 3.39.0. npm deprecated both releases for bugs. Also raised: `@aws-sdk/types`, `@aws-sdk/xml-builder`, `@smithy/signature-v4` and `@smithy/types`, which `@aws-sdk/core` 3.980.1 requires.
- `rimraf` 3.0.2 and its `glob` 7.2.3 and `inflight` 1.0.6 are removed. npm marks all three unsupported.
  - Their only user was `del` 6.1.1, which Reporting's Chromium setup and `kibana-plugin` use for cleanup.
  - `del` now deletes with Node.js's recursive `fs.rm`. It removes the same files and directories, ignores missing paths, and retries busy ones as rimraf did.
  - This is applied as a checksum-verified `edit` of `del/index.js` and `del/package.json` (see `npm-patch.mjs`).

Still reported by npm as deprecated, with no replacement version: abab, crypto-js, domexception, jpeg-exif, lodash.get, node-domexception, source-map 0.8.0-beta.0, whatwg-encoding, @formatjs/intl-utils, and the renamed OpenTelemetry packages `@opentelemetry/sdk-trace-base`, `sdk-trace-node` and `propagator-jaeger`. These are deprecated in every release of the package, so only changes in Kibana or its dependencies can remove them.

Verified on the built image:
- **Every replaced package loads:** each replaced package, and each package that depends on one, loads with Kibana's module resolution.
- **Targeted checks:**
  - `del` deletes a tree and a glob, and ignores a missing path.
  - openpgp verifies the Elastic Package Registry signature and rejects a tampered archive.
  - `@hapi/hapi` parses a multipart upload.
  - systeminformation reads host load and memory.
  - The Bedrock runtime client sends a SigV4-signed request and reads the response.
- **Kibana itself:** Kibana starts against Elasticsearch, serves its pages at desktop and phone widths without errors, and starts over HTTPS with a PKCS#12 keystore.

## Known scanner findings

Trivy reports no vulnerabilities. Grype reports these, none of which has a fix that can be applied
yet:

- CVE-2026-84243 in glibc 2.44 (matched through NVD). Neither Wolfi nor Chainguard ships a patched
  glibc yet.
- CVE-2026-119586 in sqlite-libs 3.54.1. It affects the sqlite3 command-line shell, which is not
  installed; the library comes in through libnss, which Reporting's Chromium needs for PDF and PNG
  reports. No fixed SQLite release exists yet.
- GHSA-mrhx-c7xc-m3w5 (CVE-2023-54404) in zod 3.25.76. It is fixed only in zod 4.6.6, a major
  version whose API Kibana 8.19 is not written for; Elastic's own 8.19.24 release ships the same
  zod.
- GHSA-gcqx-w48m-w2h4 (CVE-2026-93753) in deepmerge 4.3.1. No fixed release exists.

The image will be rebuilt under a new tag as fixes become available.
