#!/bin/sh
# Runtime package installation uses short, bounded retries because the package
# CDN can leave an established connection idle indefinitely.
set -u
repos=/etc/apk/repositories
if [ -n "${APK_REPOSITORY:-}" ]; then
  printf '%s\n' "$APK_REPOSITORY" > /tmp/apk-repositories
  repos=/tmp/apk-repositories
fi
if [ -e /etc/gai.conf ]; then cp -p /etc/gai.conf /tmp/gai.conf.orig; fi
echo 'precedence ::ffff:0:0/96  100' > /etc/gai.conf
ok=
for i in 1 2 3 4 5 6; do
  if timeout 90 sh -c 'apk --repositories-file "$0" upgrade --no-cache && apk --repositories-file "$0" add --no-cache "$@"' "$repos" "$@"; then
    ok=1
    break
  fi
  echo "apk install failed (attempt $i), retrying" >&2
  sleep 10
done
if [ -e /tmp/gai.conf.orig ]; then mv /tmp/gai.conf.orig /etc/gai.conf; else rm -f /etc/gai.conf; fi
rm -f /tmp/apk-repositories
[ -n "$ok" ]
