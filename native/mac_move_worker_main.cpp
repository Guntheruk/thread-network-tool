#include "mac_move_worker_protocol.hpp"
#include "network_move_commissioner.hpp"
#include "network_move_worker_lifecycle.hpp"
#include "move_journal.hpp"
#include "dataset.hpp"

#include <algorithm>
#include <chrono>
#include <csignal>
#include <iostream>
#include <stdexcept>
#include <unistd.h>

using namespace tnt::move;
using namespace tnt::move::mac_worker;
namespace {
uint64_t NowMs() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}
void Deadline(int) {
    const char message[] = "{\"schema_version\":1,\"disposition\":\"uncertain\",\"reason\":\"process_deadline\"}\n";
    write(STDOUT_FILENO, message, sizeof(message) - 1);
    _Exit(124);
}
std::string Q(const std::string& s) { return tnt::JsonString(s); }
void Clear(Fields& fields) { for (auto& [_, value] : fields) Wipe(value); fields.clear(); }
std::string SafeReason(const std::string& reason) {
    static const std::vector<std::string> allowed{
        "invalid_request", "hash_failed", "binding_mismatch", "invalid_dataset", "authorization_incomplete",
        "unsupported_dataset_fields", "same_network", "endpoint_role_conflict", "duplicate_endpoint",
        "invalid_endpoint", "timestamp_rollback_without_key_change", "unsupported_delay",
        "pending_dataset_overflow", "source_snapshot_changed_or_unavailable",
        "target_snapshot_changed_or_unavailable", "preflight_deadline", "operation_consumed",
        "review_expired", "unresolved_operation_fence", "petition_failed", "pending_accepted",
        "pending_rejected", "submission_unknown", "fence_time_invalid", "journal_mismatch",
        "receipt_unavailable", "receipt_write_failed", "operation_already_started", "worker_busy",
        "lifecycle_untrusted", "lifecycle_unavailable", "worker_failure"};
    return std::find(allowed.begin(), allowed.end(), reason) != allowed.end() ? reason : "worker_failure";
}
std::string Base(const Input& x, const std::string& binding) {
    std::string output = "{\"schema_version\":1,\"operation_id\":" + Q(x.operation) +
        ",\"profile_id\":" + Q(kProfile) + ",\"binding_commitment\":" + Q(binding) +
        ",\"source_commitment\":" + Q(DatasetCommitment(x.source_dataset)) +
        ",\"target_commitment\":" + Q(DatasetCommitment(x.target_dataset)) +
        ",\"source_bindings\":[";
    for (size_t i = 0; i < x.sources.size(); ++i) {
        if (i) output += ',';
        output += Q(RouterBinding(x.sources[i]));
    }
    output += "],\"target_binding\":" + Q(RouterBinding(x.target)) +
        ",\"checked_at_ms\":" + std::to_string(NowMs()) +
        ",\"profile_verified\":true,\"runtime_verified\":true,\"independent_deadline\":true";
    return output;
}
struct JournalFence final : Fence {
    const Input& input;
    explicit JournalFence(const Input& value) : input(value) {}
    bool Arm(const std::string& operation) override {
        return operation == input.operation && VerifyJournal(input, true);
    }
};
std::string Observation(const Router& router, const ReadResult& read, const Bytes& expected) {
    bool match = read.ok && read.pending.empty() && Matches(read.active, expected);
    std::string commitment;
    if (read.ok) {
        try { commitment = DatasetCommitment(read.active); } catch (...) {}
    }
    return "{\"binding\":" + Q(RouterBinding(router)) +
        ",\"dataset_commitment\":" + Q(commitment) +
        ",\"checked_at_ms\":" + std::to_string(NowMs()) +
        ",\"authenticated\":" + (read.ok ? "true" : "false") +
        ",\"pending_empty\":" + (read.ok && read.pending.empty() ? "true" : "false") +
        ",\"connectivity_verified\":false,\"full_match\":" + (match ? "true" : "false") + "}";
}
void WipeRead(ReadResult& read) { Wipe(read.active); Clear(read.pending); }
std::string Observe(const Input& x, Transport& transport, const std::string& base) {
    if (!VerifyJournal(x, false) || !worker::ReadReceipt(x.lifecycle_directory, x.operation,
            RecoveryBinding(x), x.fenced_at_ms)) throw std::runtime_error("receipt_unavailable");
    auto record = DecodeRecord(Journal(x.lifecycle_directory).Read());
    bool rejected = record.disposition == "rejected";
    Fields source, target;
    std::string why;
    if (!DecodeDataset(x.source_dataset, source, why) || !DecodeDataset(x.target_dataset, target, why))
        throw std::runtime_error("invalid_dataset");
    auto output = base + ",\"worker_terminated\":true,\"recovery_binding_verified\":true,\"sources\":[";
    bool all_converged = true;
    bool all_original_unchanged = true;
    for (size_t i = 0; i < x.sources.size(); ++i) {
        if (i) output += ',';
        bool original_match = false;
        bool converged = false;
        auto read = transport.Read(x.sources[i].endpoint, rejected ? source.at(4) : target.at(4));
        if (rejected) {
            original_match = read.ok && read.pending.empty() && Matches(read.active, x.source_dataset);
            if (!original_match) {
                transport.ResetReadSessions();
                auto changed = transport.Read(x.sources[i].endpoint, target.at(4));
                converged = changed.ok && changed.pending.empty() && Matches(changed.active, x.target_dataset);
                if (changed.ok) { WipeRead(read); read = std::move(changed); }
                else WipeRead(changed);
            }
        } else {
            converged = read.ok && read.pending.empty() && Matches(read.active, x.target_dataset);
        }
        if (!rejected && !converged) {
            transport.ResetReadSessions();
            auto original = transport.Read(x.sources[i].endpoint, source.at(4));
            original_match = original.ok && original.pending.empty() &&
                Matches(original.active, x.source_dataset);
            if (original.ok) {
                WipeRead(read);
                read = std::move(original);
            } else {
                WipeRead(original);
            }
        }
        all_original_unchanged = all_original_unchanged && original_match;
        output += Observation(x.sources[i], read, rejected ? x.source_dataset : x.target_dataset);
        WipeRead(read);
        all_converged = all_converged && converged;
    }
    auto target_read = transport.Read(x.target.endpoint, target.at(4));
    bool target_unchanged = target_read.ok && target_read.pending.empty() &&
        Matches(target_read.active, x.target_dataset);
    output += "],\"target\":" + Observation(x.target, target_read, x.target_dataset) +
        ",\"target_unchanged\":" + (target_unchanged ? "true" : "false") +
        ",\"converged\":" + (all_converged && target_unchanged ? "true" : "false") +
        ",\"original_source_unchanged_rejected\":" + (rejected && all_original_unchanged ? "true" : "false") + "}";
    WipeRead(target_read);
    Clear(source);
    Clear(target);
    return output;
}
}

