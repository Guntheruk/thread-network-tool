set -eu
find /opt/full-app-source /opt/lab /opt/full-app-build /opt/full-app-commissioner /opt/full-app-provenance /opt/runner /opt/runner-provenance /opt/verification-profile /opt/cache-app -type f -print0 | sort -z | xargs -0 sha256sum
