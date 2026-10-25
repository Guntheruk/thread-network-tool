#include "discovery.hpp"
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>
#define CHECK(x) do {if(!(x)){std::cerr<<"CHECK failed: " #x " at "<<__LINE__<<'\n';std::exit(1);}} while(0)
namespace {
void Add(std::vector<uint8_t>& txt,const std::string& key,const std::vector<uint8_t>& value) {
    txt.push_back(static_cast<uint8_t>(key.size()+1+value.size()));
    txt.insert(txt.end(),key.begin(),key.end());txt.push_back('=');
    txt.insert(txt.end(),value.begin(),value.end());
}
}
int main() {
    std::vector<uint8_t> txt;
    Add(txt,"nn",{'T','e','s','t'});
    Add(txt,"xp",{1,2,3,4,5,6,7,8});
    Add(txt,"tv",{'1','.','4','.','0'});
    Add(txt,"id",{'S','E','C','R','E','T'});
    auto parsed=tnt::ParseDiscoveryTxt(txt.data(),txt.size());
    CHECK(parsed.network_name=="Test");
    CHECK(parsed.extended_pan_id=="0102030405060708");
    CHECK(parsed.thread_version=="1.4.0");
    CHECK(tnt::DiscoveryJsonString("a\"\\\n") == "\"a\\\"\\\\\\u000a\"");
    CHECK(tnt::DiscoveryUtf8("\xc3\xa9"));
    CHECK(!tnt::DiscoveryUtf8("\xc0\x80"));
    CHECK(!tnt::DiscoveryUtf8("\xed\xa0\x80"));
    CHECK(!tnt::DiscoveryUtf8("\xf4\x90\x80\x80"));
    txt.push_back(7); // truncated entry invalidates metadata
    parsed=tnt::ParseDiscoveryTxt(txt.data(),txt.size());
    CHECK(parsed.network_name.empty()&&parsed.extended_pan_id.empty()&&parsed.thread_version.empty());
    txt.clear();Add(txt,"nn",{0xc0,0x80});Add(txt,"xp",{1,2});Add(txt,"tv",{'1',';','x'});
    parsed=tnt::ParseDiscoveryTxt(txt.data(),txt.size());
    CHECK(parsed.network_name.empty()&&parsed.extended_pan_id.empty()&&parsed.thread_version.empty());
    txt.clear();Add(txt,"nn",{'a'});Add(txt,"nn",{'b'});
    CHECK(tnt::ParseDiscoveryTxt(txt.data(),txt.size()).network_name.empty());
    CHECK(tnt::ParseDiscoveryTxt(nullptr,10).network_name.empty());
    CHECK(tnt::ParseDiscoveryTxt(txt.data(),1025).network_name.empty());
#ifndef __APPLE__
    auto result=tnt::Discover();
    CHECK(result.exit_code==2&&result.json.find("\"discovery_status\":\"unsupported\"")!=std::string::npos);
#endif
    std::cout<<"native discovery tests passed\n";
}
