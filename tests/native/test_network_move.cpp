#include "network_move.hpp"
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#define CHECK(x) do { if(!(x)){std::cerr<<"CHECK failed line "<<__LINE__<<": " #x "\n";std::exit(1);} }while(0)
using namespace tnt::move;
namespace {
Bytes N(uint64_t n,size_t size){Bytes b(size);for(size_t i=size;i>0;--i){b[i-1]=n&255;n>>=8;}return b;}
Fields Fixture(bool target=false,uint64_t stamp=20,uint8_t key=0x11){return {
    {0,{0,0,15}},{1,{0x12,0x34}},{2,Bytes(8,target?2:1)},{3,{'L','a','b'}},{4,Bytes(16,target?0xbb:0xaa)},
    {5,Bytes(16,key)},{7,{0xfd,0,0,0,0,0,0,1}},{12,{0,0,0}},{14,N(stamp<<16,8)},{53,{0,4,0,0x1f,0xff,0xe0}}};}
Bytes Raw(const Fields& fields){Bytes b;for(auto& f:fields){b.push_back(f.first);b.push_back(uint8_t(f.second.size()));b.insert(b.end(),f.second.begin(),f.second.end());}return b;}
Request RequestFor(const Fields& source,const Fields& target,uint32_t delay=300000){Request r;r.operation_id=std::string(32,'a');r.sources={{"::1",1001},{"::1",1002}};r.target={"::1",1003};r.source_dataset=Raw(source);r.target_dataset=Raw(target);r.controlled_empty=true;r.manual_recovery=true;r.delay_ms=delay;return r;}
struct Fake final:Transport {
    Fields source=Fixture(),target=Fixture(true,10,0x22),source_pending,target_pending,captured;
    unsigned reads=0,petitions=0,sets=0;uint16_t petition_port=0;bool petition_ok=true,throw_set=false,unavailable=false;
    std::function<void()> on_petition;
    Disposition response=Disposition::accepted;
    ReadResult Read(const Endpoint& endpoint,const Bytes& pskc)override{
        ++reads;bool is_target=endpoint.port==1003;auto& fields=is_target?target:source;
        if(unavailable||fields.at(4)!=pskc)return {};
        return {true,Raw(fields),is_target?target_pending:source_pending};
    }
    bool PetitionSource(const Endpoint& endpoint,const Bytes&)override{++petitions;petition_port=endpoint.port;if(on_petition)on_petition();return petition_ok;}
    Disposition SetSourcePending(const Fields& pending)override{++sets;captured=pending;if(throw_set)throw std::runtime_error("secret exception");if(response==Disposition::accepted)source_pending=pending;return response;}
};
struct Marker final:Fence{bool allow=true;unsigned calls=0;std::string id;bool Arm(const std::string& operation)override{++calls;id=operation;return allow;}};
bool Prepare(Operation& op,Fake& fake,std::string& reason){return op.Prepare(RequestFor(fake.source,fake.target),reason);}
}
int main(){
    unsigned cases=0;
    // Actual pinned timestamp rule matrix: key change permits older/equal target; unchanged key requires newer.
    for(bool different:{false,true})for(uint64_t target_stamp:{10u,20u,30u}){
        Fake fake;fake.target=Fixture(true,target_stamp,different?0x22:0x11);Operation op(fake);std::string reason;
        bool expected=different||target_stamp>20;CHECK(Prepare(op,fake,reason)==expected);++cases;
        if(expected){Marker marker;auto result=op.Confirm(marker);CHECK(result.disposition==Disposition::accepted);CHECK(fake.sets==1&&fake.petitions==1&&fake.petition_port==1001);CHECK(fake.captured.at(14)==fake.target.at(14));CHECK(fake.captured.at(5)==fake.target.at(5));CHECK(fake.captured.size()==fake.target.size()+2);}
        else CHECK(fake.sets==0&&fake.petitions==0);
    }
    for(bool source:{false,true}){Fake fake;(source?fake.source:fake.target)[74]={0,0,15};Operation op(fake);std::string reason;CHECK(!Prepare(op,fake,reason));CHECK(reason=="unsupported_dataset_fields");CHECK(fake.reads==0);++cases;}
    for(unsigned type:{5u,7u,12u,1u,53u}){Fake fake;Operation op(fake);std::string reason;CHECK(Prepare(op,fake,reason));fake.source[uint8_t(type)][0]^=1;Marker marker;auto result=op.Confirm(marker);CHECK(result.disposition==Disposition::proven_not_sent);CHECK(fake.sets==0&&fake.petitions==0);++cases;}
    {Fake fake;Operation op(fake);std::string reason;CHECK(Prepare(op,fake,reason));fake.on_petition=[&]{fake.target[5][0]^=1;};Marker marker;auto r=op.Confirm(marker);CHECK(r.disposition==Disposition::proven_not_sent&&fake.sets==0&&fake.petitions==1);++cases;}
    {Fake fake;fake.source_pending[51]=N(1,8);Operation op(fake);std::string reason;CHECK(!Prepare(op,fake,reason));CHECK(fake.sets==0);++cases;}
    {Fake fake;fake.target_pending[51]=N(1,8);Operation op(fake);std::string reason;CHECK(!Prepare(op,fake,reason));++cases;}
    {Fake fake;fake.unavailable=true;Operation op(fake);std::string reason;CHECK(!Prepare(op,fake,reason));++cases;}
    {Fake fake;Operation op(fake);std::string reason;auto request=RequestFor(fake.source,fake.target);request.controlled_empty=false;CHECK(!op.Prepare(request,reason));CHECK(fake.reads==0);++cases;}
    {Fake fake;Operation op(fake);std::string reason;auto request=RequestFor(fake.source,fake.target);request.manual_recovery=false;CHECK(!op.Prepare(request,reason));++cases;}
    {Fake fake;Operation op(fake);std::string reason;auto request=RequestFor(fake.source,fake.target);request.sources[1]=request.sources[0];CHECK(!op.Prepare(request,reason));++cases;}
    {Fake fake;Operation op(fake);std::string reason;fake.target[2]=fake.source[2];CHECK(!Prepare(op,fake,reason));CHECK(reason=="same_network");++cases;}
    {Fake fake;Operation op(fake);std::string reason;CHECK(!op.Prepare(RequestFor(fake.source,fake.target,30000),reason));CHECK(reason=="unsupported_delay");++cases;}
    {Fake fake;fake.target[14]=N(0xfffffffffffe0000ULL,8);Operation op(fake);std::string reason;CHECK(Prepare(op,fake,reason));++cases;}
    {Fake fake;fake.target[14]=N(0xffffffffffff0000ULL,8);Operation op(fake);std::string reason;CHECK(!Prepare(op,fake,reason));CHECK(reason=="pending_dataset_overflow");++cases;}
    {Fake fake;auto raw=Raw(fake.source);raw.insert(raw.end(),{14,8,0,0,0,0,0,0,0,1});Fields fields;std::string reason;CHECK(!DecodeDataset(raw,fields,reason));++cases;}
    {Fake fake;auto raw=Raw(fake.source);raw.pop_back();Fields fields;std::string reason;CHECK(!DecodeDataset(raw,fields,reason));++cases;}
    {Fake fake;auto clock=std::chrono::steady_clock::now();Operation op(fake,[&]{return clock;});std::string reason;CHECK(Prepare(op,fake,reason));clock+=std::chrono::seconds(31);Marker marker;auto r=op.Confirm(marker);CHECK(r.disposition==Disposition::proven_not_sent&&r.reason=="review_expired");CHECK(fake.sets==0&&fake.petitions==0);++cases;}
    {Fake fake;Operation op(fake);std::string reason;CHECK(Prepare(op,fake,reason));Marker marker;marker.allow=false;auto r=op.Confirm(marker);CHECK(r.disposition==Disposition::proven_not_sent&&fake.sets==0&&fake.petitions==0);++cases;}
    {Fake fake;fake.petition_ok=false;Operation op(fake);std::string reason;CHECK(Prepare(op,fake,reason));Marker marker;auto r=op.Confirm(marker);CHECK(r.disposition==Disposition::proven_not_sent&&fake.sets==0);++cases;}
    for(auto response:{Disposition::accepted,Disposition::rejected,Disposition::uncertain,Disposition::proven_not_sent}){
        Fake fake;fake.response=response;Operation op(fake);std::string reason;CHECK(Prepare(op,fake,reason));Marker marker;auto r=op.Confirm(marker);CHECK(r.pending_set_invocations==1&&fake.sets==1);CHECK(r.disposition==(response==Disposition::proven_not_sent?Disposition::uncertain:response));
        for(unsigned repeat=0;repeat<2;++repeat){auto again=op.Confirm(marker);CHECK(ResultJson(again)==ResultJson(r));CHECK(again.disposition!=Disposition::proven_not_sent);CHECK(again.pending_set_invocations==1&&again.petitions==1);CHECK(fake.sets==1&&fake.petitions==1&&marker.calls==1);}
        CHECK(ResultJson(r).find("secret")==std::string::npos);++cases;}
    {Fake fake;fake.throw_set=true;Operation op(fake);std::string reason;CHECK(Prepare(op,fake,reason));Marker marker;auto r=op.Confirm(marker);CHECK(r.disposition==Disposition::uncertain&&fake.sets==1);auto again=op.Confirm(marker);CHECK(ResultJson(again)==ResultJson(r));CHECK(fake.sets==1&&fake.petitions==1&&marker.calls==1);++cases;}
    {Fake fake;Operation op(fake);std::string reason;CHECK(Prepare(op,fake,reason));Marker marker;CHECK(op.Confirm(marker).disposition==Disposition::accepted);CHECK(op.ObservePending(reason));fake.target[5][0]^=1;CHECK(!op.ObservePending(reason));fake.target[5][0]^=1;fake.source=fake.target;fake.source_pending.clear();CHECK(op.Observe({{"::1",1001},{"::1",1002}},{"::1",1003},reason));CHECK(fake.petitions==1&&fake.sets==1);++cases;}
    std::cout<<"native network move checks passed: "<<cases<<" cases\n";
}
