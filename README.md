# Kibana hardened image

Kibana 8.19.24 repackaged from Elastic's official Linux release archive (SHA-512 verified) on a
current Chainguard Wolfi runtime. The bundled Node.js is replaced by Wolfi's patched `nodejs-24`,
and npm packages with known vulnerabilities are replaced by fixed releases from the npm registry,
each pinned by integrity hash in `build/npm-manifest.json`. The build fails if any replaced package
is left with an unmet dependency.

Published as `mohankrishna999/kibana:8.19.24-patched` for amd64 and arm64.

The image preserves the standard `/usr/share/kibana` layout, `kibana-docker` environment
translation, UID 1000 and port 5601. Primary GID 0 and group-writable paths support OpenShift
arbitrary UIDs.

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
