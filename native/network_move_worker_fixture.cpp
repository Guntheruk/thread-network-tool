#include "network_move_worker_protocol.hpp"
#include <cerrno>
#include <cstdio>
#include <dirent.h>
#include <fstream>
#include <set>
#include <sstream>
#include <stdexcept>
#include <unistd.h>
namespace tnt::move::worker {
namespace {
unsigned long long Birth(unsigned pid){std::ifstream f("/proc/"+std::to_string(pid)+"/stat");std::string line;std::getline(f,line);auto end=line.rfind(')');if(end==line.npos)throw std::runtime_error("fixture_process_missing");std::istringstream rest(line.substr(end+2));std::string item;for(int field=3;field<=22;++field){if(!(rest>>item))throw std::runtime_error("fixture_process_invalid");if(field==22)return std::stoull(item);}throw std::runtime_error("fixture_process_invalid");}
std::set<unsigned long long> SocketInodes(unsigned pid){std::set<unsigned long long> out;std::string path="/proc/"+std::to_string(pid)+"/fd";DIR* dir=opendir(path.c_str());if(!dir)throw std::runtime_error("fixture_fd_unavailable");while(auto* ent=readdir(dir)){if(ent->d_name[0]=='.')continue;std::string fdpath=path+"/"+ent->d_name;char link[128];auto n=readlink(fdpath.c_str(),link,sizeof(link)-1);if(n<=0)continue;link[n]=0;unsigned long long inode=0;if(sscanf(link,"socket:[%llu]",&inode)==1)out.insert(inode);}closedir(dir);return out;}
enum class SocketBind { missing, loopback, wildcard };
SocketBind UdpOwned(unsigned port,const std::set<unsigned long long>& inodes){
 bool wildcard=false;
 for(auto name:{"/proc/net/udp","/proc/net/udp6"}){
  std::ifstream f(name);std::string line;std::getline(f,line);
  while(std::getline(f,line)){
   std::istringstream row(line);std::string slot,local,remote,state,tx,tm,retr,uid,timeout,inode;
   row>>slot>>local>>remote>>state>>tx>>tm>>retr>>uid>>timeout>>inode;
   auto colon=local.rfind(':');if(colon==local.npos||inode.empty())continue;
   unsigned candidate=0;try{candidate=std::stoul(local.substr(colon+1),nullptr,16);}catch(...){continue;}
   if(candidate!=port)continue;
   bool owned=false;try{owned=inodes.count(std::stoull(inode));}catch(...){continue;}
   if(!owned)continue;
   auto addr=local.substr(0,colon);
   if(addr=="0100007F"||addr=="00000000000000000000000001000000")return SocketBind::loopback;
   if(addr=="00000000"||addr=="00000000000000000000000000000000")wildcard=true;
  }
 }
 return wildcard?SocketBind::wildcard:SocketBind::missing;
}
bool OnlyLoopbackInterface(){
 DIR* dir=opendir("/sys/class/net");if(!dir)throw std::runtime_error("isolated_network_required");
 bool saw_lo=false,other=false;errno=0;
 while(auto* entry=readdir(dir)){
  std::string name=entry->d_name;if(name=="."||name=="..")continue;
  if(name=="lo")saw_lo=true;else other=true;
  errno=0;
 }
 bool clean=errno==0;closedir(dir);return clean&&saw_lo&&!other;
}
void VerifyNode(const Node& n){
 if(Birth(n.pid)!=n.birth)throw std::runtime_error("fixture_process_replaced");
 auto bound=UdpOwned(n.port,SocketInodes(n.pid));
 if(bound==SocketBind::missing)throw std::runtime_error("fixture_socket_unowned");
}
}
void VerifyFixture(const Fixture& f){
#ifdef __linux__
 if(!OnlyLoopbackInterface())throw std::runtime_error("isolated_network_required");
 std::set<std::pair<unsigned,unsigned long long>> identities;std::set<unsigned> ports;
 for(const auto& n:f.sources){if(!identities.insert({n.pid,n.birth}).second||!ports.insert(n.port).second)throw std::runtime_error("fixture_duplicate");VerifyNode(n);}if(!identities.insert({f.target.pid,f.target.birth}).second||!ports.insert(f.target.port).second)throw std::runtime_error("fixture_duplicate");VerifyNode(f.target);
#else
 (void)f;throw std::runtime_error("linux_fixture_required");
#endif
}
}
