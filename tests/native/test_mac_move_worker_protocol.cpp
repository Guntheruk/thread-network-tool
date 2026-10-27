#include "mac_move_worker_protocol.hpp"
#include "move_journal.hpp"
#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <sstream>
#include <unistd.h>

using namespace tnt::move;
using namespace tnt::move::mac_worker;
#define CHECK(x) do { if (!(x)) { std::cerr << "failed at line " << __LINE__ << "\n"; std::exit(1); } } while (0)

namespace {
Bytes Number(uint64_t n, size_t size) {
    Bytes value(size);
    for (size_t i = size; i > 0; --i) { value[i - 1] = n & 255; n >>= 8; }
    return value;
}
Bytes Dataset(bool target) {
    Fields fields{{0,{0,0,15}}, {1,{0x12,0x34}}, {2,Bytes(8,target ? 2 : 1)},
        {3,{'L','a','b'}}, {4,Bytes(16,target ? 0xbb : 0xaa)},
        {5,Bytes(16,target ? 0x22 : 0x11)}, {7,{0xfd,0,0,0,0,0,0,1}},
        {12,{0,0,0}}, {14,Number((target ? 10 : 20) << 16,8)},
        {53,{0,4,0,0x1f,0xff,0xe0}}};
    Bytes raw;
    for (const auto& [type, bytes] : fields) {
        raw.push_back(type); raw.push_back(static_cast<uint8_t>(bytes.size()));
        raw.insert(raw.end(), bytes.begin(), bytes.end());
    }
    return raw;
}
std::string Hex(const Bytes& bytes) {
    static constexpr char digits[] = "0123456789abcdef";
    std::string out;
    for (auto b : bytes) { out.push_back(digits[b >> 4]); out.push_back(digits[b & 15]); }
    return out;
}
std::string InputText() {
    return "TNT-MAC-MOVE/1\nmode inspect\noperation_id " + std::string(64,'a') +
        "\nreview_revision " + std::string(64,'b') +
        "\nsource_generation 1\ntarget_generation 2\nsession_id " + std::string(64,'c') +
        "\ndiscovery_revision " + std::string(64,'d') +
        "\nconnectivity_revision " + std::string(64,'e') +
        "\nsource_dataset " + Hex(Dataset(false)) + "\ntarget_dataset " + Hex(Dataset(true)) +
        "\nsource_count 2\nsource_router " + std::string(64,'1') + " 127.0.0.1 1001\n" +
        "source_router " + std::string(64,'2') + " ::1 1002\n" +
        "target_router " + std::string(64,'3') + " fd00::1 1003\n" +
        "delay_ms 300000\ninventory_attestation " + std::string(64,'f') +
        "\ncontrolled_empty yes\nmanual_recovery yes\nlifecycle_directory /tmp/tnt-synthetic\n" +
        "fenced_at_ms 0\nexpected_binding -\nEND\n";
}
Input Parse(const std::string& body) { std::istringstream in(body); return ReadInput(in); }
bool Rejects(const std::string& body) {
    try { Parse(body); return false; } catch (const std::exception&) { return true; }
}
std::string Replace(std::string body, const std::string& from, const std::string& to) {
    auto pos = body.find(from);
    CHECK(pos != body.npos);
    body.replace(pos, from.size(), to);
    return body;
}
}

int main() {
    auto x = Parse(InputText());
    CHECK(x.sources.size() == 2 && x.target.endpoint.port == 1003);
    CHECK(RouterBinding(x.sources[0]) != RouterBinding(x.sources[1]));
    CHECK(Binding(x) == Binding(Parse(InputText())));
    CHECK(DatasetCommitment(x.source_dataset) != DatasetCommitment(x.target_dataset));
    CHECK(Matches(x.source_dataset, Dataset(false)));
    CHECK(!Matches(x.source_dataset, Dataset(true)));
    auto changed = Parse(Replace(InputText(), "127.0.0.1 1001", "127.0.0.1 1004"));
    CHECK(Binding(changed) != Binding(x));
    CHECK(RecoveryBinding(changed) != RecoveryBinding(x));
    CHECK(Rejects(Replace(InputText(), "127.0.0.1 1001", "8.8.8.8 1001")));
    CHECK(Rejects(Replace(InputText(), "127.0.0.1 1001", "fe80::1 1001")));
    CHECK(Rejects(Replace(InputText(), "127.0.0.1 1001", "localhost 1001")));
    CHECK(Rejects(Replace(InputText(), "::1 1002", "0:0:0:0:0:0:0:1 1002")));
    CHECK(Rejects(Replace(InputText(), "127.0.0.1 1001", "127.0.0.1 0")));
    CHECK(Rejects(Replace(InputText(), std::string(64,'2') + " ::1 1002", std::string(64,'1') + " ::1 1002")));
    CHECK(Rejects(Replace(InputText(), "::1 1002", "127.0.0.1 1001")));
    CHECK(Rejects(Replace(InputText(), "controlled_empty yes", "controlled_empty no")));
    CHECK(Rejects(Replace(InputText(), "manual_recovery yes", "manual_recovery no")));
    auto too_many = Replace(InputText(), "source_count 2", "source_count 9");
    std::string extra;
    for (int i = 0; i < 7; ++i)
        extra += "source_router " + std::string(64, "456789a"[i]) + " ::1 " + std::to_string(1004 + i) + "\n";
    too_many = Replace(too_many, "target_router ", extra + "target_router ");
    CHECK(Rejects(too_many));
    CHECK(Rejects(Replace(InputText(), "delay_ms 300000", "delay_ms 299999")));
    CHECK(Rejects(InputText() + "extra\n"));
    CHECK(Rejects(Replace(InputText(), "mode inspect", "mode dispatch")));
    char path[] = "/tmp/tnt-mac-worker-journal-XXXXXX";
    CHECK(mkdtemp(path) != nullptr);
    auto fenced = Parse(InputText());
    fenced.mode = "dispatch";
    fenced.fenced_at_ms = 1000;
    fenced.lifecycle_directory = path;
    Journal journal(path);
    journal.Initialize();
    JournalRecord record;
    record.operation_id = fenced.operation;
    record.revision = 1;
    record.profile = kProfile;
    record.stage = "dispatch_fenced";
    record.disposition = "unknown";
    record.source_commitment = DatasetCommitment(fenced.source_dataset);
    record.target_commitment = DatasetCommitment(fenced.target_dataset);
    record.target_router_binding = RouterBinding(fenced.target);
    for (const auto& router : fenced.sources) record.router_bindings.push_back(RouterBinding(router));
    std::sort(record.router_bindings.begin(), record.router_bindings.end());
    record.fenced_at_ms = 1000;
    record.observe_until_ms = 331000;
    record.observation_seconds = 30;
    record.reason = "none";
    journal.Begin(record);
    CHECK(VerifyJournal(fenced, true));
    auto wrong = fenced;
    wrong.sources[0].endpoint.port++;
    CHECK(!VerifyJournal(wrong, true));
    wrong = fenced;
    wrong.fenced_at_ms++;
    CHECK(!VerifyJournal(wrong, true));
    wrong = fenced;
    wrong.operation = std::string(64, '0');
    CHECK(!VerifyJournal(wrong, true));
    CHECK(VerifyJournal(fenced, false));
    unlink((std::string(path) + "/operation").c_str());
    unlink((std::string(path) + "/writer.lock").c_str());
    unlink((std::string(path) + "/used-" + fenced.operation).c_str());
    rmdir(path);
    std::cout << "Mac move worker protocol: strict input, pinned endpoints, full datasets, redacted bindings\n";
}
