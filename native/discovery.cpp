#include "discovery.hpp"
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <memory>
#include <sstream>
#include <vector>
#ifdef __APPLE__
#include <arpa/inet.h>
#include <dns_sd.h>
#include <sys/select.h>
#endif

namespace tnt {
bool DiscoveryUtf8(const std::string& s) {
    for (size_t i=0;i<s.size();) {
        const unsigned char c=static_cast<unsigned char>(s[i]);
        if(c<0x80) { if(c==0) return false; ++i; continue; }
        unsigned n= c>=0xc2&&c<=0xdf?2:c>=0xe0&&c<=0xef?3:c>=0xf0&&c<=0xf4?4:0;
        if(!n || i+n>s.size()) return false;
        for(unsigned j=1;j<n;++j) if((static_cast<unsigned char>(s[i+j])&0xc0)!=0x80) return false;
        const unsigned char d=static_cast<unsigned char>(s[i+1]);
        if((c==0xe0&&d<0xa0)||(c==0xed&&d>=0xa0)||(c==0xf0&&d<0x90)||(c==0xf4&&d>=0x90)) return false;
        i+=n;
    }
    return true;
}
std::string DiscoveryJsonString(const std::string& s) {
    std::string out="\""; char hex[7];
    for(unsigned char c:s) {
        if(c=='"'||c=='\\') {out+='\\';out+=char(c);}
        else if(c<0x20) {std::snprintf(hex,sizeof hex,"\\u%04x",c);out+=hex;}
        else out+=char(c);
    }
    return out+'"';
}
DiscoveryTxt ParseDiscoveryTxt(const uint8_t* data,size_t size) {
    DiscoveryTxt out;
    if(!data || size>1024) return out;
    bool nn=false,xp=false,tv=false;
    for(size_t p=0;p<size;) {
        const size_t len=data[p++];
        if(len>size-p) return {}; // no metadata from malformed TXT
        const uint8_t* item=data+p;p+=len;
        if(len<3 || item[2]!='=') continue;
        const uint8_t* value=item+3;const size_t n=len-3;
        if(item[0]=='n'&&item[1]=='n') {
            if(nn) {out.network_name.clear();continue;} nn=true;
            const std::string s(reinterpret_cast<const char*>(value),n);
            if(n>=1&&n<=16&&DiscoveryUtf8(s)) out.network_name=s;
        } else if(item[0]=='x'&&item[1]=='p') {
            if(xp) {out.extended_pan_id.clear();continue;} xp=true;
            if(n==8) {const char* hex="0123456789abcdef";for(size_t i=0;i<n;++i) {out.extended_pan_id+=hex[value[i]>>4];out.extended_pan_id+=hex[value[i]&15];}}
        } else if(item[0]=='t'&&item[1]=='v') {
            if(tv) {out.thread_version.clear();continue;} tv=true;
            bool safe=n>=1&&n<=16;
            for(size_t i=0;i<n;++i) if(!((value[i]>='0'&&value[i]<='9')||value[i]=='.')) safe=false;
            if(safe) out.thread_version.assign(reinterpret_cast<const char*>(value),n);
        }
    }
    return out;
}

#ifdef __APPLE__
namespace {
constexpr size_t kMaxServices=32,kMaxRows=64;
struct State;
struct Service {
    State* owner;std::string name,type,domain,host;uint32_t index;
    uint16_t port=0;DiscoveryTxt txt;DNSServiceRef resolve=nullptr,addr=nullptr;
    bool active=true,resolved=false,failed=false;std::vector<std::string> addresses;
    ~Service(){if(resolve) DNSServiceRefDeallocate(resolve);if(addr) DNSServiceRefDeallocate(addr);}
};
struct State {DNSServiceRef browse=nullptr;std::vector<std::unique_ptr<Service>> services;bool error=false,partial=false;~State(){if(browse) DNSServiceRefDeallocate(browse);}};
void DNSSD_API OnBrowse(DNSServiceRef,DNSServiceFlags flags,uint32_t index,DNSServiceErrorType error,const char* name,const char* type,const char* domain,void* context) {
    auto& st=*static_cast<State*>(context);
    if(error!=kDNSServiceErr_NoError){st.error=true;return;}
    if(!name||!type||!domain) {st.partial=true;return;}
    std::string n(name),t(type),d(domain);
    if(n.size()>255||!DiscoveryUtf8(n)||t.size()>255||d.size()>255) {st.partial=true;return;}
    for(auto& s:st.services) if(s->active&&s->index==index&&s->name==n&&s->type==t&&s->domain==d) {
        if(!(flags&kDNSServiceFlagsAdd)) s->active=false;
        return;
    }
    if(!(flags&kDNSServiceFlagsAdd)) return;
    if(st.services.size()>=kMaxServices){st.partial=true;return;}
    auto s=std::make_unique<Service>();s->owner=&st;s->name=n;s->type=t;s->domain=d;s->index=index;st.services.push_back(std::move(s));
}
void DNSSD_API OnResolve(DNSServiceRef,DNSServiceFlags,uint32_t,DNSServiceErrorType error,const char*,const char* host,uint16_t port,uint16_t txt_len,const unsigned char* txt,void* context) {
    auto& s=*static_cast<Service*>(context);
    if(error!=kDNSServiceErr_NoError||!host||!port||std::strlen(host)>255){s.failed=true;s.owner->partial=true;return;}
    s.host=host;s.port=ntohs(port);s.txt=ParseDiscoveryTxt(txt,txt_len);s.resolved=true;
}
void DNSSD_API OnAddr(DNSServiceRef,DNSServiceFlags flags,uint32_t,DNSServiceErrorType error,const char*,const sockaddr* address,uint32_t,void* context) {
    auto& s=*static_cast<Service*>(context);
    if(error!=kDNSServiceErr_NoError){s.failed=true;s.owner->partial=true;return;}
    if(!address) return;
    char buf[INET6_ADDRSTRLEN];const void* bytes=nullptr;
    if(address->sa_family==AF_INET) bytes=&reinterpret_cast<const sockaddr_in*>(address)->sin_addr;
    else if(address->sa_family==AF_INET6) {
        const auto* b=reinterpret_cast<const sockaddr_in6*>(address)->sin6_addr.s6_addr;
        if(!((b[0]&0xe0)==0x20||(b[0]&0xfe)==0xfc)) return; // global or ULA only
        bytes=&reinterpret_cast<const sockaddr_in6*>(address)->sin6_addr;
    } else return;
    if(!inet_ntop(address->sa_family,bytes,buf,sizeof buf)) return;
    auto it=std::find(s.addresses.begin(),s.addresses.end(),buf);
    if(flags&kDNSServiceFlagsAdd) {
        if(it==s.addresses.end()) {if(s.addresses.size()<kMaxRows)s.addresses.emplace_back(buf);else s.owner->partial=true;}
    } else if(it!=s.addresses.end()) s.addresses.erase(it);
}
void StartPending(State& st) {
    for(auto& p:st.services) {
        auto& s=*p;
        if(!s.active) {if(s.resolve){DNSServiceRefDeallocate(s.resolve);s.resolve=nullptr;}if(s.addr){DNSServiceRefDeallocate(s.addr);s.addr=nullptr;}continue;}
        if(!s.resolve&&!s.resolved&&!s.failed) {
            if(DNSServiceResolve(&s.resolve,0,s.index,s.name.c_str(),s.type.c_str(),s.domain.c_str(),OnResolve,&s)!=kDNSServiceErr_NoError){s.failed=true;st.partial=true;}
        }
        if(s.resolved&&!s.addr&&!s.failed) {
            if(DNSServiceGetAddrInfo(&s.addr,0,s.index,kDNSServiceProtocol_IPv4|kDNSServiceProtocol_IPv6,s.host.c_str(),OnAddr,&s)!=kDNSServiceErr_NoError){s.failed=true;st.partial=true;}
        }
    }
}
std::string Json(const State& st,const char* status) {
    std::ostringstream o;o<<"{\"schema_version\":1,\"discovery_status\":\""<<status<<"\",\"routers\":[";
    size_t rows=0;
    for(const auto& p:st.services) if(p->active) for(const auto& address:p->addresses) {
        if(rows==kMaxRows) break;
        if(rows++) o<<',';
        o<<"{\"service_name\":"<<DiscoveryJsonString(p->name)
         <<",\"network_name\":"<<(p->txt.network_name.empty()?"null":DiscoveryJsonString(p->txt.network_name))
         <<",\"extended_pan_id\":"<<(p->txt.extended_pan_id.empty()?"null":DiscoveryJsonString(p->txt.extended_pan_id))
         <<",\"thread_version\":"<<(p->txt.thread_version.empty()?"null":DiscoveryJsonString(p->txt.thread_version))
         <<",\"address\":"<<DiscoveryJsonString(address)<<",\"port\":"<<p->port
         <<",\"interface_index\":"<<p->index<<'}';
    }
    o<<"]}";return o.str();
}
}
#endif
DiscoveryResult Discover() {
#ifndef __APPLE__
    return {"{\"schema_version\":1,\"discovery_status\":\"unsupported\",\"routers\":[]}",2};
#else
    State st;
    if(DNSServiceBrowse(&st.browse,0,kDNSServiceInterfaceIndexAny,"_meshcop._udp","local.",OnBrowse,&st)!=kDNSServiceErr_NoError)
        return {Json(st,"error"),1};
    const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(7);
    while(!st.error&&std::chrono::steady_clock::now()<deadline) {
        StartPending(st);
        fd_set readfds;FD_ZERO(&readfds);int maxfd=-1;
        auto add=[&](DNSServiceRef ref){if(!ref)return;int fd=DNSServiceRefSockFD(ref);if(fd<0||fd>=FD_SETSIZE){st.error=true;return;}FD_SET(fd,&readfds);maxfd=std::max(maxfd,fd);};
        add(st.browse);for(auto& p:st.services) if(p->active){add(p->resolve);add(p->addr);}
        if(st.error||maxfd<0) break;
        auto remaining=std::chrono::duration_cast<std::chrono::microseconds>(deadline-std::chrono::steady_clock::now()).count();
        if(remaining<=0) break;
        timeval timeout{static_cast<long>(remaining/1000000),static_cast<int>(remaining%1000000)};
        int ready=select(maxfd+1,&readfds,nullptr,nullptr,&timeout);
        if(ready<0) {st.error=true;break;}
        if(!ready) break;
        auto process=[&](DNSServiceRef ref){if(ref&&FD_ISSET(DNSServiceRefSockFD(ref),&readfds)&&DNSServiceProcessResult(ref)!=kDNSServiceErr_NoError)st.error=true;};
        process(st.browse);
        // Browse callbacks may append services; stable Service allocations keep callback contexts valid.
        const size_t count=st.services.size();
        for(size_t i=0;i<count&&!st.error;++i) if(st.services[i]->active){process(st.services[i]->resolve);process(st.services[i]->addr);}
    }
    for(const auto& p:st.services) if(p->active&&(!p->resolved||p->addresses.empty())) st.partial=true;
    size_t rows=0;for(const auto& p:st.services) if(p->active) rows+=p->addresses.size();
    if(rows>kMaxRows) st.partial=true;
    const char* status=st.error?"error":st.partial?"partial":"completed";
    return {Json(st,status),st.error?1:st.partial?1:0};
#endif
}
}
