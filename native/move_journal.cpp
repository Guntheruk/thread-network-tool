#include "move_journal.hpp"

#include <algorithm>
#include <limits>
#include <map>
#include <set>
#include <stdexcept>
#include <utility>

#ifndef _WIN32
#include <cerrno>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace tnt::move {
namespace {
[[noreturn]] void Fail() { throw std::runtime_error("journal_unavailable"); }
bool Hex(const std::string &s) {
  return s.size() == 64 && s.find_first_not_of("0123456789abcdef") == std::string::npos;
}
bool Member(const std::string &s, std::initializer_list<const char *> choices) {
  return std::any_of(choices.begin(), choices.end(), [&](const char *c) { return s == c; });
}
unsigned long long Number(const std::string &s) {
  if (s.empty() || s.size() > 16 || s.find_first_not_of("0123456789") != std::string::npos ||
      (s.size() > 1 && s.front() == '0')) Fail();
  unsigned long long value = 0;
  for (char c : s) value = value * 10 + static_cast<unsigned>(c - '0');
  if (value > 9007199254740991ULL) Fail();  // Exact in all Dart targets.
  return value;
}
void Validate(const JournalRecord &r) {
  if (!Hex(r.operation_id) || r.revision == 0 || r.revision > 9007199254740991ULL ||
      !Member(r.profile, {"openthread-posix-lab-v1", "eero-source-network-alpha-v1"}) ||
      !Member(r.stage, {"dispatch_fenced", "observing", "needs_attention", "observation_stopped", "verified_complete", "verified_configuration", "verified_unchanged", "proven_not_sent"}) ||
      !Member(r.disposition, {"unknown", "accepted", "rejected", "uncertain", "proven_not_sent"}) ||
      !Hex(r.source_commitment) || !Hex(r.target_commitment) || !Hex(r.target_router_binding) ||
      r.source_commitment == r.target_commitment ||
      r.router_bindings.empty() || r.router_bindings.size() > 32 ||
      r.fenced_at_ms == 0 || r.observe_until_ms <= r.fenced_at_ms ||
      r.observe_until_ms > 9007199254740991ULL ||
      r.observation_seconds < 1 || r.observation_seconds > 3600 ||
      ((r.stable_since_ms == 0) != (r.stable_last_ms == 0)) ||
      (r.stable_since_ms != 0 && (r.stable_since_ms <= r.fenced_at_ms ||
        r.stable_last_ms < r.stable_since_ms || r.stable_last_ms > 9007199254740991ULL)) ||
      !Member(r.reason, {"none", "worker_accepted", "worker_rejected", "worker_not_sent", "worker_uncertain", "worker_failure", "journal_failure", "restart_requires_reads", "credentials_required", "recovery_binding_mismatch", "verification_pending", "verification_failed", "verification_complete", "configuration_verified", "verification_unchanged", "observation_stopped"})) Fail();
  if (!std::is_sorted(r.router_bindings.begin(), r.router_bindings.end()) ||
      std::adjacent_find(r.router_bindings.begin(), r.router_bindings.end()) != r.router_bindings.end()) Fail();
  for (const auto &binding : r.router_bindings) if (!Hex(binding) || binding == r.target_router_binding) Fail();
  if (r.stage == "dispatch_fenced" && (r.disposition != "unknown" || r.reason != "none" || r.stable_since_ms != 0)) Fail();
  if (r.stage == "proven_not_sent" && r.disposition != "proven_not_sent") Fail();
  if (Member(r.stage, {"verified_complete", "verified_configuration"}) && !Member(r.disposition, {"accepted", "uncertain"})) Fail();
  if (r.stage == "verified_complete" && (r.profile != "openthread-posix-lab-v1" || r.reason != "verification_complete")) Fail();
  if (r.stage == "verified_configuration" && (r.profile != "eero-source-network-alpha-v1" || r.reason != "configuration_verified")) Fail();
  if (r.stage == "verified_unchanged" && r.disposition != "rejected") Fail();
  if (Member(r.stage, {"verified_complete", "verified_configuration", "verified_unchanged"}) && (r.stable_since_ms == 0 ||
      r.stable_last_ms < r.observe_until_ms ||
      r.stable_last_ms - r.stable_since_ms < r.observation_seconds * 1000)) Fail();
}

#ifndef _WIN32
struct Fd {
  int value = -1;
  explicit Fd(int fd) : value(fd) { if (fd < 0) Fail(); }
  ~Fd() { if (value >= 0) close(value); }
  Fd(const Fd &) = delete;
  Fd &operator=(const Fd &) = delete;
};
void CheckFile(int fd) {
  struct stat st {};
  if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_uid != geteuid() ||
      (st.st_mode & 07777) != 0600 || st.st_nlink != 1) Fail();
}
int OpenDirectory(const std::string &path) {
  if (path.empty() || path.front() != '/') Fail();
  Fd directory(open(path.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
  struct stat st {};
  if (fstat(directory.value, &st) != 0 || !S_ISDIR(st.st_mode) ||
      st.st_uid != geteuid() || (st.st_mode & 07777) != 0700) Fail();
  const int result = directory.value;
  directory.value = -1;
  return result;
}
void Sync(int fd, bool regular) {
  if (fsync(fd) != 0) Fail();
#ifdef __APPLE__
  // Request the disk-cache flush for regular files, rather than claiming that
  // Dart flush()/rename alone establishes power-loss durability on macOS.
  if (regular && fcntl(fd, F_FULLFSYNC) != 0) Fail();
#else
  (void)regular;
#endif
}
struct LockedDirectory {
  Fd directory;
  Fd lock;
  explicit LockedDirectory(const std::string &path)
      : directory(OpenDirectory(path)),
        lock(openat(directory.value, "writer.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600)) {
    CheckFile(lock.value);
    if (flock(lock.value, LOCK_EX | LOCK_NB) != 0) throw std::runtime_error("journal_busy");
    // Also makes an app-created journal directory durable before any fence.
    Fd parent(openat(directory.value, "..", O_RDONLY | O_DIRECTORY | O_CLOEXEC));
    Sync(parent.value, false);
  }
};
std::string ReadAt(int directory) {
  const int raw = openat(directory, "operation", O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
  if (raw < 0) { if (errno == ENOENT) return {}; Fail(); }
  Fd file(raw);
  CheckFile(file.value);
  std::string result;
  char bytes[1024];
  for (;;) {
    const auto n = read(file.value, bytes, sizeof(bytes));
    if (n < 0) { if (errno == EINTR) continue; Fail(); }
    if (n == 0) break;
    result.append(bytes, static_cast<size_t>(n));
    if (result.size() > 8192) Fail();
  }
  if (result.empty()) Fail();
  DecodeRecord(result);
  return result;
}
void WriteAt(int directory, const JournalRecord &record, const Journal::FaultHook &fault) {
  const auto text = EncodeRecord(record);
  // A previous pre-rename crash may leave a temporary file. It was never an
  // authorized dispatch fence. Refuse unexpected file types/owners/links.
  int stale = openat(directory, "operation.next", O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
  if (stale >= 0) {
    Fd old(stale); CheckFile(old.value);
    if (unlinkat(directory, "operation.next", 0) != 0) Fail();
  } else if (errno != ENOENT) Fail();
  Fd file(openat(directory, "operation.next", O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0600));
  CheckFile(file.value);
  size_t offset = 0;
  while (offset < text.size()) {
    const auto n = write(file.value, text.data() + offset, text.size() - offset);
    if (n < 0) { if (errno == EINTR) continue; Fail(); }
    if (n == 0) Fail();
    offset += static_cast<size_t>(n);
  }
  Sync(file.value, true);
  if (fault) fault("after_file_sync");
  if (renameat(directory, "operation.next", directory, "operation") != 0) Fail();
  if (fault) fault("after_rename");
  Sync(directory, false);
  if (fault) fault("after_directory_sync");
}
#endif
}  // namespace

bool IsTerminal(const JournalRecord &r) {
  return r.stage == "proven_not_sent" || r.stage == "verified_complete" || r.stage == "verified_configuration" || r.stage == "verified_unchanged";
}
std::string EncodeRecord(const JournalRecord &r) {
  Validate(r);
  std::string routers;
  for (const auto &binding : r.router_bindings) { if (!routers.empty()) routers += ','; routers += binding; }
  return "schema=1\noperation=" + r.operation_id + "\nrevision=" + std::to_string(r.revision) +
      "\nprofile=" + r.profile + "\nstage=" + r.stage + "\ndisposition=" + r.disposition +
      "\nsource=" + r.source_commitment + "\ntarget=" + r.target_commitment + "\ntarget_router=" + r.target_router_binding + "\nrouters=" + routers +
      "\nfenced_at_ms=" + std::to_string(r.fenced_at_ms) + "\nobserve_until_ms=" + std::to_string(r.observe_until_ms) +
      "\nobservation_seconds=" + std::to_string(r.observation_seconds) +
      "\nstable_since_ms=" + std::to_string(r.stable_since_ms) + "\nstable_last_ms=" + std::to_string(r.stable_last_ms) +
      "\nreason=" + r.reason + "\n";
}
JournalRecord DecodeRecord(const std::string &text) {
  if (text.empty() || text.size() > 8192 || text.back() != '\n') Fail();
  std::map<std::string, std::string> fields;
  size_t offset = 0;
  while (offset < text.size()) {
    const size_t end = text.find('\n', offset);
    const auto line = text.substr(offset, end - offset);
    const auto split = line.find('=');
    if (split == std::string::npos || !fields.emplace(line.substr(0, split), line.substr(split + 1)).second) Fail();
    offset = end + 1;
  }
  if (fields.size() != 16 || fields["schema"] != "1") Fail();
  JournalRecord r;
  r.operation_id = fields["operation"]; r.revision = Number(fields["revision"]);
  r.profile = fields["profile"]; r.stage = fields["stage"]; r.disposition = fields["disposition"];
  r.source_commitment = fields["source"]; r.target_commitment = fields["target"];
  r.target_router_binding = fields["target_router"];
  r.fenced_at_ms = Number(fields["fenced_at_ms"]); r.observe_until_ms = Number(fields["observe_until_ms"]);
  r.observation_seconds = Number(fields["observation_seconds"]);
  r.stable_since_ms = Number(fields["stable_since_ms"]); r.stable_last_ms = Number(fields["stable_last_ms"]);
  r.reason = fields["reason"];
  const auto routers = fields["routers"];
  offset = 0;
  for (;;) {
    const auto end = routers.find(',', offset);
    r.router_bindings.push_back(routers.substr(offset, end - offset));
    if (end == std::string::npos) break;
    offset = end + 1;
  }
  Validate(r);
  if (EncodeRecord(r) != text) Fail();  // One canonical, bounded representation.
  return r;
}
Journal::Journal(std::string directory, FaultHook fault)
    : directory_(std::move(directory)), fault_(std::move(fault)) {}
void Journal::Initialize() {
#ifdef _WIN32
  Fail();
#else
  if (directory_.empty() || directory_.front() != '/') Fail();
  if (mkdir(directory_.c_str(), 0700) != 0 && errno != EEXIST) Fail();
  LockedDirectory locked(directory_);
  Sync(locked.directory.value, false);
#endif
}
std::string Journal::Read() {
#ifdef _WIN32
  Fail();
#else
  LockedDirectory locked(directory_);
  return ReadAt(locked.directory.value);
#endif
}
JournalRecord Journal::Begin(JournalRecord record) {
#ifdef _WIN32
  Fail();
#else
  Validate(record);
  if (record.revision != 1 || record.stage != "dispatch_fenced") Fail();
  LockedDirectory locked(directory_);
  const auto previous = ReadAt(locked.directory.value);
  if (!previous.empty()) {
    const auto old = DecodeRecord(previous);
    if (old.operation_id == record.operation_id) throw std::runtime_error("operation_already_exists");
    if (!IsTerminal(old)) throw std::runtime_error("unresolved_operation");
  }
  // Permanent random-ID tombstones prevent replay after a later completed
  // operation has replaced the current record. They contain no network data.
  const auto used = "used-" + record.operation_id;
  const int marker_fd = openat(locked.directory.value, used.c_str(),
      O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0600);
  if (marker_fd < 0) {
    if (errno == EEXIST) throw std::runtime_error("operation_already_exists");
    Fail();
  }
  Fd marker(marker_fd);
  CheckFile(marker.value);
  Sync(marker.value, true);
  Sync(locked.directory.value, false);
  WriteAt(locked.directory.value, record, fault_);
  return record;
#endif
}
JournalRecord Journal::Update(JournalRecord record, unsigned long long expected_revision) {
#ifdef _WIN32
  Fail();
#else
  Validate(record);
  LockedDirectory locked(directory_);
  const auto previous = ReadAt(locked.directory.value);
  if (previous.empty()) Fail();
  const auto old = DecodeRecord(previous);
  if (old.operation_id != record.operation_id || old.revision != expected_revision ||
      record.revision != old.revision + 1 || IsTerminal(old) ||
      record.stage == "dispatch_fenced" || old.profile != record.profile ||
      old.source_commitment != record.source_commitment || old.target_commitment != record.target_commitment ||
      old.router_bindings != record.router_bindings || old.target_router_binding != record.target_router_binding || old.fenced_at_ms != record.fenced_at_ms ||
      old.observe_until_ms != record.observe_until_ms ||
      old.observation_seconds != record.observation_seconds ||
      (record.stage == "proven_not_sent" && old.stage != "dispatch_fenced") ||
      (old.stage != "dispatch_fenced" && old.disposition != record.disposition)) Fail();
  WriteAt(locked.directory.value, record, fault_);
  return record;
#endif
}
}  // namespace tnt::move
