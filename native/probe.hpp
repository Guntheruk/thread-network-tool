#pragma once
#include "dataset.hpp"
#include <string>
namespace tnt {
struct ProbeResult { std::string json; int exit_code; };
ProbeResult Probe(const std::string& address, unsigned port, const Dataset& dataset);
}
