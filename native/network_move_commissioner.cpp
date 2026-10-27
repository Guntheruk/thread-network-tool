#include "network_move_commissioner.hpp"
#include <commissioner/commissioner.hpp>
#include <memory>
#include <cstdio>
#include <algorithm>

namespace tnt::move {
namespace {
using namespace ot::commissioner;
Bytes Number(uint64_t n,size_t len){Bytes out(len);for(size_t i=len;i>0;--i){out[i-1]=n&255;n>>=8;}return out;}
uint64_t Number(const Bytes& bytes){uint64_t n=0;for(auto byte:bytes)n=(n<<8)|byte;return n;}
class QuietHandler final:public CommissionerHandler{};
struct Session {
    QuietHandler handler;
    Endpoint endpoint;
    Bytes pskc;
    std::shared_ptr<Commissioner> commissioner;
    ~Session(){Wipe(pskc);}
};
Fields PendingFields(const PendingOperationalDataset& p) {
    Fields out;
    if(p.mPresentFlags&p.kActiveTimestampBit)out[14]=Number(p.mActiveTimestamp.Encode(),8);
    if(p.mPresentFlags&p.kChannelBit)out[0]=Bytes{p.mChannel.mPage,uint8_t(p.mChannel.mNumber>>8),uint8_t(p.mChannel.mNumber)};
    if(p.mPresentFlags&p.kLegacyWakeupChannelBit)out[74]=Bytes{p.mLegacyWakeupChannel.mPage,uint8_t(p.mLegacyWakeupChannel.mNumber>>8),uint8_t(p.mLegacyWakeupChannel.mNumber)};
    if(p.mPresentFlags&p.kPanIdBit)out[1]=Number(p.mPanId,2);
    if(p.mPresentFlags&p.kExtendedPanIdBit)out[2]=p.mExtendedPanId;
    if(p.mPresentFlags&p.kNetworkNameBit)out[3]=Bytes(p.mNetworkName.begin(),p.mNetworkName.end());
    if(p.mPresentFlags&p.kPSKcBit)out[4]=p.mPSKc;
    if(p.mPresentFlags&p.kNetworkMasterKeyBit)out[5]=p.mNetworkMasterKey;
    if(p.mPresentFlags&p.kMeshLocalPrefixBit)out[7]=p.mMeshLocalPrefix;
    if(p.mPresentFlags&p.kSecurityPolicyBit) {
        Bytes policy=Number(p.mSecurityPolicy.mRotationTime,2);policy.insert(policy.end(),p.mSecurityPolicy.mFlags.begin(),p.mSecurityPolicy.mFlags.end());out[12]=std::move(policy);
    }
    if(p.mPresentFlags&p.kChannelMaskBit) {
        Bytes mask;for(auto& entry:p.mChannelMask){mask.push_back(entry.mPage);mask.push_back(uint8_t(entry.mMasks.size()));mask.insert(mask.end(),entry.mMasks.begin(),entry.mMasks.end());}out[53]=std::move(mask);
    }
    if(p.mPresentFlags&p.kPendingTimestampBit)out[51]=Number(p.mPendingTimestamp.Encode(),8);
    if(p.mPresentFlags&p.kDelayTimerBit)out[52]=Number(p.mDelayTimer,4);
    return out;
}
// Never pass a lossy typed GET through the guard. Empty means exactly zero wire
// bytes; every nonempty response must be a complete, supported Pending Dataset.
bool DecodePendingFields(const Bytes& raw, Fields& out) {
    for(auto& f:out)Wipe(f.second);out.clear();
    if(raw.empty())return true;
    if(raw.size()>254)return false;
    Fields fields;Bytes active;size_t offset=0;
    auto clear=[&]{for(auto& f:fields)Wipe(f.second);Wipe(active);};
    while(offset<raw.size()) {
        if(raw.size()-offset<2){clear();return false;}
        auto type=raw[offset++];size_t size=raw[offset++];
        if(size>raw.size()-offset||fields.count(type)){clear();return false;}
        fields[type]=Bytes(raw.begin()+offset,raw.begin()+offset+size);
        if(type!=51&&type!=52){active.push_back(type);active.push_back(uint8_t(size));active.insert(active.end(),raw.begin()+offset,raw.begin()+offset+size);}
        offset+=size;
    }
    Fields decoded;std::string reason;
    bool valid=fields.count(51)&&fields.at(51).size()==8&&Number(fields.at(51))!=UINT64_MAX&&
        fields.count(52)&&fields.at(52).size()==4&&DecodeDataset(active,decoded,reason);
    static const std::vector<uint8_t> supported{0,1,2,3,4,5,7,12,14,51,52,53,74};
    for(const auto& f:fields)if(std::find(supported.begin(),supported.end(),f.first)==supported.end())valid=false;
    for(auto& f:decoded)Wipe(f.second);
    Wipe(active);
    if(!valid){clear();return false;}
    out=std::move(fields);return true;
}
bool BuildPending(const Fields& fields, PendingOperationalDataset& p) {
    Bytes raw;for(const auto& f:fields){if(f.second.size()>255)return false;raw.push_back(f.first);raw.push_back(uint8_t(f.second.size()));raw.insert(raw.end(),f.second.begin(),f.second.end());}
    Fields checked;bool valid=DecodePendingFields(raw,checked)&&!checked.empty();Wipe(raw);
    for(auto& f:checked)Wipe(f.second);
    if(!valid)return false;
    p.mPresentFlags=p.kActiveTimestampBit|p.kChannelBit|p.kChannelMaskBit|p.kExtendedPanIdBit|p.kMeshLocalPrefixBit|
        p.kNetworkMasterKeyBit|p.kNetworkNameBit|p.kPanIdBit|p.kPSKcBit|p.kSecurityPolicyBit|p.kPendingTimestampBit|p.kDelayTimerBit;
    p.mActiveTimestamp=Timestamp::Decode(Number(fields.at(14)));
    p.mChannel={fields.at(0)[0],uint16_t(Number(Bytes(fields.at(0).begin()+1,fields.at(0).end())))};
    if(fields.count(74)){p.mPresentFlags|=p.kLegacyWakeupChannelBit;p.mLegacyWakeupChannel={fields.at(74)[0],uint16_t(Number(Bytes(fields.at(74).begin()+1,fields.at(74).end())))};}
    p.mPanId=uint16_t(Number(fields.at(1)));p.mExtendedPanId=fields.at(2);
    p.mNetworkName=std::string(fields.at(3).begin(),fields.at(3).end());p.mPSKc=fields.at(4);p.mNetworkMasterKey=fields.at(5);p.mMeshLocalPrefix=fields.at(7);
    const auto& policy=fields.at(12);p.mSecurityPolicy.mRotationTime=uint16_t((policy[0]<<8)|policy[1]);p.mSecurityPolicy.mFlags=Bytes(policy.begin()+2,policy.end());
    const auto& masks=fields.at(53);size_t offset=0;
    while(offset<masks.size()){ChannelMaskEntry entry;entry.mPage=masks.at(offset++);size_t size=masks.at(offset++);entry.mMasks=Bytes(masks.begin()+offset,masks.begin()+offset+size);offset+=size;p.mChannelMask.push_back(entry);}
    p.mPendingTimestamp=Timestamp::Decode(Number(fields.at(51)));p.mDelayTimer=uint32_t(Number(fields.at(52)));
    auto projected=PendingFields(p);bool exact=projected==fields;for(auto& f:projected)Wipe(f.second);return exact;
}
void WipePending(PendingOperationalDataset& p){Wipe(p.mNetworkMasterKey);Wipe(p.mPSKc);}
class Adapter final:public Transport {
    std::vector<std::unique_ptr<Session>> sessions_;
    Session* source_=nullptr;
    bool discard_, trace_;
    void Trace(const char* event,int code=-1){if(trace_){if(code<0)std::fprintf(stderr,"%s\n",event);else std::fprintf(stderr,"%s:%d\n",event,code);std::fflush(stderr);}}
    Session* Connect(const Endpoint& endpoint,const Bytes& pskc) {
        for(auto& session:sessions_)if(session->endpoint.address==endpoint.address&&session->endpoint.port==endpoint.port&&session->pskc==pskc)return session.get();
        auto session=std::make_unique<Session>();session->endpoint=endpoint;session->pskc=pskc;
        Config config;config.mEnableCcm=false;config.mEnableDtlsDebugLogging=false;config.mLogger.reset();config.mPSKc=pskc;
        session->commissioner=Commissioner::Create(session->handler);
        auto error=session->commissioner->Init(config);Wipe(config.mPSKc);
        if(error!=ErrorCode::kNone||session->commissioner->Connect(endpoint.address,endpoint.port)!=ErrorCode::kNone)return nullptr;
        auto pointer=session.get();sessions_.push_back(std::move(session));return pointer;
    }
public:
    explicit Adapter(bool discard,bool trace):discard_(discard),trace_(trace){}
    void ResetReadSessions() override {source_=nullptr;sessions_.clear();}
    ReadResult Read(const Endpoint& endpoint,const Bytes& pskc) override {
        ReadResult read;auto session=Connect(endpoint,pskc);if(!session)return read;
        Bytes pending;
        Trace("active_begin");auto active_error=session->commissioner->GetRawActiveDataset(read.active,0);Trace("active_result",int(active_error.GetCode()));if(active_error!=ErrorCode::kNone)return read;
        Trace("pending_begin");auto pending_error=session->commissioner->GetRawPendingDataset(pending,0);Trace("pending_result",int(pending_error.GetCode()));if(pending_error!=ErrorCode::kNone){Wipe(pending);return read;}
        read.ok=DecodePendingFields(pending,read.pending);Wipe(pending);return read;
    }
    bool PetitionSource(const Endpoint& endpoint,const Bytes& pskc) override {
        source_=Connect(endpoint,pskc);if(!source_)return false;
        Trace("petition_begin");std::string existing;auto error=source_->commissioner->Petition(existing,endpoint.address,endpoint.port);Trace("petition_result",int(error.GetCode()));return error==ErrorCode::kNone;
    }
    Disposition SetSourcePending(const Fields& fields) override {
        if(!source_)return Disposition::proven_not_sent;
        PendingOperationalDataset p;
        if(!BuildPending(fields,p)){WipePending(p);return Disposition::proven_not_sent;}
        Trace("set_begin");auto error=source_->commissioner->SetPendingDataset(p);Trace("set_result",int(error.GetCode()));WipePending(p);
        // Destroy directly after the synchronous result. Do not enqueue async Disconnect
        // immediately before CommissionerSafe destruction: its one-item Invoke queue
        // can coalesce that notification with destructor Stop and block shutdown.
        // No Resign/SET is sent to the target, and no old commissioner is kept across activation.
        source_=nullptr;sessions_.clear();
        if(discard_)return Disposition::uncertain; // Explicit lab API-result loss; not wire-loss emulation.
        if(error==ErrorCode::kNone)return Disposition::accepted;
        if(error==ErrorCode::kRejected)return Disposition::rejected;
        return Disposition::uncertain;
    }
};
}
std::unique_ptr<Transport> CreateCommissionerTransport(bool discard,bool trace){return std::make_unique<Adapter>(discard,trace);}
}
