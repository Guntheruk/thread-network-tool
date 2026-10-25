#pragma once
#include "network_move.hpp"
#include <string>
#include <vector>
namespace tnt::move::worker {
struct Node { std::string id; unsigned pid=0; unsigned long long birth=0; unsigned port=0; };
struct Input {
 Input()=default;
 Input(const Input&)=default;
 Input& operator=(const Input&)=default;
 Input(Input&&)=default;
 Input& operator=(Input&&)=default;
 ~Input(){Wipe(source_dataset);Wipe(target_dataset);}
 std::string mode, operation, review, session, discovery, connectivity, manifest, inventory, expected;
 std::string lifecycle_directory;
 unsigned long long fenced_at_ms=0;
 unsigned long long source_generation=0,target_generation=0;
 Bytes source_dataset,target_dataset;
 std::vector<std::string> source_ids;
 std::string target_id;
 unsigned delay=0;
};
struct Fixture { std::string id; std::vector<Node> sources; Node target; unsigned long long connectivity_checked_at_ms=0; bool connectivity_verified=false, discard_set_result=false; };
Input ReadInput();
Fixture ReadFixture(const Input&);
std::string Sha256(const std::string&);
std::string DatasetCommitment(const Bytes&);
std::string Binding(const Input&, const Fixture&);
std::string RecoveryBinding(const Input&, const Fixture&);
void VerifyFixture(const Fixture&);
}
