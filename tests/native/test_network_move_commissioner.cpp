// Include the production adapter so the private projection functions are tested
// without exposing a new production interface. No Commissioner session is made.
#include "../../native/network_move_commissioner.cpp"
#include <cstdlib>
#include <iostream>
using namespace tnt::move;
static unsigned checks=0;
#define CHECK(x) do{++checks;if(!(x)){std::cerr<<"failed line "<<__LINE__<<"\n";std::exit(1);}}while(0)
static Bytes Wire(const Fields& f){Bytes b;for(const auto& e:f){b.push_back(e.first);b.push_back(uint8_t(e.second.size()));b.insert(b.end(),e.second.begin(),e.second.end());}return b;}
static Fields Fixture(){return {{0,{0,0,15}},{1,{0x12,0x34}},{2,Bytes(8,1)},{3,{'L','a','b'}},{4,Bytes(16,0x11)},{5,Bytes(16,0x22)},{7,{0xfd,0,0,0,0,0,0,1}},{12,{0,0,0}},{14,{0,0,0,0,0,1,0,0}},{51,{0,0,0,0,0,2,0,0}},{52,{0,0,0x75,0x30}},{53,{0,4,0,0x1f,0xff,0xe0}}};}
int main(){
 Fields out;CHECK(DecodePendingFields({},out)&&out.empty());
 for(unsigned channel:{0u,11u,26u}){auto input=Fixture();if(channel)input[74]={0,0,uint8_t(channel)};auto raw=Wire(input);CHECK(DecodePendingFields(raw,out));CHECK(out==input);ot::commissioner::PendingOperationalDataset typed;CHECK(BuildPending(input,typed));CHECK(PendingFields(typed)==input);WipePending(typed);}
 auto reject=[&](Bytes raw){CHECK(!DecodePendingFields(raw,out));CHECK(out.empty());};
 reject({200,1,0});reject({200,0});reject({74});reject({74,3,0,0});reject(Bytes(255,0));
 for(unsigned type:{0u,14u,51u,52u,74u,200u}){auto input=Fixture();if(type==74)input[74]={0,0,11};auto raw=Wire(input);raw.insert(raw.end(),{uint8_t(type),0});reject(raw);}
 for(Bytes wake: {Bytes{},Bytes{0,0},Bytes{0,0,0},Bytes{1,0,11},Bytes{0,0,10},Bytes{0,0,27},Bytes{0,1,11}}){auto f=Fixture();f[74]=wake;reject(Wire(f));ot::commissioner::PendingOperationalDataset p;CHECK(!BuildPending(f,p));}
 for(unsigned type:{0u,5u,14u,51u,52u}){auto f=Fixture();f[type].pop_back();reject(Wire(f));}
 auto f=Fixture();f[200]={1};reject(Wire(f));ot::commissioner::PendingOperationalDataset p;CHECK(!BuildPending(f,p));
 f=Fixture();f.erase(51);reject(Wire(f));f=Fixture();f.erase(52);reject(Wire(f));
 std::cout<<checks<<" adapter checks; 3 exact field-map projections; malformed/unknown/duplicate wire rejection; no network calls\n";
}
