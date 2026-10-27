#include "network_move_worker_protocol.hpp"
#include <algorithm>
#include <cstdlib>
#include <iostream>
#define CHECK(x) do { if(!(x)){std::cerr<<"CHECK failed line "<<__LINE__<<": " #x "\n";std::exit(1);} }while(0)
using namespace tnt::move::worker;
using tnt::move::Bytes;
namespace {
Bytes Dataset(bool target,bool reorder){
 std::vector<std::pair<uint8_t,Bytes>> fields={
  {0,{0,0,static_cast<uint8_t>(target?20:15)}},{1,{0x12,0x34}},{2,Bytes(8,target?2:1)},
  {3,{'L','a','b'}},{4,Bytes(16,target?0xbb:0xaa)},{5,Bytes(16,target?0x22:0x11)},
  {7,{0xfd,0,0,0,0,0,0,1}},{12,{0,0,0}},{14,{0,0,0,0,0,10,0,0}},
  {53,{0,4,0,0x1f,0xff,0xe0}}};
 if(reorder)std::reverse(fields.begin(),fields.end());Bytes out;for(auto& [type,value]:fields){out.push_back(type);out.push_back(value.size());out.insert(out.end(),value.begin(),value.end());}return out;
}
}
int main(){
 Input x;x.operation=std::string(64,'a');x.review=std::string(64,'b');x.session=std::string(64,'c');x.discovery=std::string(64,'d');x.connectivity=std::string(64,'e');x.inventory=std::string(64,'f');x.source_dataset=Dataset(false,false);x.target_dataset=Dataset(true,false);x.delay=300000;
 Fixture f;f.id=std::string(64,'1');f.sources={{std::string(64,'2'),10,20,1001},{std::string(64,'3'),11,21,1002}};f.target={std::string(64,'4'),12,22,1003};
 auto b=Binding(x,f),r=RecoveryBinding(x,f);CHECK(b.size()==64&&r.size()==64);auto reordered=x;reordered.source_dataset=Dataset(false,true);CHECK(DatasetCommitment(x.source_dataset)==DatasetCommitment(reordered.source_dataset));CHECK(Binding(reordered,f)==b);
 f.sources[0].port=2001;CHECK(Binding(x,f)==b&&RecoveryBinding(x,f)==r);
 x.review=std::string(64,'9');CHECK(Binding(x,f)!=b&&RecoveryBinding(x,f)==r);
 f.sources[0].birth++;CHECK(RecoveryBinding(x,f)!=r);
 std::cout<<"worker commitment checks passed: 6 checks\n";
}
