FROM tnt-commissioner-lab@sha256:14522db1edfe1186a74ff0de1882b1a9577d24428e80da2542b79c860c5fb6f5
# Fresh build context; Stage 1 sources and historical manifest remain unchanged.
COPY app-source /opt/move-source
COPY move-source.sha256 /lab/move-source.sha256
RUN cd /opt/move-source && sha256sum -c /lab/move-source.sha256
RUN cmake -G Ninja -S /opt/move-source -B /opt/move-build -DTNT_WITH_COMMISSIONER=ON -DTNT_COMMISSIONER_SOURCE=/opt/ot-commissioner -DTNT_BUILD_MOVE_LAB=ON -DTNT_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 && cmake --build /opt/move-build --target thread-network thread-network-move-lab tnt-network-move-tests -j2 && ctest --test-dir /opt/move-build -R '^native-network-move$' --output-on-failure
COPY driver.py /lab/driver.py
COPY move_driver.py /lab/move_driver.py
ENV LD_LIBRARY_PATH=/opt/move-build
RUN cp /opt/move-build/thread-network /opt/move-build/thread-network-move-lab /opt/app-build/
ENTRYPOINT ["python3", "/lab/move_driver.py"]
