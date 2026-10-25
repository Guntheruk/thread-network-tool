#pragma once

#include <functional>
#include <string>
#include <vector>

namespace tnt::move {

// Deliberately contains no dataset, key, endpoint, label, or credential handle.
struct JournalRecord {
  std::string operation_id;
  unsigned long long revision = 0;
  std::string profile;
  std::string stage;
  std::string disposition;
  std::string source_commitment;
  std::string target_commitment;
  std::string target_router_binding;
  std::vector<std::string> router_bindings;
  unsigned long long fenced_at_ms = 0;
  unsigned long long observe_until_ms = 0;
  unsigned long long observation_seconds = 0;
  unsigned long long stable_since_ms = 0;
  unsigned long long stable_last_ms = 0;
  std::string reason;
};

bool IsTerminal(const JournalRecord &record);
std::string EncodeRecord(const JournalRecord &record);
JournalRecord DecodeRecord(const std::string &text);

// POSIX only. Every action obtains the same cross-process flock. A record is
// replaced only after its contents are durable, followed by a directory fsync.
// The caller must supply an existing owner-only directory. No automatic reset.
class Journal {
 public:
  using FaultHook = std::function<void(const char *)>;
  explicit Journal(std::string directory, FaultHook fault = {});
  void Initialize();
  std::string Read();
  JournalRecord Begin(JournalRecord record);
  JournalRecord Update(JournalRecord record, unsigned long long expected_revision);

 private:
  std::string directory_;
  FaultHook fault_;
};

}  // namespace tnt::move
