#include "network_move.hpp"
#include "dataset.hpp"
#include <algorithm>
#include "network_move_commissioner.hpp"
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <random>
#include <sstream>
#include <string>
#ifndef _WIN32
#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>
#endif
using namespace tnt::move;
namespace {
class Input {
    size_t total_=0;
public:
    std::string Line() {
        std::string line;char c;
        while(std::cin.get(c)) {
            if(++total_>16384||line.size()>1024||c=='\r'||c=='\0')throw std::runtime_error("invalid_request");
            if(c=='\n')return line;line.push_back(c);
        }
        throw std::runtime_error("invalid_request");
    }
    std::string Field(const std::string& label) {
        auto line=Line();auto prefix=label+" ";
        if(line.rfind(prefix,0)!=0||line.size()==prefix.size())throw std::runtime_error("invalid_request");
        return line.substr(prefix.size());
    }
};
unsigned Unsigned(const std::string& value,unsigned maximum) {
    if(value.empty()||value.size()>10)throw std::runtime_error("invalid_request");
    uint64_t number=0;for(char c:value){if(c<'0'||c>'9')throw std::runtime_error("invalid_request");number=number*10+c-'0';if(number>maximum)throw std::runtime_error("invalid_request");}return unsigned(number);
}
Endpoint Loopback(const std::string& value) {
    auto split=value.find(' ');
    if(split==std::string::npos||value.find(' ',split+1)!=std::string::npos)throw std::runtime_error("invalid_request");
    Endpoint endpoint{value.substr(0,split),uint16_t(Unsigned(value.substr(split+1),65535))};
    if((endpoint.address!="::1"&&endpoint.address!="127.0.0.1")||!endpoint.port)throw std::runtime_error("loopback_required");return endpoint;
}
Request ReadRequest(Input& input) {
    if(input.Line()!="TNT-MOVE/1")throw std::runtime_error("invalid_request");
    Request request;request.operation_id=input.Field("operation_id");
    std::string source=input.Field("source_dataset"),target=input.Field("target_dataset");
    bool valid=DecodeHex(source,request.source_dataset)&&DecodeHex(target,request.target_dataset);
    std::fill(source.begin(),source.end(),'0');std::fill(target.begin(),target.end(),'0');
    if(!valid)throw std::runtime_error("invalid_request");
    unsigned count=Unsigned(input.Field("source_count"),8);if(!count)throw std::runtime_error("invalid_request");
    for(unsigned i=0;i<count;++i)request.sources.push_back(Loopback(input.Field("source_endpoint")));
    request.target=Loopback(input.Field("target_endpoint"));request.delay_ms=Unsigned(input.Field("delay_ms"),600000);
    request.controlled_empty=input.Field("controlled_empty")=="yes";
    request.manual_recovery=input.Field("recovery")=="manual-stop-and-observe";
    if(input.Line()!="END")throw std::runtime_error("invalid_request");return request;
}
std::string Token() {
    std::random_device random;static const char hex[]="0123456789abcdef";std::string token;
    for(unsigned i=0;i<32;++i)token+=hex[random()&15];return token;
}
class TmpfsFence final:public Fence {
public:
    bool Arm(const std::string& id) override {
#ifdef _WIN32
        return false;
#else
        // Lab-only fixed path, no request-controlled filenames. Existing unresolved ID always blocks.
        int fd=open("/tmp/tnt-network-move-unresolved",O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW|O_CLOEXEC,0600);
        if(fd<0)return false;
        std::string content="TNT-MOVE/1\n"+id+"\nunresolved\n";
        bool ok=write(fd,content.data(),content.size())==static_cast<ssize_t>(content.size())&&fsync(fd)==0;
        if(close(fd)!=0)ok=false;
        int directory=open("/tmp",O_RDONLY|O_DIRECTORY|O_CLOEXEC);
        if(directory<0)return false;if(fsync(directory)!=0)ok=false;close(directory);return ok;
#endif
    }
};
}
int main(int argc,char** argv) {
    bool discard=argc==2&&std::string(argv[1])=="--lab-discard-set-result";
    if(argc!=1&&!discard){std::cout<<"{\"schema_version\":1,\"disposition\":\"proven_not_sent\",\"reason\":\"invalid_request\"}\n";return 1;}
#ifndef _WIN32
    auto deadline=[](int){const char message[]="{\"schema_version\":1,\"disposition\":\"uncertain\",\"reason\":\"process_deadline\"}\n";write(STDOUT_FILENO,message,sizeof(message)-1);_Exit(124);};
    signal(SIGALRM,deadline);signal(SIGTERM,deadline);alarm(1000);
#endif
    bool confirm_started=false;
    try {
        Input input;Request request=ReadRequest(input);const auto operation_id=request.operation_id;auto transport=CreateCommissionerTransport(discard,true);Operation operation(*transport);
        std::string reason;
        if(!operation.Prepare(std::move(request),reason)){Result result;result.operation_id=operation_id;result.reason=reason;std::cout<<ResultJson(result)<<std::endl;return 1;}
        auto token=Token();std::cout<<"{\"schema_version\":1,\"phase\":\"review\",\"ready\":true,\"confirmation_token\":\""<<token<<"\"}"<<std::endl;
        if(input.Field("confirm")!=token){Result result;result.operation_id=operation_id;result.reason="confirmation_mismatch";std::cout<<ResultJson(result)<<std::endl;return 1;}
        TmpfsFence fence;confirm_started=true;auto result=operation.Confirm(fence);std::cout<<ResultJson(result)<<std::endl;
        if(!result.pending_set_invocations)return 1;
        while(true) {
            std::string command=input.Line();
            if(command=="quit")return result.disposition==Disposition::accepted?0:2;
            if(command=="pending") {
                bool observed=operation.ObservePending(reason);
                std::cout<<"{\"schema_version\":1,\"phase\":\"pending\",\"verified\":"<<(observed?"true":"false")<<",\"reason\":"<<tnt::JsonString(reason)<<"}"<<std::endl;
            } else if(command.rfind("observe ",0)==0) {
                unsigned count=Unsigned(command.substr(8),8);std::vector<Endpoint> endpoints;
                for(unsigned i=0;i<count;++i)endpoints.push_back(Loopback(input.Field("source_endpoint")));
                auto target=Loopback(input.Field("target_endpoint"));
                bool observed=operation.Observe(endpoints,target,reason);
                std::cout<<"{\"schema_version\":1,\"phase\":\"observation\",\"converged\":"<<(observed?"true":"false")<<",\"reason\":"<<tnt::JsonString(reason)<<"}"<<std::endl;
            } else throw std::runtime_error("invalid_request");
        }
    } catch(...) {
        Result result;result.disposition=confirm_started?Disposition::uncertain:Disposition::proven_not_sent;result.reason="worker_error";
        std::cout<<ResultJson(result)<<std::endl;return 1;
    }
}
