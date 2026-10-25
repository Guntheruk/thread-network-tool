FROM openthread/environment@sha256:8fc56c561f0e65ce039cbb8c665d2e5411f9c573ebe1d142417c65a47394dd26
COPY audit_source.py /lab/audit_source.py
COPY openthread /opt/openthread
RUN python3 /lab/audit_source.py dependency /opt/openthread 53e8322140dde7b26827332100504507cec9cc4e \
    third_party/mbedtls/repo=e185d7fd85499c8ce5ca2a54f5cf8fe7dbe3f8df \
    third_party/mbedtls/repo/framework=457996474728cb8e968ed21953b72f74d2f536b2
COPY ot-commissioner /opt/ot-commissioner
RUN python3 /lab/audit_source.py dependency /opt/ot-commissioner 448f807e3246c46e5b82e4cdc12a9b0fb2a646ae \
    third_party/fmtlib/repo=40626af88bd7df9a5fb80be7b25ac85b122d6c21 \
    third_party/libevent/repo=4c908dde58ef780eeefcc9df4db3063ca62ea862 \
    third_party/mbedtls/repo=c765c831e5c2a0971410692f92f7a81d6ec65ec2 \
    third_party/mbedtls/repo/framework=2a3e2c5ea053c14b745dbdf41f609b1edc6a72fa
RUN cd /opt/openthread && ./script/cmake-build simulation -DOT_APP_CLI=OFF -DOT_APP_NCP=OFF -DOT_APP_RCP=ON -DOT_FTD=OFF -DOT_MTD=OFF
RUN cd /opt/openthread && ./script/cmake-build posix -DOT_APP_CLI=ON -DOT_DAEMON=OFF -DOT_FTD=ON -DOT_MTD=OFF -DOT_BORDER_AGENT=ON -DOT_PLATFORM_UDP=ON -DOT_PLATFORM_NETIF=OFF -DOT_BORDER_AGENT_MESHCOP_SERVICE=OFF -DOT_BORDER_AGENT_EPSKC=OFF
COPY app-source /opt/app-source
COPY app-source.sha256 /lab/app-source.sha256
RUN cd /opt/app-source && sha256sum -c /lab/app-source.sha256
RUN python3 /lab/audit_source.py /opt/app-source/native/probe.cpp
# Prepare this directory on the host with the current app manifest/patch. Python
# 3.11 in frozen images only verifies it; no extraction or dependency fetch occurs.
COPY commissioner-prepared /opt/commissioner-prepared
ENV PYTHONDONTWRITEBYTECODE=1
RUN python3 /opt/app-source/tools/prepare_commissioner_source.py --verify-only --output /opt/commissioner-prepared
RUN cmake -G Ninja -S /opt/app-source -B /opt/app-build -DTNT_WITH_COMMISSIONER=ON -DTNT_COMMISSIONER_SOURCE=/opt/commissioner-prepared -DTNT_BUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 && cmake --build /opt/app-build --target thread-network -j2 && python3 /opt/app-source/tools/prepare_commissioner_source.py --verify-only --output /opt/commissioner-prepared
COPY driver.py /lab/driver.py
ENTRYPOINT ["python3", "/lab/driver.py"]
