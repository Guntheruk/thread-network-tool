#include "network_move_worker_protocol.hpp"
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#define CHECK(x) do { if(!(x)){std::cerr<<"CHECK failed line "<<__LINE__<<": " #x "\n";std::exit(1);} }while(0)
#ifdef __linux__
#include <arpa/inet.h>
#include <dirent.h>
#include <netinet/in.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>
#include <fstream>
#include <sstream>
#include <vector>
using namespace tnt::move::worker;
namespace {
struct Child {pid_t pid=0;unsigned port=0;unsigned long long birth=0;};
std::vector<pid_t> children;
struct Cleanup {~Cleanup(){for(auto pid:children){kill(pid,SIGKILL);waitpid(pid,nullptr,0);}}} cleanup;
unsigned long long Birth(pid_t pid){std::ifstream f("/proc/"+std::to_string(pid)+"/stat");std::string line;std::getline(f,line);auto end=line.rfind(')');CHECK(end!=line.npos);std::istringstream s(line.substr(end+2));std::string word;for(unsigned field=3;field<=22;++field){CHECK(bool(s>>word));if(field==22)return std::stoull(word);}std::exit(1);}
bool OnlyLo(){DIR* dir=opendir("/sys/class/net");if(!dir)return false;bool lo=false,other=false;while(auto* e=readdir(dir)){std::string name=e->d_name;if(name=="."||name=="..")continue;if(name=="lo")lo=true;else other=true;}closedir(dir);return lo&&!other;}
Child Spawn(int family,bool wildcard,unsigned requested=0,bool reuse=false){int pipefd[2];CHECK(pipe(pipefd)==0);pid_t pid=fork();CHECK(pid>=0);if(pid==0){close(pipefd[0]);int fd=socket(family,SOCK_DGRAM,0);if(fd<0)_Exit(2);if(reuse){int yes=1;if(setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof(yes))||setsockopt(fd,SOL_SOCKET,SO_REUSEPORT,&yes,sizeof(yes)))_Exit(2);}if(family==AF_INET6){int yes=1;if(setsockopt(fd,IPPROTO_IPV6,IPV6_V6ONLY,&yes,sizeof(yes)))_Exit(2);sockaddr_in6 addr{};addr.sin6_family=AF_INET6;addr.sin6_port=htons(requested);addr.sin6_addr=wildcard?in6addr_any:in6addr_loopback;if(bind(fd,reinterpret_cast<sockaddr*>(&addr),sizeof(addr)))_Exit(2);socklen_t len=sizeof(addr);if(getsockname(fd,reinterpret_cast<sockaddr*>(&addr),&len))_Exit(2);unsigned port=ntohs(addr.sin6_port);if(write(pipefd[1],&port,sizeof(port))!=sizeof(port))_Exit(2);}else{sockaddr_in addr{};addr.sin_family=AF_INET;addr.sin_port=htons(requested);addr.sin_addr.s_addr=htonl(INADDR_LOOPBACK);if(bind(fd,reinterpret_cast<sockaddr*>(&addr),sizeof(addr)))_Exit(2);socklen_t len=sizeof(addr);if(getsockname(fd,reinterpret_cast<sockaddr*>(&addr),&len))_Exit(2);unsigned port=ntohs(addr.sin_port);if(write(pipefd[1],&port,sizeof(port))!=sizeof(port))_Exit(2);}for(;;)pause();}
 close(pipefd[1]);unsigned port=0;auto got=read(pipefd[0],&port,sizeof(port));close(pipefd[0]);CHECK(got==sizeof(port)&&port>0);children.push_back(pid);return {pid,port,Birth(pid)};}
Node NodeFor(const Child& c,char digit){return {std::string(64,digit),static_cast<unsigned>(c.pid),c.birth,c.port};}
}
int main(int argc,char** argv){CHECK(OnlyLo());bool split_only=argc==2&&std::string(argv[1])=="--split-only",shared_only=argc==2&&std::string(argv[1])=="--shared-only";CHECK(argc==1||split_only||shared_only);auto ipv4=Spawn(AF_INET,false);auto alias=Spawn(AF_INET6,false,ipv4.port);auto source2=Spawn(AF_INET6,false);auto target=Spawn(AF_INET6,false);auto wildcard=Spawn(AF_INET6,true);Fixture fixture;fixture.sources={NodeFor(alias,'1'),NodeFor(source2,'2')};fixture.target=NodeFor(target,'3');VerifyFixture(fixture);fixture.sources[0]=NodeFor(wildcard,'4');VerifyFixture(fixture);if(!shared_only){fixture.sources[0]=NodeFor(ipv4,'5');bool rejected=false;try{VerifyFixture(fixture);}catch(const std::runtime_error& error){rejected=std::string(error.what())=="fixture_socket_unowned";}CHECK(rejected);}if(!split_only){auto first=Spawn(AF_INET6,false,0,true);auto second=Spawn(AF_INET6,false,first.port,true);fixture.sources[0]=NodeFor(first,'6');bool rejected=false;try{VerifyFixture(fixture);}catch(const std::runtime_error& error){rejected=std::string(error.what())=="fixture_socket_ambiguous";}CHECK(rejected);(void)second;}std::cout<<"actual Linux socket owner checks passed: exact IPv6, wildcard IPv6, requested alias rejections\n";}
#else
int main(){std::cout<<"Linux network namespace test requires Linux\n";}
#endif
