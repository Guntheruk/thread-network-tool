// Synthetic fixtures only. This exercises the actual patched upstream codec.
#include <algorithm>
#include <cstdlib>
#include <iostream>
#include "library/commissioner_impl.hpp"

namespace ot { namespace commissioner {
class CommissionerTestPeer {
public:
    static Error Decode(ActiveOperationalDataset &out, const ByteArray &wire) {
        return CommissionerImpl::DecodeActiveOperationalDataset(out, wire);
    }
    static Error DecodePending(PendingOperationalDataset &out, const ByteArray &wire) {
        coap::Response response{coap::Type::kAcknowledgment, coap::Code::kChanged};
        response.Append(wire);
        return CommissionerImpl::DecodePendingOperationalDataset(out, response);
    }
    static Error Encode(coap::Request &out, const PendingOperationalDataset &dataset) {
        return CommissionerImpl::EncodePendingOperationalDataset(out, dataset);
    }
    static ByteArray GetTypes(uint16_t flags) {
        return CommissionerImpl::GetPendingOperationalDatasetTlvs(flags);
    }
};
}}
using namespace ot::commissioner;
static unsigned checks = 0;
static void check(bool ok, const char *label) {
    ++checks;
    if (!ok) { std::cerr << "FAILED: " << label << '\n'; std::exit(1); }
}
static bool success(Error error) { return error == ErrorCode::kNone; }
static ByteArray wake(unsigned page, unsigned channel) {
    return {74, 3, static_cast<uint8_t>(page), static_cast<uint8_t>(channel >> 8), static_cast<uint8_t>(channel)};
}
static ByteArray fixture(bool present, unsigned channel = 11) {
    // Active timestamp plus ordinary channel, pending timestamp and delay.
    ByteArray bytes = {14,8,0,0,0,0,0,1,0,0, 0,3,0,0,15,
                      51,8,0,0,0,0,0,2,0,0, 52,4,0,0,0x75,0x30};
    // Remaining Active fields use explicit synthetic values, never household credentials.
    auto append = [&](uint8_t type, ByteArray value) {
        bytes.push_back(type); bytes.push_back(static_cast<uint8_t>(value.size()));
        bytes.insert(bytes.end(),value.begin(),value.end());
    };
    append(1,{0x12,0x34}); append(2,{1,2,3,4,5,6,7,8});
    append(3,{'L','a','b','M','e','s','h'});
    append(4,ByteArray(16,0x11)); append(5,ByteArray(16,0x22));
    append(7,{0xfd,0,0,0,0,0,0,1}); append(12,{0x02,0xa0,0xf7,0xf8});
    append(53,{0,4,0,0x1f,0xff,0xe0});
    if (present) { auto value = wake(0,channel); bytes.insert(bytes.end(),value.begin(),value.end()); }
    return bytes;
}
static std::map<uint8_t,ByteArray> fields(const ByteArray &wire) {
    std::map<uint8_t,ByteArray> result;
    size_t offset = 0;
    while (offset < wire.size()) {
        check(wire.size()-offset >= 2, "complete header");
        unsigned type = wire[offset++], length = wire[offset++];
        check(length <= wire.size()-offset, "complete value");
        check(!result.count(type), "one field of each type");
        result[type] = ByteArray(wire.begin()+offset,wire.begin()+offset+length);
        offset += length;
    }
    return result;
}
int main() {
    static_assert((ActiveOperationalDataset::kLegacyWakeupChannelBit &
                   (PendingOperationalDataset::kDelayTimerBit | PendingOperationalDataset::kPendingTimestampBit)) == 0,
                  "present bit collides with pending fields");
    for (unsigned channel : {11u, 26u}) {
        auto input = fixture(true,channel);
        PendingOperationalDataset decoded;
        check(success(CommissionerTestPeer::DecodePending(decoded,input)), "decode actual pending codec");
        check(decoded.mPresentFlags & ActiveOperationalDataset::kLegacyWakeupChannelBit,"present legacy field");
        check(decoded.mLegacyWakeupChannel.mPage == 0 && decoded.mLegacyWakeupChannel.mNumber == channel,
              "decode exact page and big-endian channel");
        coap::Request request{coap::Type::kConfirmable,coap::Code::kPost};
        check(success(CommissionerTestPeer::Encode(request,decoded)), "encode actual pending codec");
        check(fields(input) == fields(request.GetPayload()), "all type/value bytes preserved");
        auto types = CommissionerTestPeer::GetTypes(decoded.mPresentFlags);
        check(std::count(types.begin(),types.end(),74) == 1,"pending GET requests74 exactly once");
    }
    PendingOperationalDataset absent;
    check(success(CommissionerTestPeer::DecodePending(absent,fixture(false))),"decode absent74");
    check(!(absent.mPresentFlags & ActiveOperationalDataset::kLegacyWakeupChannelBit),"absence retained");
    coap::Request noWake{coap::Type::kConfirmable,coap::Code::kPost};
    check(success(CommissionerTestPeer::Encode(noWake,absent)),"encode absent74");
    check(fields(noWake.GetPayload()) == fields(fixture(false)),"absence roundtrip exact");
    auto absentTypes = CommissionerTestPeer::GetTypes(absent.mPresentFlags);
    check(std::count(absentTypes.begin(),absentTypes.end(),74)==0,"GET omits absent74");
    unsigned negatives=0;
    auto reject = [&](ByteArray input) {
        ActiveOperationalDataset output;
        check(!success(CommissionerTestPeer::Decode(output,input)),"invalid74 rejects before permissive parser");
        PendingOperationalDataset pending;
        check(!success(CommissionerTestPeer::DecodePending(pending,input)),"pending decode also rejects invalid74");
        ++negatives;
    };
    for (unsigned length : {0u,1u,2u,4u}) {
        ByteArray malformed{74,static_cast<uint8_t>(length)};
        malformed.resize(2+length,0); reject(malformed);
    }
    reject({74}); reject({74,3,0,0}); reject(wake(1,11));
    for (unsigned channel : {0u,10u,27u,65535u}) reject(wake(0,channel));
    auto duplicate=wake(0,11), second=wake(0,26);
    duplicate.insert(duplicate.end(),second.begin(),second.end()); reject(duplicate);
    for (unsigned channel : {0u,10u,27u,65535u}) {
        PendingOperationalDataset invalid;
        invalid.mPresentFlags |= ActiveOperationalDataset::kLegacyWakeupChannelBit;
        invalid.mLegacyWakeupChannel={0,static_cast<uint16_t>(channel)};
        coap::Request request{coap::Type::kConfirmable,coap::Code::kPost};
        check(!success(CommissionerTestPeer::Encode(request,invalid)),"invalid typed channel encode rejects");
        check(request.GetPayload().empty(),"invalid channel appends no payload");
        ++negatives;
    }
    PendingOperationalDataset invalidPage;
    invalidPage.mPresentFlags |= ActiveOperationalDataset::kLegacyWakeupChannelBit;
    invalidPage.mLegacyWakeupChannel={1,11};
    coap::Request invalidPageRequest{coap::Type::kConfirmable,coap::Code::kPost};
    check(!success(CommissionerTestPeer::Encode(invalidPageRequest,invalidPage)),"invalid typed page encode rejects");
    check(invalidPageRequest.GetPayload().empty(),"invalid page appends no payload");
    ++negatives;
    check(tlv::IsDatasetParameter(true,tlv::Type::kLegacyWakeupChannel),"active dataset field recognized");
    check(tlv::IsDatasetParameter(false,tlv::Type::kLegacyWakeupChannel),"pending dataset field recognized");
    check(!tlv::IsDatasetParameter(true,static_cast<tlv::Type>(200)),
          "unknown field is not an operational dataset parameter; adapter must reject it");
    // This bounded patch preserves generic upstream unknown-TLV semantics.
    // Adapter preflight must reject every unsupported type BEFORE projection.
    // The public typed setter is still the only write API. This compile-time
    // check fails if an accidental incompatible/raw-only interface is substituted.
    using PublicPendingSetter=Error (Commissioner::*)(const PendingOperationalDataset &);
    PublicPendingSetter setter=static_cast<PublicPendingSetter>(&Commissioner::SetPendingDataset);
    check(setter != nullptr,"existing public typed Pending SET remains available");
    using RawPendingGetter=Error (Commissioner::*)(ByteArray &, uint16_t);
    RawPendingGetter getter=static_cast<RawPendingGetter>(&Commissioner::GetRawPendingDataset);
    check(getter != nullptr,"bounded read-only raw Pending GET public API available");
    std::cout << checks << " native checks; 3 roundtrips; " << negatives << " negative codec fixtures passed\n";
}
