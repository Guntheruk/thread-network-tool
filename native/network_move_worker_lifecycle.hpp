#pragma once
#include <string>
namespace tnt::move::worker {
class Lease {
 int fd_=-1;
public:
 Lease();~Lease();Lease(const Lease&)=delete;Lease& operator=(const Lease&)=delete;
 bool held() const {return fd_>=0;}
};
void WriteReceipt(const std::string& directory,const std::string& operation,const std::string& binding,unsigned long long fenced_at_ms,const std::string& disposition);
bool ReadReceipt(const std::string& directory,const std::string& operation,const std::string& binding,unsigned long long fenced_at_ms);
}
