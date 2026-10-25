#pragma once
#include "dataset.hpp"
#include <string>
namespace tnt { std::string Probe(const std::string& address, unsigned port, const Dataset& dataset); }
