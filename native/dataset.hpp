#pragma once
#include <array>
#include <cstdint>
#include <string>
#include <vector>
namespace tnt {
struct Dataset {
    std::string network_name;
    std::string extended_pan_id;
    std::string pan_id;
    std::string active_timestamp;
    uint16_t channel = 0;
    std::array<uint8_t,16> pskc{};
    std::vector<unsigned> unknown_types;
    ~Dataset() { volatile uint8_t* p=pskc.data(); for(size_t i=0;i<pskc.size();++i) p[i]=0; }
};
bool ParseDataset(const char* hex, Dataset& out, std::string& error_code);
std::string InspectJson(const Dataset& dataset);
std::string ErrorJson(const std::string& code);
std::string JsonString(const std::string& value);
}
