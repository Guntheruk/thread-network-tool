#pragma once

#include "network_move.hpp"
#include <istream>
#include <string>
#include <vector>

namespace tnt::move::mac_worker {

inline constexpr const char* kProfile = "eero-source-network-alpha-v1";

struct Router {
    std::string identity;
    Endpoint endpoint;
};

struct Input {
    std::string mode, operation, review, session, discovery, connectivity;
    std::string inventory, lifecycle_directory, expected;
    unsigned long long source_generation = 0, target_generation = 0;
    unsigned long long fenced_at_ms = 0;
    Bytes source_dataset, target_dataset;
    std::vector<Router> sources;
    Router target;
    unsigned delay = 0;
    bool controlled_empty = false, manual_recovery = false;
    ~Input() { Wipe(source_dataset); Wipe(target_dataset); }
};

Input ReadInput(std::istream&);
std::string Sha256(const std::string&);
std::string DatasetCommitment(const Bytes&);
std::string RouterBinding(const Router&);
std::string Binding(const Input&);
std::string RecoveryBinding(const Input&);
bool Matches(const Bytes&, const Bytes&);
bool VerifyJournal(const Input&, bool dispatch);

} // namespace tnt::move::mac_worker