int main(int argc, char** argv) {
    bool may_have_dispatched = false;
    std::string operation;
    try {
        if (argc == 2 && std::string(argv[1]) == "capabilities") {
            std::cout << "{\"schema_version\":1,\"profile_id\":" << Q(kProfile) <<
                ",\"network_writes\":true,\"authenticated_reads\":true,\"durable_fence\":true}" << std::endl;
            return 0;
        }
        if (argc != 1) throw std::runtime_error("invalid_request");
        std::signal(SIGALRM, Deadline);
        std::signal(SIGTERM, Deadline);
        alarm(1000);
        auto x = ReadInput(std::cin);
        operation = x.operation;
        worker::Lease lease(x.lifecycle_directory);
        auto binding = Binding(x);
        if (x.expected != "-" && x.expected != binding) throw std::runtime_error("binding_mismatch");
        auto base = Base(x, binding);
        auto transport = CreateCommissionerTransport(false, false);
        if (x.mode == "observe") {
            std::cout << Observe(x, *transport, base) << std::endl;
            return 0;
        }
        Request request;
        request.operation_id = x.operation;
        request.source_dataset = x.source_dataset;
        request.target_dataset = x.target_dataset;
        request.delay_ms = x.delay;
        request.controlled_empty = x.controlled_empty;
        request.manual_recovery = x.manual_recovery;
        for (const auto& source : x.sources) request.sources.push_back(source.endpoint);
        request.target = x.target.endpoint;
        Operation move(*transport);
        std::string reason;
        if (!move.Prepare(std::move(request), reason)) {
            std::cout << "{\"schema_version\":1,\"profile_id\":" << Q(kProfile) << ",\"operation_id\":" << Q(x.operation) <<
                ",\"disposition\":\"proven_not_sent\",\"reason\":" << Q(SafeReason(reason)) <<
                ",\"petitions\":0,\"pending_set_invocations\":0}" << std::endl;
            return 0;
        }
        if (x.mode == "inspect") {
            std::cout << base + ",\"ready\":true,\"disposition\":\"proven_not_sent\",\"reason\":\"ready\",\"petitions\":0,\"pending_set_invocations\":0}" << std::endl;
            return 0;
        }
        auto now = NowMs();
        if (!x.fenced_at_ms || x.fenced_at_ms > now || now - x.fenced_at_ms > 30000)
            throw std::runtime_error("fence_time_invalid");
        if (!VerifyJournal(x, true)) throw std::runtime_error("journal_mismatch");
        auto recovery = RecoveryBinding(x);
        worker::WriteReceipt(x.lifecycle_directory, x.operation, recovery, x.fenced_at_ms, "started");
        JournalFence fence(x);
        may_have_dispatched = true;
        auto result = move.Confirm(fence);
        try {
            worker::WriteReceipt(x.lifecycle_directory, x.operation, recovery, x.fenced_at_ms,
                                 DispositionName(result.disposition));
        } catch (...) {
            result.disposition = Disposition::uncertain;
            result.reason = "receipt_write_failed";
        }
        std::cout << base + ",\"disposition\":" + Q(DispositionName(result.disposition)) +
            ",\"reason\":" + Q(SafeReason(result.reason)) +
            ",\"petitions\":" + std::to_string(result.petitions) +
            ",\"pending_set_invocations\":" + std::to_string(result.pending_set_invocations) + "}" << std::endl;
        return 0;
    } catch (const std::exception& error) {
        std::cout << "{\"schema_version\":1,\"profile_id\":" << Q(kProfile) << ",\"operation_id\":" << Q(operation) <<
            ",\"disposition\":" << Q(may_have_dispatched ? "uncertain" : "proven_not_sent") <<
            ",\"reason\":" << Q(SafeReason(error.what())) << "}" << std::endl;
        return 1;
    }
}
