#include <commissioner/commissioner.hpp>
#include <event2/event.h>
#include <library/coap.hpp>
#include <library/dtls.hpp>
#include <library/socket.hpp>
#include <atomic>
#include <csignal>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <set>
#include <string>
#include <vector>

// Opt-in synthetic Border Agent peer. It binds only ::1, has fixed public test
// credentials, and is never installed in an application or enabled by default.
namespace {
using namespace ot::commissioner;
namespace coap = ot::commissioner::coap;
std::atomic<bool> stop{false};
struct Stats { unsigned active=0, pending=0, petition=0, set=0, duplicate_set=0, udp_tx=0, bad_outer=0, bad_inner=0, rejected=0, handshake=0, dtls_error=0; };
ByteArray Dataset(bool target) {
  ByteArray out;
  auto field=[&](uint8_t type, const ByteArray& value){out.push_back(type);out.push_back(uint8_t(value.size()));out.insert(out.end(),value.begin(),value.end());};
  field(0,{0,0,15});field(1,{0x12,0x34});field(2,ByteArray(8,target?2:1));
  field(3,{'L','a','b'});field(4,ByteArray(16,target?0xbb:0xaa));
  field(5,ByteArray(16,target?0x22:0x11));field(7,{0xfd,0,0,0,0,0,0,1});
  field(12,{0,0,0});field(14,{0,0,0,0,0,uint8_t(target?10:20),0,0});
  field(53,{0,4,0,0x1f,0xff,0xe0});return out;
}
bool GetField(const ByteArray& raw,uint8_t wanted,ByteArray& value) {
  for(size_t offset=0;offset<raw.size();) {
    if(raw.size()-offset<2)return false;
    uint8_t type=raw[offset++];size_t size=raw[offset++];
    if(size==255){if(raw.size()-offset<2)return false;size=(size_t(raw[offset])<<8)|raw[offset+1];offset+=2;}
    if(size>raw.size()-offset)return false;
    if(type==wanted){value.assign(raw.begin()+offset,raw.begin()+offset+size);return true;}
    offset+=size;
  }
  return false;
}
void Reply(coap::Coap& server,const coap::Request& request,coap::Code code,const ByteArray& payload={}) {
  coap::Response response{coap::Type::kAcknowledgment,code};
  response.Append(payload);
  server.SendResponse(request,response).IgnoreError();
}
ByteArray InnerReply(const coap::Message& request,bool accepted) {
  auto token=request.GetToken();
  auto id=request.GetMessageId();
  ByteArray out{uint8_t(0x60|token.size()),uint8_t(coap::Code::kChanged),uint8_t(id>>8),uint8_t(id)};
  out.insert(out.end(),token.begin(),token.end());
  out.push_back(0xff);out.insert(out.end(),{16,1,accepted?uint8_t(1):uint8_t(0xff)});
  return out;
}
}
int main(int argc,char** argv) {
  if(argc<3||argc>4)return 2;
  std::string role=argv[1],mode=argv[2];
  if((role!="source"&&role!="target")||(mode!="accept"&&mode!="reject"&&mode!="drop"))return 2;
  uint16_t port=0;
  if(argc==4){char* end=nullptr;auto n=std::strtoul(argv[3],&end,10);if(!argv[3][0]||*end||n==0||n>65535)return 2;port=uint16_t(n);}
  bool target=role=="target";
  auto* base=event_base_new();if(!base)return 3;
  auto socket=std::make_shared<UdpSocket>(base);
  DtlsSession dtls(base,true,socket);
  coap::Coap server(base,dtls);
  Stats count;
  std::set<std::string> seen_sets;
  std::string last_unknown;
  auto active=Dataset(target);
  auto get=[&](const coap::Request& request,bool pending){
    const auto& payload=request.GetPayload();
    if(request.GetType()!=coap::Type::kConfirmable||request.GetCode()!=coap::Code::kPost||
       (!payload.empty() && (payload.size()<2||payload[0]!=13||payload.size()!=size_t(payload[1])+2))){
      ++count.rejected;Reply(server,request,coap::Code::kBadRequest);return;
    }
    ++(pending?count.pending:count.active);
    Reply(server,request,coap::Code::kChanged,pending?ByteArray{}:active);
  };
  coap::Resource ag{"/c/ag",[&](const coap::Request& r){get(r,false);}};
  coap::Resource pg{"/c/pg",[&](const coap::Request& r){get(r,true);}};
  coap::Resource cp{"/c/cp",[&](const coap::Request& r){
    if(target||r.GetCode()!=coap::Code::kPost){++count.rejected;Reply(server,r,coap::Code::kMethodNotAllowed);return;}
    ++count.petition;Reply(server,r,coap::Code::kChanged,{16,1,1,11,2,0x12,0x34});
  }};
  coap::Resource ut{"/c/ut",[&](const coap::Request& r){
    ++count.udp_tx;
    if(target||r.GetCode()!=coap::Code::kPost){++count.rejected;return;}
    ByteArray address,encap;
    if(!GetField(r.GetPayload(),49,address)||address.size()!=16||
       !GetField(r.GetPayload(),48,encap)||encap.size()<8){++count.rejected;++count.bad_outer;return;}
    ByteArray inner(encap.begin()+4,encap.end());Error error;
    auto message=coap::Message::Deserialize(error,inner);
    std::string path;
    if(error!=ErrorCode::kNone||!message||message->GetUriPath(path)!=ErrorCode::kNone||
       path!="/c/ps"){++count.rejected;++count.bad_inner;return;}
    auto token=message->GetToken();
    std::string request_key=std::to_string(message->GetMessageId())+":"+std::string(token.begin(),token.end());
    if(seen_sets.insert(request_key).second){++count.set;if(mode=="drop")std::cout<<"{\"event\":\"pending_set\"}"<<std::endl;}
    else ++count.duplicate_set;
    ByteArray session,delay,stamp,key,pskc;
    bool valid=GetField(message->GetPayload(),11,session)&&session==ByteArray({0x12,0x34})&&
      GetField(message->GetPayload(),52,delay)&&delay==ByteArray({0,4,0x93,0xe0})&&
      GetField(message->GetPayload(),51,stamp)&&stamp.size()==8&&
      GetField(message->GetPayload(),5,key)&&key==ByteArray(16,0x22)&&
      GetField(message->GetPayload(),4,pskc)&&pskc==ByteArray(16,0xbb);
    if(!valid){++count.rejected;return;}
    if(mode=="drop")return;
    auto reply=InnerReply(*message,mode=="accept");
    ByteArray encapsulated{0xf0,0xbf,0xf0,0xbf};
    encapsulated.insert(encapsulated.end(),reply.begin(),reply.end());
    ByteArray payload{49,16};payload.insert(payload.end(),address.begin(),address.end());
    payload.push_back(48);payload.push_back(uint8_t(encapsulated.size()));
    payload.insert(payload.end(),encapsulated.begin(),encapsulated.end());
    coap::Request udpRx{coap::Type::kNonConfirmable,coap::Code::kPost};
    if(udpRx.SetUriPath("/c/ur")==ErrorCode::kNone){udpRx.Append(payload);server.SendRequest(udpRx,nullptr);}
  }};
  server.AddResource(ag).IgnoreError();server.AddResource(pg).IgnoreError();
  server.AddResource(cp).IgnoreError();server.AddResource(ut).IgnoreError();
  server.SetDefaultHandler([&](const coap::Request& r){++count.rejected;if(r.GetUriPath(last_unknown)!=ErrorCode::kNone)last_unknown="invalid";Reply(server,r,coap::Code::kNotFound);});
  DtlsConfig config;config.mPSK.assign(16,target?0xbb:0xaa);
  if(dtls.Init(config)!=ErrorCode::kNone||socket->Bind("::1",port)!=0)return 3;
  dtls.Connect([&](DtlsSession&,Error e){if(e==ErrorCode::kNone)++count.handshake;else ++count.dtls_error;});
  std::cout<<"{\"event\":\"ready\",\"port\":"<<socket->GetLocalPort()<<"}"<<std::endl;
  auto* signal=evsignal_new(base,SIGTERM,[](evutil_socket_t,short,void* context){*static_cast<std::atomic<bool>*>(context)=true;},&stop);
  evsignal_add(signal,nullptr);
  while(!stop)event_base_loop(base,EVLOOP_ONCE);
  std::cout<<"{\"event\":\"counts\",\"active_get\":"<<count.active
           <<",\"pending_get\":"<<count.pending<<",\"petition\":"<<count.petition
           <<",\"pending_set\":"<<count.set<<",\"duplicate_set\":"<<count.duplicate_set
           <<",\"rejected\":"<<count.rejected
           <<",\"udp_tx\":"<<count.udp_tx<<",\"bad_outer\":"<<count.bad_outer
           <<",\"bad_inner\":"<<count.bad_inner
           <<",\"handshakes\":"<<count.handshake<<",\"dtls_errors\":"<<count.dtls_error
           <<",\"last_unknown\":\""<<last_unknown<<"\"}"<<std::endl;
  event_free(signal);event_base_free(base);
}
