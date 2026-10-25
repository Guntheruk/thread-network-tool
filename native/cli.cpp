#include "dataset.hpp"
#include "probe.hpp"
#include <iostream>
#include <string>
#include <cstdlib>
#include <cerrno>
#if !defined(_WIN32)
#include <arpa/inet.h>
#include <sys/resource.h>
#include <unistd.h>
#endif
namespace {
void Wipe(std::string& s) {volatile char* p=s.data();for(size_t i=0;i<s.size();++i)p[i]=0;}
std::string ReadLine() {
    std::string line;
    line.reserve(4096);
    for(size_t i=0;i<=508;++i) {
        int c=std::cin.get();
        if(c=='\n' || c==EOF) return line;
        line+=char(c);
    }
    return line;
}
bool Port(const char* s,unsigned& port) {
    if(!s || !*s) return false;
    for(const char* p=s;*p;++p) if(*p<'0'||*p>'9') return false;
    errno=0;char* end=nullptr;unsigned long n=std::strtoul(s,&end,10);
    if(errno || *end || n==0 || n>65535) return false;
    port=unsigned(n);return true;
}
bool NumericIp(const char* s) {
#if defined(_WIN32)
    (void)s;return false;
#else
    unsigned char buf[16];
    return inet_pton(AF_INET,s,buf)==1 || inet_pton(AF_INET6,s,buf)==1;
#endif
}
}
int main(int argc,char** argv) {
    if(argc<2) {std::cout<<tnt::ErrorJson("invalid_command")<<'\n';return 2;}
    const bool inspect=std::string(argv[1])=="inspect" && argc==2;
    const bool probe=std::string(argv[1])=="probe" && argc==4;
    if(!inspect && !probe) {std::cout<<tnt::ErrorJson("invalid_command")<<'\n';return 2;}
    unsigned port=0;
    if(probe && (!Port(argv[3],port)||!NumericIp(argv[2]))) {
        std::cout<<tnt::ErrorJson("invalid_endpoint")<<'\n';return 2;
    }
#if !defined(_WIN32)
    if(isatty(STDIN_FILENO)) {std::cout<<tnt::ErrorJson("stdin_required")<<'\n';return 2;}
    struct rlimit no_core={0,0};
    if(setrlimit(RLIMIT_CORE,&no_core)!=0) {std::cout<<tnt::ErrorJson("environment_error")<<'\n';return 2;}
#endif
    std::string line=ReadLine();
    if(line.size()>508) {Wipe(line);std::cout<<tnt::ErrorJson("dataset_too_large")<<'\n';return 1;}
    if(std::cin.peek()!=EOF) {Wipe(line);std::cout<<tnt::ErrorJson("extra_input")<<'\n';return 1;}
    tnt::Dataset dataset;std::string code;
    if(!tnt::ParseDataset(line.c_str(),dataset,code)) {
        Wipe(line);
        std::cout<<tnt::ErrorJson(code)<<'\n';return 1;
    }
    Wipe(line);
    if(inspect) {std::cout<<tnt::InspectJson(dataset)<<'\n';return 0;}
#if defined(TNT_WITH_COMMISSIONER)
    std::cout<<tnt::Probe(argv[2],port,dataset)<<'\n';
    return 0;
#else
    std::cout<<"{\"schema_version\":1,\"probe_status\":\"unsupported\",\"reason\":\"commissioner_not_built\"}"<<'\n';
    return 2;
#endif
}
