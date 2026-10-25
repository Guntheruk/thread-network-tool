#include "probe.hpp"
#include <commissioner/commissioner.hpp>
#include <commissioner/network_data.hpp>
#include <sstream>
namespace tnt {
namespace {
std::string Hex(const ot::commissioner::ByteArray& bytes) {
    static const char d[]="0123456789abcdef";std::string out;
    for(auto b:bytes){out+=d[b>>4];out+=d[b&15];}return out;
}
class QuietHandler final:public ot::commissioner::CommissionerHandler {};
struct PskcWiper {
    ot::commissioner::ByteArray& value;
    ~PskcWiper() {volatile uint8_t* p=value.data();for(size_t i=0;i<value.size();++i)p[i]=0;}
};
}
std::string Probe(const std::string& address,unsigned port,const Dataset& imported) {
    using namespace ot::commissioner;
    Config config;config.mEnableCcm=false;config.mEnableDtlsDebugLogging=false;config.mLogger.reset();
    config.mPSKc.assign(imported.pskc.begin(),imported.pskc.end());
    PskcWiper wipe{config.mPSKc};
    QuietHandler handler;auto commissioner=Commissioner::Create(handler);
    if(commissioner->Init(config)!=ErrorCode::kNone)
        return "{\"schema_version\":1,\"probe_status\":\"error\",\"stage\":\"init\",\"authenticated\":false,\"active_status\":\"unknown\",\"pending_status\":\"unknown\"}";
    if(commissioner->Connect(address,static_cast<uint16_t>(port))!=ErrorCode::kNone)
        return "{\"schema_version\":1,\"probe_status\":\"error\",\"stage\":\"connect\",\"authenticated\":false,\"active_status\":\"unknown\",\"pending_status\":\"unknown\"}";
    constexpr uint16_t fields=ActiveOperationalDataset::kActiveTimestampBit |
        ActiveOperationalDataset::kChannelBit | ActiveOperationalDataset::kExtendedPanIdBit |
        ActiveOperationalDataset::kNetworkNameBit;
    ActiveOperationalDataset active;
    if(commissioner->GetActiveDataset(active,fields)!=ErrorCode::kNone)
        return "{\"schema_version\":1,\"probe_status\":\"partial\",\"authenticated\":true,\"active_status\":\"error\",\"pending_status\":\"unknown\"}";
    constexpr uint16_t pendingFields=PendingOperationalDataset::kPendingTimestampBit |
        PendingOperationalDataset::kActiveTimestampBit | PendingOperationalDataset::kDelayTimerBit;
    PendingOperationalDataset pending;
    bool pending_ok=commissioner->GetPendingDataset(pending,pendingFields)==ErrorCode::kNone;
    bool has_xpan=(active.mPresentFlags & ActiveOperationalDataset::kExtendedPanIdBit)!=0;
    bool has_name=(active.mPresentFlags & ActiveOperationalDataset::kNetworkNameBit)!=0;
    bool has_channel=(active.mPresentFlags & ActiveOperationalDataset::kChannelBit)!=0;
    bool matched=has_xpan && has_name && has_channel && Hex(active.mExtendedPanId)==imported.extended_pan_id &&
        active.mNetworkName==imported.network_name && active.mChannel.mPage==0 && active.mChannel.mNumber==imported.channel;
    std::ostringstream o;
    o<<"{\"schema_version\":1,\"probe_status\":\"completed\",\"authenticated\":true,\"active_status\":\"read\",\"identity_match\":";
    if(!has_xpan||!has_name||!has_channel) o<<"\"unknown\"";
    else o<<(matched?"\"match\"":"\"mismatch\"");
    o<<",\"active_network_name\":";
    if(has_name)o<<JsonString(active.mNetworkName);else o<<"null";
    o<<",\"active_extended_pan_id\":";
    if(has_xpan)o<<JsonString(Hex(active.mExtendedPanId));else o<<"null";
    o<<",\"active_channel\":";
    if(has_channel)o<<active.mChannel.mNumber;else o<<"null";
    o<<",\"pending_status\":\""<<(pending_ok?(pending.mPresentFlags?"present":"empty"):"error")<<"\"}";
    return o.str();
}
}
