FROM openthread/environment@sha256:8fc56c561f0e65ce039cbb8c665d2e5411f9c573ebe1d142417c65a47394dd26

ARG OT_COMMIT=53e8322140dde7b26827332100504507cec9cc4e
COPY openthread /opt/openthread
RUN test "$(git -C /opt/openthread rev-parse HEAD)" = "$OT_COMMIT" && \
    cd /opt/openthread && \
    ./script/cmake-build simulation -DOT_APP_CLI=ON -DOT_APP_NCP=OFF \
      -DOT_APP_RCP=OFF -DOT_FTD=ON -DOT_MTD=OFF -DOT_COMMISSIONER=ON

COPY protocol_lab.py /lab/protocol_lab.py
ENTRYPOINT ["python3", "/lab/protocol_lab.py"]
