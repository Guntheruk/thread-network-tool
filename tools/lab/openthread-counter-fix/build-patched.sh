set -eu
cd /opt/openthread
printf '%s  %s\n' 58947b0c77d3aaa91b3b12b47dce5f02c1afcfabd9db3736e8342b92409b53fe src/core/thread/key_manager.cpp | sha256sum -c -
mkdir -p /counter-fix/evidence
sha256sum build/posix/src/posix/ot-cli > /counter-fix/evidence/cli-before.sha256
sha256sum build/posix/CMakeCache.txt > /counter-fix/evidence/config-before.sha256
sha256sum build/simulation/examples/apps/ncp/ot-rcp > /counter-fix/evidence/rcp-before.sha256
# Freeze every pre-existing app, fixture and lab file outside this dependency.
find /lab /opt/move-source /opt/move-build /opt/app-source /opt/app-build /opt/full-app-source /opt/lab /opt/full-app-build /opt/full-app-commissioner /opt/full-app-provenance /opt/runner /opt/runner-provenance /opt/verification-profile /opt/cache-app -type f -print0 | sort -z | xargs -0 sha256sum > /counter-fix/evidence/app-fixture-before.sha256
printf '%s  %s\n' 10d162fa0969abc268a4930d146f6ccbaf4de03d0746f7aaf2aeb3778740b4ff /counter-fix/reset-own-counter.patch | sha256sum -c -
git apply --check /counter-fix/reset-own-counter.patch
git apply /counter-fix/reset-own-counter.patch
printf '%s  %s\n' df1c551a7d9a03637f1a7fc6db9b3894763987a39b5e6b91bd9caa7ca5873360 src/core/thread/key_manager.cpp | sha256sum -c -
cmake --build build/posix --target ot-cli -j2
sha256sum build/posix/src/posix/ot-cli > /counter-fix/evidence/cli-after.sha256
sha256sum -c /counter-fix/evidence/config-before.sha256
sha256sum -c /counter-fix/evidence/rcp-before.sha256
sha256sum -c /counter-fix/evidence/app-fixture-before.sha256 > /counter-fix/evidence/app-fixture-unchanged.log
sha256sum src/core/thread/key_manager.cpp /counter-fix/reset-own-counter.patch > /counter-fix/evidence/source-patch.sha256
cp build/posix/CMakeCache.txt /counter-fix/evidence/posix-CMakeCache.txt
cat /counter-fix/evidence/cli-before.sha256 /counter-fix/evidence/cli-after.sha256 /counter-fix/evidence/rcp-before.sha256 /counter-fix/evidence/source-patch.sha256
