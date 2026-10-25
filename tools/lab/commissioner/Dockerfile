FROM openthread/environment@sha256:8fc56c561f0e65ce039cbb8c665d2e5411f9c573ebe1d142417c65a47394dd26
COPY openthread /opt/openthread
RUN test "$(git -C /opt/openthread rev-parse HEAD)" = 53e8322140dde7b26827332100504507cec9cc4e
RUN cd /opt/openthread && ./script/cmake-build simulation -DOT_APP_CLI=OFF -DOT_APP_NCP=OFF -DOT_APP_RCP=ON -DOT_FTD=OFF -DOT_MTD=OFF
RUN cd /opt/openthread && ./script/cmake-build posix -DOT_APP_CLI=ON -DOT_DAEMON=OFF -DOT_FTD=ON -DOT_MTD=OFF -DOT_BORDER_AGENT=ON -DOT_PLATFORM_UDP=ON -DOT_PLATFORM_NETIF=OFF -DOT_BORDER_AGENT_MESHCOP_SERVICE=OFF -DOT_BORDER_AGENT_EPSKC=OFF
COPY ot-commissioner /opt/ot-commissioner
COPY app-source /opt/app-source
COPY app-source.sha256 /lab/app-source.sha256
RUN cd /opt/app-source && sha256sum -c /lab/app-source.sha256
COPY audit_source.py /lab/audit_source.py
RUN python3 /lab/audit_source.py /opt/app-source/native/probe.cpp
RUN cmake -G Ninja -S /opt/app-source -B /opt/app-build -DTNT_WITH_COMMISSIONER=ON -DTNT_COMMISSIONER_SOURCE=/opt/ot-commissioner -DTNT_BUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 && cmake --build /opt/app-build --target thread-network -j2
COPY driver.py /lab/driver.py
ENTRYPOINT ["python3", "/lab/driver.py"]
