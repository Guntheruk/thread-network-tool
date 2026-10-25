#pragma once
#include <cstddef>
#include <cstdint>
#include <string>

namespace tnt {
struct DiscoveryTxt {
    std::string network_name;
    std::string extended_pan_id;
    std::string thread_version;
};

// Malformed entries and unknown keys are ignored. Values are never echoed raw.
DiscoveryTxt ParseDiscoveryTxt(const uint8_t* data, size_t size);
bool DiscoveryUtf8(const std::string& value);
std::string DiscoveryJsonString(const std::string& value);
struct DiscoveryResult { std::string json; int exit_code; };
DiscoveryResult Discover();
}
