# Kibana hardened source build

Kibana 9.5.6 built from the verified upstream source commit and packaged on a current
Chainguard Wolfi runtime. Published as `mohankrishna999/kibana:9.5.6-patched` for amd64
and arm64.

The image preserves the standard `/usr/share/kibana` layout, `kibana-docker` environment
translation, UID 1000, and port 5601. Primary GID 0 and group-writable paths support
OpenShift arbitrary UIDs.
