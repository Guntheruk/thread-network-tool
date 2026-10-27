#include "network_move_worker_lifecycle.hpp"
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#define CHECK(x) do { if(!(x)){std::cerr<<"CHECK failed line "<<__LINE__<<": " #x "\n";std::exit(1);} }while(0)
#include <sys/stat.h>
#include <unistd.h>
using namespace tnt::move::worker;
int main(){
 char path[]="/tmp/tnt-app-worker-lifecycle-XXXXXX";char* created=mkdtemp(path);CHECK(created);std::string dir=created,op(64,'a'),binding(64,'b');
 {
  Lease active;bool blocked=false;try{Lease concurrent;}catch(const std::runtime_error&){blocked=true;}CHECK(blocked);
  WriteReceipt(dir,op,binding,1000,"started");CHECK(ReadReceipt(dir,op,binding,1000));CHECK(!ReadReceipt(dir,op,std::string(64,'c'),1000));CHECK(!ReadReceipt(dir,op,binding,1001));
  bool replay=false;try{WriteReceipt(dir,op,binding,1000,"started");}catch(const std::runtime_error&){replay=true;}CHECK(replay);
  WriteReceipt(dir,op,binding,1000,"accepted");CHECK(ReadReceipt(dir,op,binding,1000));
 }
 {
  Lease active(dir);bool blocked=false;try{Lease concurrent(dir);}catch(const std::runtime_error&){blocked=true;}CHECK(blocked);
 }
 unlink((dir+"/receipt-"+op).c_str());unlink((dir+"/global.lock").c_str());rmdir(dir.c_str());std::cout<<"worker lifecycle checks passed: 7 checks\n";
}
