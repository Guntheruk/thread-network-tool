#include "probe.hpp"
#include <cstdlib>
#include <cstdint>
#include <string>

#define CHECK(condition) do { if (!(condition)) std::abort(); } while (false)

int main() {
    using ot::commissioner::ActiveOperationalDataset;
    using ot::commissioner::Timestamp;

    // Synthetic MeshCoP Active Timestamp TLV: type 14, length 8,
    // seconds=1, ticks=1, authoritative U=1 in network byte order.
    constexpr uint8_t raw_tlv[] = {0x0e, 0x08, 0x00, 0x00, 0x00,
                                   0x00, 0x00, 0x01, 0x00, 0x03};
    CHECK(raw_tlv[0] == 14 && raw_tlv[1] == 8);
    uint64_t wire = 0;
    for (unsigned i = 2; i < sizeof(raw_tlv); ++i) wire = (wire << 8) | raw_tlv[i];
    CHECK(wire == 0x0000000000010003ULL);

    ActiveOperationalDataset active;
    active.mPresentFlags = ActiveOperationalDataset::kActiveTimestampBit;
    active.mActiveTimestamp = Timestamp::Decode(wire);
    CHECK(active.mActiveTimestamp.mSeconds == 1);
    CHECK(active.mActiveTimestamp.mTicks == 1);
    CHECK(active.mActiveTimestamp.mU == 1);
    CHECK(tnt::ActiveTimestampJson(active) == "\"0000000000010003\"");

    constexpr uint8_t high_tlv[] = {0x0e, 0x08, 0xab, 0xcd, 0xef,
                                    0x12, 0x34, 0x56, 0x24, 0x69};
    wire = 0;
    for (unsigned i = 2; i < sizeof(high_tlv); ++i) wire = (wire << 8) | high_tlv[i];
    active.mActiveTimestamp = Timestamp::Decode(wire);
    CHECK(active.mActiveTimestamp.mSeconds == 0xabcdef123456ULL);
    CHECK(active.mActiveTimestamp.mTicks == 0x1234);
    CHECK(active.mActiveTimestamp.mU == 1);
    CHECK(tnt::ActiveTimestampJson(active) == "\"abcdef1234562469\"");

    active.mActiveTimestamp = Timestamp::Decode(0);
    CHECK(tnt::ActiveTimestampJson(active) == "\"0000000000000000\"");

    active.mPresentFlags = 0;
    CHECK(tnt::ActiveTimestampJson(active) == "null");
    active.mPresentFlags = ActiveOperationalDataset::kNetworkMasterKeyBit |
                           ActiveOperationalDataset::kPSKcBit;
    active.mNetworkMasterKey.assign(16, 0xab);
    active.mPSKc.assign(16, 0xcd);
    const std::string missing = tnt::ActiveTimestampJson(active);
    CHECK(missing == "null");
    CHECK(missing.find("abab") == std::string::npos);
    CHECK(missing.find("cdcd") == std::string::npos);
}
