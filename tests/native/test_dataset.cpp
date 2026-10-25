#include "thread_network_core.h"
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <iostream>
#define CHECK(condition) do { if (!(condition)) { std::cerr << "CHECK failed: " #condition << " at line " << __LINE__ << '\n'; std::exit(1); } } while (0)
namespace {
std::string Hex(const std::vector<unsigned char>& bytes) {
    const char* d="0123456789abcdef";std::string o;
    for(auto b:bytes){o+=d[b>>4];o+=d[b&15];}return o;
}
void Add(std::vector<unsigned char>& b,unsigned type,const std::vector<unsigned char>& value) {
    b.push_back(static_cast<unsigned char>(type));b.push_back(static_cast<unsigned char>(value.size()));
    b.insert(b.end(),value.begin(),value.end());
}
std::vector<unsigned char> Fixture() {
    std::vector<unsigned char> b;
    Add(b,0,{0,0,15});Add(b,1,{0x12,0x34});Add(b,2,{1,2,3,4,5,6,7,8});
    Add(b,3,{'T','e','s','t'});Add(b,4,std::vector<unsigned char>(16,0xaa));
    Add(b,5,std::vector<unsigned char>(16,0xbb));Add(b,7,std::vector<unsigned char>(8,0xfd));
    Add(b,12,{0,0,0});Add(b,14,{0,0,0,0,0,0,0,1});Add(b,53,{0,4,0,1,0,0});
    return b;
}
void Invalid(const std::string& s,const char* code) {
    char out[4096];int rc=tnt_inspect_dataset(s.c_str(),out,sizeof out);
    CHECK(rc==1);CHECK(std::strstr(out,code));CHECK(!std::strstr(out,"aaaaaaaa"));CHECK(!std::strstr(out,"bbbbbbbb"));
}
}
int main() {
    CHECK(std::string(tnt_version())=="1.0.0");
    auto b=Fixture();auto s=Hex(b);char out[4096];
    CHECK(tnt_inspect_dataset(s.c_str(),out,sizeof out)==0);
    CHECK(std::strstr(out,"\"network_name\":\"Test\""));
    CHECK(std::strstr(out,"\"extended_pan_id\":\"0102030405060708\""));
    CHECK(std::strstr(out,"\"channel\":15"));
    CHECK(!std::strstr(out,"aaaaaaaa"));CHECK(!std::strstr(out,"bbbbbbbb"));
    CHECK(!std::strstr(out,"pskc\":\""));
    CHECK(!std::strstr(out,"network_key\":\""));
    b=Fixture();b[21]='"';
    CHECK(tnt_inspect_dataset(Hex(b).c_str(),out,sizeof out)==0);
    CHECK(std::strstr(out,"\"network_name\":\"\\\"est\""));
    b=Fixture();b[21]=0xc0;Invalid(Hex(b),"invalid_field");
    b.push_back(200);b.push_back(1);b.push_back(7);
    CHECK(tnt_inspect_dataset(Hex(b).c_str(),out,sizeof out)==0);
    CHECK(std::strstr(out,"\"unknown_tlv_types\":[200]"));
    // Independent Thread wire fixtures: supported 11..26 is 001fffe0.
    for(unsigned ch:{11u,15u,25u,26u}) {
        b=Fixture();b[4]=static_cast<unsigned char>(ch);
        b[b.size()-4]=0;b[b.size()-3]=0x1f;b[b.size()-2]=0xff;b[b.size()-1]=0xe0;
        CHECK(tnt_inspect_dataset(Hex(b).c_str(),out,sizeof out)==0);
    }
    // Single-channel wire masks exercise each relevant byte/bit position.
    const unsigned channels[]={11,15,25,26};
    const unsigned char masks[][4]={{0,0x10,0,0},{0,1,0,0},{0,0,0,0x40},{0,0,0,0x20}};
    for(size_t i=0;i<4;++i) {
        b=Fixture();b[4]=static_cast<unsigned char>(channels[i]);
        for(size_t j=0;j<4;++j)b[b.size()-4+j]=masks[i][j];
        CHECK(tnt_inspect_dataset(Hex(b).c_str(),out,sizeof out)==0);
    }
    b=Fixture();Add(b,1,{9,9});Invalid(Hex(b),"duplicate_tlv");
    b=Fixture();b.resize(b.size()-8);Invalid(Hex(b),"missing_required_tlv");
    b=Fixture();b[1]=2;Invalid(Hex(b),"invalid_field");
    Invalid("ff", "truncated_tlv");Invalid("xyz","invalid_hex");
    Invalid(std::string(510,'a'),"dataset_too_large");
    b=Fixture();Add(b,200,std::vector<unsigned char>(180,7));Invalid(Hex(b),"dataset_too_large");
    b=Fixture();b[b.size()-3]=0;Invalid(Hex(b),"channel_not_in_mask");
    b=Fixture();b[7]=0xff;b[8]=0xff;Invalid(Hex(b),"invalid_field");
    char tiny[2]={'x','x'};
    CHECK(tnt_inspect_dataset(s.c_str(),tiny,sizeof tiny)==2 && tiny[0]=='\0' && tiny[1]=='x');
    CHECK(tnt_inspect_dataset(s.c_str(),nullptr,0)==2);
    CHECK(tnt_inspect_dataset(nullptr,out,sizeof out)==1);
    std::cout<<"native dataset tests passed\n";
}
