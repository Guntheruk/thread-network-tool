#include "network_move_worker_lifecycle.hpp"
#include <cerrno>
#include <fstream>
#include <stdexcept>
#include <string>
#include <sys/file.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
namespace tnt::move::worker {
namespace {
int Dir(const std::string& path){struct stat st{};if(lstat(path.c_str(),&st)||!S_ISDIR(st.st_mode)||st.st_uid!=geteuid()||(st.st_mode&077)!=0)throw std::runtime_error("lifecycle_untrusted");int fd=open(path.c_str(),O_RDONLY|O_DIRECTORY|O_CLOEXEC|O_NOFOLLOW);if(fd<0)throw std::runtime_error("lifecycle_unavailable");return fd;}
}
void LeaseOpen(int& fd,const std::string& directory){int d=Dir(directory);fd=openat(d,"global.lock",O_CREAT|O_RDWR|O_CLOEXEC|O_NOFOLLOW,0600);close(d);struct stat st{};bool trusted=fd>=0&&fstat(fd,&st)==0&&S_ISREG(st.st_mode)&&st.st_uid==geteuid()&&(st.st_mode&07777)==0600&&st.st_nlink==1;if(!trusted||flock(fd,LOCK_EX|LOCK_NB)!=0){if(fd>=0)close(fd);fd=-1;throw std::runtime_error("worker_busy");}}
Lease::Lease(){std::string path="/tmp/tnt-app-move-"+std::to_string(geteuid());if(mkdir(path.c_str(),0700)&&errno!=EEXIST)throw std::runtime_error("lease_unavailable");LeaseOpen(fd_,path);}
Lease::Lease(const std::string& directory){LeaseOpen(fd_,directory);}
Lease::~Lease(){if(fd_>=0){flock(fd_,LOCK_UN);close(fd_);}}
void WriteReceipt(const std::string& directory,const std::string& operation,const std::string& binding,unsigned long long fenced_at_ms,const std::string& disposition){int d=Dir(directory);std::string name="receipt-"+operation;if(disposition=="started"&&faccessat(d,name.c_str(),F_OK,AT_SYMLINK_NOFOLLOW)==0){close(d);throw std::runtime_error("operation_already_started");}int fd=openat(d,(name+".tmp").c_str(),O_CREAT|O_EXCL|O_WRONLY|O_CLOEXEC|O_NOFOLLOW,0600);if(fd<0){close(d);throw std::runtime_error("receipt_unavailable");}std::string value="TNT-APP-MOVE-RECEIPT/1\n"+operation+"\n"+binding+"\n"+std::to_string(fenced_at_ms)+"\n"+disposition+"\n";bool ok=write(fd,value.data(),value.size())==static_cast<ssize_t>(value.size())&&fsync(fd)==0;
#ifdef __APPLE__
if(ok)ok=fcntl(fd,F_FULLFSYNC)==0;
#endif
close(fd);if(ok)ok=renameat(d,(name+".tmp").c_str(),d,name.c_str())==0&&fsync(d)==0;close(d);if(!ok)throw std::runtime_error("receipt_write_failed");}
bool ReadReceipt(const std::string& directory,const std::string& operation,const std::string& binding,unsigned long long fenced_at_ms){int d=Dir(directory);std::string name="receipt-"+operation;int fd=openat(d,name.c_str(),O_RDONLY|O_CLOEXEC|O_NOFOLLOW);close(d);if(fd<0)return false;struct stat st{};if(fstat(fd,&st)||!S_ISREG(st.st_mode)||st.st_uid!=geteuid()||(st.st_mode&077)!=0||st.st_size>512){close(fd);return false;}std::string data(st.st_size,'\0');auto n=read(fd,data.data(),data.size());close(fd);if(n!=static_cast<ssize_t>(data.size()))return false;std::string prefix="TNT-APP-MOVE-RECEIPT/1\n"+operation+"\n"+binding+"\n"+std::to_string(fenced_at_ms)+"\n";if(data.rfind(prefix,0)!=0)return false;auto rest=data.substr(prefix.size());return rest=="started\n"||rest=="accepted\n"||rest=="rejected\n"||rest=="uncertain\n"||rest=="proven_not_sent\n";}
}
