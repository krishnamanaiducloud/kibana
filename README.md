# Kibana hardened image

Kibana 9.5.6 repackaged from Elastic's official Linux release archive (SHA-512 verified) on a
current Chainguard Wolfi runtime. The bundled Node.js is replaced by Wolfi's patched `nodejs-24`,
and npm packages with known vulnerabilities are replaced by fixed releases from the npm registry,
each pinned by integrity hash in `build/npm-manifest.json`. The build fails if any replaced package
is left with an unmet dependency.

Published as `mohankrishna999/kibana:9.5.6.2-patched` for amd64 and arm64.

The image follows Elastic's Docker image: the standard `/usr/share/kibana` layout, `kibana-docker`
environment translation, `tini` as init, `curl` for health checks, UID 1000 and port 5601. Primary
GID 0 and group-writable paths support OpenShift arbitrary UIDs.

## 9.5.6.2-patched

Earlier `9.5.6-patched` images were built from source. This release is built the same way as the
8.19 images: Elastic's release archive with the npm changes below.

npm package changes in `build/npm-manifest.json`:

- Packages with published vulnerabilities, raised to fixed releases:
  - `@ai-sdk/provider-utils` 3.0.25 to 3.0.28.
  - `@hapi/content` 6.0.2 to 6.0.3.
  - `@hono/node-server` 1.19.17 to 2.1.6. The MCP SDK accepts `^1.19.9 || ^2.0.5`; 2.x keeps
    the same API.
  - `hono` 4.13.13 to 4.13.17.
  - Every installed `@opentelemetry/sdk-trace-base` copy (2.8.0 through 2.11.0) to 2.12.1,
    each with private, version-aligned `core`, `resources` and `sdk-trace` 2.12.1 dependencies.
  - The OpenTelemetry instrumentations for Cassandra, Knex, Mongoose, MySQL, MySQL2, OracleDB, pg
    and Tedious, one minor release each. Each one also gets its own `@opentelemetry/instrumentation`
    0.221.0, which it requires.
  - `basic-ftp` 5.3.1 to 6.2.6, used by `get-uri` for `ftp://` proxy auto-config URLs. 6.0's only
    breaking change refuses data connections to a different host than the control connection.
    6.2.2 to 6.2.6 fix four further advisories published in October and November 2026.
  - `decode-uri-component` 0.5.0 to 0.5.1.
  - `fast-uri` 3.1.8 to 3.1.9.
  - `fast-xml-parser` 5.5.7 to 5.12.0. This is the release `just-bash` declares (`^5.10.1`).
  - `glob` 10.5.0 to 14.0.2, with its own `minimatch` 11.0.1 and `path-scurry` 3.0.0.
  - `joi` 18.2.9 to 18.3.1.
  - `minimatch` 10.2.4 to 11.0.1, and `just-bash`'s copy from 10.2.6 to 11.0.1. `just-bash`
    calls `minimatch(path, pattern)` for `ls` globs, which works the same in 11.
  - `node-forge` 1.4.0 to 1.4.3.
  - `nodemailer` 10.0.16 to 10.5.0.
  - `prismjs` 1.27.0 to 1.30.0, used by `refractor` for code highlighting.
  - `re2js` 2.8.5 to 2.8.7, used by Timelion's `label()`.
  - `smol-toml` 1.8.0 to 1.9.1.
  - `systeminformation` 5.33.8 to 5.33.19.
  - `zod` 4.4.3 to 4.6.7 (GHSA-mrhx-c7xc-m3w5, fixed in 4.6.6). Every package that uses it accepts
    any zod 4 release.
