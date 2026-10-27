FROM tnt-full-app:787ace4
COPY test_network_key_counter.cpp /diagnostic/test_network_key_counter.cpp
COPY reset-own-counter.patch /diagnostic/reset-own-counter.patch
COPY run.sh /diagnostic/run.sh
ENTRYPOINT ["bash", "/diagnostic/run.sh"]
