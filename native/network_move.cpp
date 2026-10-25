#include "network_move.hpp"
#include "dataset.hpp"
#include <algorithm>
#include <iomanip>
#include <mutex>
#include <sstream>

namespace tnt::move {
namespace {
std::mutex dispatch_mutex;
void Clear(Fields& fields) { for (auto& entry : fields) Wipe(entry.second); fields.clear(); }
uint64_t Integer(const Bytes& bytes) { uint64_t value = 0; for (auto byte : bytes) value = (value << 8) | byte; return value; }
Bytes Encode(uint64_t value, size_t size) { Bytes result(size); for(size_t i=size;i>0;--i) { result[i-1]=value&255; value>>=8; } return result; }
bool Representable(const Fields& fields) {
    static const std::vector<uint8_t> allowed{0,1,2,3,4,5,7,12,14,53};
    return std::all_of(fields.begin(), fields.end(), [](const auto& entry) {
        return std::find(allowed.begin(), allowed.end(), entry.first) != allowed.end();
    });
}
bool EqualActive(const Bytes& raw, const Fields& expected) {
    Fields actual; std::string reason;
    bool matches = DecodeDataset(raw, actual, reason) && actual == expected;
    Clear(actual); return matches;
}
}
void Wipe(Bytes& bytes) { volatile uint8_t* p=bytes.data(); for(size_t i=0;i<bytes.size();++i) p[i]=0; bytes.clear(); }
Request::~Request() { Wipe(source_dataset); Wipe(target_dataset); }
bool DecodeHex(const std::string& hex, Bytes& out) {
    if(hex.empty() || hex.size()>508 || hex.size()%2) return false;
    Bytes bytes;
    for(size_t i=0;i<hex.size();i+=2) {
        unsigned value=0;
        for(size_t j=0;j<2;++j) { char c=hex[i+j]; unsigned digit;
            if(c>='0'&&c<='9')digit=c-'0';else if(c>='a'&&c<='f')digit=c-'a'+10;
            else if(c>='A'&&c<='F')digit=c-'A'+10;else { Wipe(bytes); return false; }
            value=value*16+digit;
        } bytes.push_back(static_cast<uint8_t>(value));
    } out=std::move(bytes);return true;
}
bool DecodeDataset(const Bytes& bytes, Fields& fields, std::string& reason) {
    reason="invalid_dataset";
    if(bytes.empty()||bytes.size()>254)return false;
    Fields result; size_t offset=0;
    while(offset<bytes.size()) {
        if(offset+2>bytes.size()) { Clear(result);return false; }
        auto type=bytes[offset++];auto size=bytes[offset++];
        if(offset+size>bytes.size()||result.count(type)) {Clear(result);return false;}
        result[type]=Bytes(bytes.begin()+offset,bytes.begin()+offset+size);offset+=size;
    }
    std::ostringstream hex;for(auto byte:bytes)hex<<std::hex<<std::setw(2)<<std::setfill('0')<<unsigned(byte);
    Dataset parsed;std::string error;
    if(!ParseDataset(hex.str().c_str(),parsed,error)||result.count(51)||result.count(52)||
       !result.count(14)||result[14].size()!=8||Integer(result[14])==UINT64_MAX) {Clear(result);return false;}
    // A full operational snapshot includes every mandatory Active Dataset component.
    for(auto type:{0,1,2,3,4,5,7,12,14,53})if(!result.count(type)){Clear(result);return false;}
    fields=std::move(result);return true;
}
std::string DispositionName(Disposition value) {
    switch(value){case Disposition::proven_not_sent:return "proven_not_sent";case Disposition::accepted:return "accepted";
        case Disposition::rejected:return "rejected";case Disposition::uncertain:return "uncertain";}return "uncertain";
}
std::string ResultJson(const Result& result) {
    return "{\"schema_version\":1,\"operation_id\":"+JsonString(result.operation_id)+",\"disposition\":"+JsonString(DispositionName(result.disposition))+
        ",\"reason\":"+JsonString(result.reason)+",\"petitions\":"+std::to_string(result.petitions)+
        ",\"pending_set_invocations\":"+std::to_string(result.pending_set_invocations)+"}";
}
Operation::Operation(Transport& transport,Clock clock):transport_(transport),now_(std::move(clock)){}
Operation::~Operation(){Clear(source_);Clear(target_);Clear(pending_);}
bool Operation::CheckSnapshots(std::string& reason) {
    auto started=now_();
    for(const auto& endpoint:request_.sources) {
        auto read=transport_.Read(endpoint,source_.at(4));
        bool ok=read.ok&&read.pending.empty()&&EqualActive(read.active,source_);
        Wipe(read.active);Clear(read.pending);
        if(!ok){reason="source_snapshot_changed_or_unavailable";return false;}
    }
    auto read=transport_.Read(request_.target,target_.at(4));
    bool ok=read.ok&&read.pending.empty()&&EqualActive(read.active,target_);
    Wipe(read.active);Clear(read.pending);
    if(!ok){reason="target_snapshot_changed_or_unavailable";return false;}
    if(now_()-started>std::chrono::seconds(30)){reason="preflight_deadline";return false;}
    return true;
}
bool Operation::Prepare(Request request,std::string& reason) {
    std::lock_guard<std::mutex> lock(mutex_);
    if(prepare_attempted_||consumed_){reason="operation_consumed";return false;}
    prepare_attempted_=true;
    if(request.sources.empty()||request.sources.size()>8||request.operation_id.size()!=32||
       !std::all_of(request.operation_id.begin(),request.operation_id.end(),[](char c){return(c>='0'&&c<='9')||(c>='a'&&c<='f');})||
       !request.controlled_empty||!request.manual_recovery){reason="authorization_incomplete";return false;}
    if(!DecodeDataset(request.source_dataset,source_,reason)||!DecodeDataset(request.target_dataset,target_,reason))return false;
    if(!Representable(source_)||!Representable(target_)){reason="unsupported_dataset_fields";return false;}
    if(source_.at(2)==target_.at(2)){reason="same_network";return false;}
    for(size_t i=0;i<request.sources.size();++i) {
        const auto& endpoint=request.sources[i];
        if(endpoint.address.empty()||!endpoint.port||
           (endpoint.address==request.target.address&&endpoint.port==request.target.port)) {reason="endpoint_role_conflict";return false;}
        for(size_t j=0;j<i;++j)if(endpoint.address==request.sources[j].address&&endpoint.port==request.sources[j].port){reason="duplicate_endpoint";return false;}
    }
    if(request.target.address.empty()||!request.target.port){reason="invalid_endpoint";return false;}
    bool key_change=source_.at(5)!=target_.at(5);
    uint64_t source_stamp=Integer(source_.at(14)),target_stamp=Integer(target_.at(14));
    if(!key_change&&target_stamp<=source_stamp){reason="timestamp_rollback_without_key_change";return false;}
    if(request.delay_ms<(key_change?300000u:30000u)||request.delay_ms>600000u){reason="unsupported_delay";return false;}
    uint64_t seconds=std::max(source_stamp,target_stamp)>>16;
    if(seconds>=((uint64_t{1}<<48)-1)||request.target_dataset.size()+20>254){reason="pending_dataset_overflow";return false;}
    pending_=target_;pending_[51]=Encode((seconds+1)<<16,8);pending_[52]=Encode(request.delay_ms,4);
    request_=std::move(request);
    if(!CheckSnapshots(reason))return false;
    prepared_at_=now_();ready_=true;reason="ready";return true;
}
Result Operation::Confirm(Fence& fence) {
    std::scoped_lock lock(dispatch_mutex,mutex_);
    // A repeated confirmation must preserve this operation's dispatch evidence.
    // In particular an uncertain SET can never become proof that nothing was sent.
    Result& result=confirmation_result_;
    if(consumed_)return result;
    result.operation_id=request_.operation_id;
    consumed_=true;
    if(!ready_){return result;}
    if(now_()-prepared_at_>std::chrono::seconds(30)){result.reason="review_expired";return result;}
    if(!CheckSnapshots(result.reason))return result;
    // The caller must separately fence before launching a future worker. This local fence
    // also prevents this lab worker from dispatching while any prior operation is unresolved.
    if(!fence.Arm(request_.operation_id)){result.reason="unresolved_operation_fence";return result;}
    result.petitions=1;
    if(!transport_.PetitionSource(request_.sources.front(),source_.at(4))){result.reason="petition_failed";return result;}
    if(!CheckSnapshots(result.reason))return result;
    if(now_()-prepared_at_>std::chrono::seconds(30)){result.reason="review_expired";return result;}
    dispatched_=true;result.pending_set_invocations=1;result.disposition=Disposition::uncertain;result.reason="submission_unknown";
    try { result.disposition=transport_.SetSourcePending(pending_); }
    catch(...) { return result; }
    if(result.disposition==Disposition::proven_not_sent)result.disposition=Disposition::uncertain;
    result.reason=result.disposition==Disposition::accepted?"pending_accepted":
        result.disposition==Disposition::rejected?"pending_rejected":"submission_unknown";
    return result;
}
bool Operation::ObservePending(std::string& reason) {
    std::lock_guard<std::mutex> lock(mutex_);
    if(!ready_||!dispatched_){reason="observation_unavailable";return false;}
    transport_.ResetReadSessions();
    for(const auto& endpoint:request_.sources) {
        auto read=transport_.Read(endpoint,source_.at(4));
        bool matches=read.ok && read.pending.count(52) && read.pending.at(52).size()==4;
        if(matches) {
            auto remaining=Integer(read.pending.at(52));
            matches=remaining>0&&remaining<=request_.delay_ms;
            read.pending[52]=pending_.at(52);
            matches=matches&&read.pending==pending_&&EqualActive(read.active,source_);
        }
        Wipe(read.active);Clear(read.pending);
        if(!matches){reason="pending_not_observed";return false;}
    }
    auto read=transport_.Read(request_.target,target_.at(4));
    bool unchanged=read.ok&&read.pending.empty()&&EqualActive(read.active,target_);
    Wipe(read.active);Clear(read.pending);reason=unchanged?"pending_propagated":"target_changed_or_unavailable";return unchanged;
}
bool Operation::Observe(const std::vector<Endpoint>& endpoints,const Endpoint& refreshed_target,std::string& reason) {
    std::lock_guard<std::mutex> lock(mutex_);
    if(!ready_||!dispatched_||endpoints.size()!=request_.sources.size()){reason="observation_unavailable";return false;}
    for(size_t i=0;i<endpoints.size();++i) {
        if(endpoints[i].address.empty()||!endpoints[i].port||
           (endpoints[i].address==refreshed_target.address&&endpoints[i].port==refreshed_target.port)) {reason="endpoint_role_conflict";return false;}
        for(size_t j=0;j<i;++j)if(endpoints[i].address==endpoints[j].address&&endpoints[i].port==endpoints[j].port){reason="duplicate_endpoint";return false;}
    }
    if(refreshed_target.address.empty()||!refreshed_target.port){reason="invalid_endpoint";return false;}
    transport_.ResetReadSessions();
    for(const auto& endpoint:endpoints) {
        auto read=transport_.Read(endpoint,target_.at(4));
        bool ok=read.ok&&read.pending.empty()&&EqualActive(read.active,target_);
        Wipe(read.active);Clear(read.pending);if(!ok){reason="source_not_converged";return false;}
    }
    auto target=transport_.Read(refreshed_target,target_.at(4));
    bool ok=target.ok&&target.pending.empty()&&EqualActive(target.active,target_);
    Wipe(target.active);Clear(target.pending);reason=ok?"converged":"target_changed_or_unavailable";return ok;
}
}
