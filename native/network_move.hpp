#pragma once
#include <chrono>
#include <cstdint>
#include <functional>
#include <map>
#include <mutex>
#include <string>
#include <vector>

namespace tnt::move {
using Bytes = std::vector<uint8_t>;
using Fields = std::map<uint8_t, Bytes>;
struct Endpoint { std::string address; uint16_t port = 0; };
struct Request {
    std::string operation_id;
    std::vector<Endpoint> sources;
    Endpoint target;
    Bytes source_dataset, target_dataset;
    uint32_t delay_ms = 0;
    bool controlled_empty = false, manual_recovery = false;
    ~Request();
};
struct ReadResult { bool ok = false; Bytes active; Fields pending; };
enum class Disposition { proven_not_sent, accepted, rejected, uncertain };
struct Result {
    Disposition disposition = Disposition::proven_not_sent;
    std::string reason = "not_prepared";
    std::string operation_id;
    unsigned petitions = 0, pending_set_invocations = 0;
};
class Transport {
public:
    virtual ~Transport() = default;
    virtual void ResetReadSessions() {}
    virtual ReadResult Read(const Endpoint&, const Bytes& pskc) = 0;
    virtual bool PetitionSource(const Endpoint&, const Bytes& pskc) = 0;
    virtual Disposition SetSourcePending(const Fields&) = 0;
};
class Fence {
public:
    virtual ~Fence() = default;
    // Must atomically refuse an existing unresolved fence, including another operation ID.
    virtual bool Arm(const std::string& operation_id) = 0;
};
void Wipe(Bytes&);
bool DecodeHex(const std::string&, Bytes&);
bool DecodeDataset(const Bytes&, Fields&, std::string& reason);
std::string DispositionName(Disposition);
std::string ResultJson(const Result&);

class Operation {
public:
    using Clock = std::function<std::chrono::steady_clock::time_point()>;
    explicit Operation(Transport&, Clock = [] { return std::chrono::steady_clock::now(); });
    ~Operation();
    Operation(const Operation&) = delete;
    Operation& operator=(const Operation&) = delete;
    bool Prepare(Request, std::string& reason);
    Result Confirm(Fence&);
    // Observation authenticates supplied refreshed endpoints with target credentials; never petitions or SETs.
    bool ObservePending(std::string& reason);
    bool Observe(const std::vector<Endpoint>& refreshed_sources, const Endpoint& refreshed_target, std::string& reason);
private:
    bool CheckSnapshots(std::string& reason);
    std::mutex mutex_;
    Transport& transport_;
    Clock now_;
    Request request_;
    Fields source_, target_, pending_;
    std::chrono::steady_clock::time_point prepared_at_;
    bool ready_ = false, consumed_ = false, prepare_attempted_ = false, dispatched_ = false;
};
}
