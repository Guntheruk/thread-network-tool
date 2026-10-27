set -eu
mkdir -p /work/openthread
tar -C /opt/openthread --exclude=./build -cf - . | tar -C /work/openthread -xf -
cd /work/openthread
printf '%s  %s\n' 58947b0c77d3aaa91b3b12b47dce5f02c1afcfabd9db3736e8342b92409b53fe src/core/thread/key_manager.cpp | sha256sum -c -
cp /diagnostic/test_network_key_counter.cpp tests/unit/
printf '\not_unit_test(network_key_counter)\n' >> tests/unit/CMakeLists.txt
cmake -G Ninja -S . -B /work/build -DOT_PLATFORM=external -DOT_APP_CLI=OFF -DOT_APP_NCP=OFF -DOT_APP_RCP=OFF -DOT_FTD=ON -DOT_MTD=OFF -DOT_COMPILE_WARNING_AS_ERROR=OFF -DOT_BUILD_EXECUTABLES=OFF -DOT_UNIT_TEST=ON > /work/configure.log 2>&1 || { cat /work/configure.log; exit 3; }
cmake --build /work/build --target ot-test-network_key_counter -j2 > /work/build-red.log 2>&1 || { tail -90 /work/build-red.log; exit 4; }
set +e
/work/build/tests/unit/ot-test-network_key_counter > /work/red.log 2>&1
red_status=$?
set -e
cat /work/red.log
printf 'RED_EXIT=%s\n' "$red_status"
test "$red_status" = 255
grep -F "host advertises a counter different from the radio's next secured TX" /work/red.log
printf '%s  %s\n' 10d162fa0969abc268a4930d146f6ccbaf4de03d0746f7aaf2aeb3778740b4ff /diagnostic/reset-own-counter.patch | sha256sum -c -
git apply --check /diagnostic/reset-own-counter.patch
git apply /diagnostic/reset-own-counter.patch
printf '%s  %s\n' df1c551a7d9a03637f1a7fc6db9b3894763987a39b5e6b91bd9caa7ca5873360 src/core/thread/key_manager.cpp | sha256sum -c -
cp /diagnostic/reset-own-counter.patch /work/reset-own-counter.patch
cmake --build /work/build --target ot-test-network_key_counter -j2 > /work/build-green.log 2>&1 || { tail -90 /work/build-green.log; exit 5; }
/work/build/tests/unit/ot-test-network_key_counter > /work/green.log 2>&1
cat /work/green.log
cp /work/reset-own-counter.patch /work/red.log /work/green.log /work/configure.log /work/build-red.log /work/build-green.log /evidence/
cp src/core/thread/key_manager.cpp /evidence/patched-key_manager.cpp
cp /work/build/tests/unit/ot-test-network_key_counter /evidence/
sha256sum /diagnostic/test_network_key_counter.cpp /diagnostic/run.sh /work/reset-own-counter.patch src/core/thread/key_manager.cpp /work/build/tests/unit/ot-test-network_key_counter