- The same changes as 8.19.24.1:
  - `@hapi/hapi` 21.4.10 to 21.4.13, with `@hapi/ammo` 6.0.2, `@hapi/pez` 6.1.3,
    `@hapi/subtext` 8.1.5 and `@hapi/wreck` 18.1.3.
  - `openpgp` 5.11.3 to 6.3.2. The 5.x line gets no more security fixes. Fleet's package signature
    check is its only user.
  - `@smithy/core` 3.33.3 to 3.39.0. npm deprecated 3.33.3 for a bug.
  - `del` 6.1.1 deletes with Node.js's recursive `fs.rm` instead of `rimraf` 3. Its private
    `rimraf` 3.0.2, `glob` 7.2.3, `minimatch` and `brace-expansion`, and `inflight` 1.0.6, are
    removed. npm marks `rimraf` 3, `glob` 7 and `inflight` unsupported. This is a checksum-verified
    `edit` of `del/index.js` and `del/package.json` (see `npm-patch.mjs`).
- `just-bash`'s `re2js` 1.4.0 goes to 1.3.3. npm deprecated 1.4.0 as an accidental breaking release
  and points to 1.3.3, which matches `just-bash`'s `^1.3.3`.
- `zod-to-json-schema`'s test bundles (`dist-test-v3`, `dist-test-v4`) are removed, as in the
  8.19 images.

`just-bash`, the Agent Builder's sandboxed shell, ships a prebuilt bundle that contains its own
copies of `fast-xml-parser`, `re2js` and `smol-toml`. The separately installed copies above are
updated. The code inside the bundle changes only with a `just-bash` release.

Still reported by npm as deprecated, with no replacement version: abab, crypto-js, domexception,
jpeg-exif, lodash.get, node-domexception, prebuild-install, whatwg-encoding,
@formatjs/intl-utils, and the renamed OpenTelemetry packages `@opentelemetry/sdk-trace-base`,
`sdk-trace-node` and `propagator-jaeger`. Every release of these is deprecated, so only changes in
Kibana or its dependencies can remove them.

Verified on the built image, side by side with Elastic's `kibana:9.5.6`:

- **Every replaced package loads:** each replaced package, and each package that depends on one,
  loads with Kibana's module resolution.
- **Functional checks give the same results as Elastic's 9.5.6 code:**
  - `ftp://` download through `get-uri` and `basic-ftp` 6.
  - `just-bash` `ls` globs (minimatch 11).
  - An MCP client and server round trip over the SDK's streamable HTTP transport
    (`@hono/node-server` 2).
  - Code highlighting through `refractor` (prismjs 1.30).
  - Timelion's `re2js` label replacement.
  - Reporting's unzip, the PKCS#12 keystore (node-forge), `nodemailer`, `joi`, `glob`,
    `minimatch`, `fast-xml-parser` and `systeminformation`.
- **Targeted checks:**
  - openpgp 6.3.2 verifies the Elastic Package Registry signature of `system` 3.5.0 and rejects a
    tampered archive.
  - `@hapi/hapi` parses a multipart upload.
  - The Bedrock runtime client sends a SigV4-signed request and reads the response.
  - `del` deletes a tree and a glob, and ignores a missing path.
- **Kibana itself:**
  - Kibana starts against Elasticsearch 9.5.6.2-patched and serves Home and Discover at desktop and
    phone widths, with renders identical to Elastic's image.
  - It logs no error that Elastic's image does not also log.
  - It starts over HTTPS with a PKCS#12 keystore.

## Known scanner findings

Trivy reports no vulnerabilities. Elastic's `kibana:9.5.6` image has 378. Grype reports three, none
of which has a fix that can be applied yet:

- CVE-2026-84243 in glibc 2.44 (matched through NVD). Neither Wolfi nor Chainguard ships a patched
  glibc yet.
- CVE-2026-119586 in sqlite-libs 3.54.1. It affects the sqlite3 command-line shell, which is not
  installed. The library comes in through libnss, which Reporting's Chromium needs for PDF and PNG
  reports, and through `curl`. No fixed SQLite release exists yet.
- GHSA-gcqx-w48m-w2h4 (CVE-2026-93753) in deepmerge 4.3.1. No fixed release exists.

The image will be rebuilt under a new tag as fixes become available.
