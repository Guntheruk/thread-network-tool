#include "dataset.hpp"
#include "thread_network_core.h"
#include <array>
#include <cstring>
#include <iomanip>
#include <sstream>

namespace tnt {
namespace {
constexpr size_t kMaxHex = 508; // Thread operational dataset maximum: 254 encoded bytes.
struct ByteWiper {
    std::vector<uint8_t>& value;
    ~ByteWiper() { volatile uint8_t* p=value.data(); for(size_t i=0;i<value.size();++i) p[i]=0; }
};
int Digit(char c) {
    if (c >= '0' && c <= '9') return c-'0';
    if (c >= 'a' && c <= 'f') return c-'a'+10;
    if (c >= 'A' && c <= 'F') return c-'A'+10;
    return -1;
}
std::string Hex(const uint8_t* data, size_t length) {
    static const char digits[] = "0123456789abcdef";
    std::string result;
    result.reserve(length*2);
    for (size_t i=0;i<length;++i) { result += digits[data[i]>>4]; result += digits[data[i]&15]; }
    return result;
}
bool Utf8(const uint8_t* p, size_t n) {
    for(size_t i=0;i<n;) {
        uint8_t a=p[i++];
        if(a<0x80) { if(a==0) return false; continue; }
        unsigned extra=0; uint32_t cp=0;
        if(a>=0xc2 && a<=0xdf) {extra=1;cp=a&31;}
        else if(a>=0xe0 && a<=0xef) {extra=2;cp=a&15;}
        else if(a>=0xf0 && a<=0xf4) {extra=3;cp=a&7;}
        else return false;
        if(extra>n-i) return false;
        for(unsigned j=0;j<extra;++j) { if((p[i]&0xc0)!=0x80) return false; cp=(cp<<6)|(p[i++]&63); }
        if((extra==1 && cp<0x80)||(extra==2 && cp<0x800)||(extra==3 && cp<0x10000)||
           cp>0x10ffff||(cp>=0xd800 && cp<=0xdfff)) return false;
    }
    return true;
}
bool Known(uint8_t type) {
    switch(type) {case 0:case 1:case 2:case 3:case 4:case 5:case 7:case 12:case 14:case 53:return true;default:return false;}
}
bool ValidField(uint8_t type,const uint8_t* p,size_t n) {
    switch(type) {
    case 0: return n==3 && p[0]==0 && ((unsigned(p[1])<<8)|p[2])>=11 && ((unsigned(p[1])<<8)|p[2])<=26;
    case 1: return n==2 && !(p[0]==0xff && p[1]==0xff);
    case 2:case 14:return n==8;
    case 3:return n>=1 && n<=16 && Utf8(p,n);
    case 4:case 5:return n==16;
    case 7:return n==8 && p[0]==0xfd;
    case 12:return n==3 || n==4;
    case 53:return n==6 && p[0]==0 && p[1]==4;
    default:return true;
    }
}
}
bool ParseDataset(const char* hex, Dataset& out, std::string& code) {
    out=Dataset{};
    if(!hex) {code="invalid_input";return false;}
    size_t chars=0;
    while(chars<=kMaxHex && hex[chars]) ++chars;
    if(chars>kMaxHex) {code="dataset_too_large";return false;}
    if(chars==0 || chars%2) {code="invalid_hex";return false;}
    std::vector<uint8_t> bytes; bytes.reserve(chars/2); ByteWiper wipe{bytes};
    for(size_t i=0;i<chars;i+=2) {int hi=Digit(hex[i]),lo=Digit(hex[i+1]); if(hi<0||lo<0) {code="invalid_hex";return false;} bytes.push_back(uint8_t((hi<<4)|lo));}
    std::array<bool,256> seen{};
    size_t i=0;
    while(i<bytes.size()) {
        if(bytes.size()-i<2) {code="truncated_tlv";return false;}
        uint8_t type=bytes[i++],length=bytes[i++];
        if(length>bytes.size()-i) {code="truncated_tlv";return false;}
        if(seen[type]) {code="duplicate_tlv";return false;}
        seen[type]=true;
        const uint8_t* p=bytes.data()+i;
        if((type==0 || type==53) && length>0 && p[0]!=0) {code="unsupported_channel_page";return false;}
        if(!ValidField(type,p,length)) {code="invalid_field";return false;}
        switch(type) {
            case 0:out.channel=uint16_t((unsigned(p[1])<<8)|p[2]);break;
            case 1:out.pan_id=Hex(p,length);break;
            case 2:out.extended_pan_id=Hex(p,length);break;
            case 3:out.network_name.assign(reinterpret_cast<const char*>(p),length);break;
            case 4:std::memcpy(out.pskc.data(),p,16);break;
            case 14:out.active_timestamp=Hex(p,length);break;
            default:if(!Known(type)) out.unknown_types.push_back(type);break;
        }
        i+=length;
    }
    for(uint8_t required:{uint8_t(0),uint8_t(1),uint8_t(2),uint8_t(3),uint8_t(4),uint8_t(5),uint8_t(7),uint8_t(12),uint8_t(14),uint8_t(53)})
        if(!seen[required]) {code="missing_required_tlv";return false;}
    // Thread MeshCoP ChannelMaskEntry wire bits are MSB-first for each channel index.
    // Other channel pages are deliberately outside this initial parser's scope.
    size_t mask=0;
    while(mask<bytes.size()) {if(bytes[mask]==53) break; mask+=2+bytes[mask+1];}
    const unsigned channel=out.channel;
    const uint8_t* m=bytes.data()+mask+4;
    if((m[channel/8] & (0x80u>>(channel%8)))==0) {code="channel_not_in_mask";return false;}
    return true;
}
std::string JsonString(const std::string& value) {
    std::ostringstream o;o<<'"';
    for(unsigned char c:value) {
        if(c=='"'||c=='\\') o<<'\\'<<char(c);
        else if(c<0x20) {o<<"\\u00"<<std::hex<<std::setw(2)<<std::setfill('0')<<unsigned(c)<<std::dec;}
        else o<<char(c);
    }
    o<<'"';return o.str();
}
std::string InspectJson(const Dataset& d) {
    std::ostringstream o;
    o<<"{\"schema_version\":1,\"valid\":true,\"network_name\":"<<JsonString(d.network_name)
     <<",\"extended_pan_id\":"<<JsonString(d.extended_pan_id)
     <<",\"channel\":"<<d.channel<<",\"pan_id\":"<<JsonString(d.pan_id)
     <<",\"active_timestamp\":"<<JsonString(d.active_timestamp)
     <<",\"has_network_key\":true,\"has_pskc\":true,\"unknown_tlv_types\":[";
    for(size_t i=0;i<d.unknown_types.size();++i) {if(i)o<<',';o<<d.unknown_types[i];}
    o<<"]}";return o.str();
}
std::string ErrorJson(const std::string& code) {
    return "{\"schema_version\":1,\"valid\":false,\"error_code\":"+JsonString(code)+
        ",\"message\":\"Dataset validation failed\"}";
}
}
extern "C" const char* tnt_version(void) {return "1.0.0";}
extern "C" int tnt_inspect_dataset(const char* hex,char* output,size_t capacity) {
    if(!output || capacity==0) return 2;
    output[0]='\0';
    try {
        tnt::Dataset dataset;std::string code;
        bool valid=tnt::ParseDataset(hex,dataset,code);
        std::string result=valid?tnt::InspectJson(dataset):tnt::ErrorJson(code);
        if(result.size()+1>capacity) return 2;
        std::memcpy(output,result.c_str(),result.size()+1);
        return valid?0:1;
    } catch(...) {return 1;}
}
