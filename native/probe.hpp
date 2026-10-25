#pragma once
#include "dataset.hpp"
#include <commissioner/network_data.hpp>
#include <string>
namespace tnt {
struct ProbeResult { std::string json; int exit_code; };
std::string ActiveTimestampJson(const ot::commissioner::ActiveOperationalDataset& active);
ProbeResult Probe(const std::string& address, unsigned port, const Dataset& dataset);
}
