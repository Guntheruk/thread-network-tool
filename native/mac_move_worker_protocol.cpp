#include "mac_move_worker_protocol.hpp"
#include "move_journal.hpp"

#include <mbedtls/sha256.h>
#include <arpa/inet.h>
#include <algorithm>
#include <iomanip>
#include <limits>
#include <set>
#include <sstream>
#include <stdexcept>

namespace tnt::move::mac_worker {
namespace {
[[noreturn]] void Bad() { throw std::runtime_error("invalid_request"); }
bool Hex64(const std::string& s) {
    return s.size() == 64 && std::all_of(s.begin(), s.end(), [](char c) {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
    });
}
unsigned long long Number(const std::string& s, unsigned long long max = std::numeric_limits<unsigned long long>::max()) {
    if (s.empty() || s.size() > 20) Bad();
    unsigned long long n = 0;
    for (char c : s) {
        if (c < '0' || c > '9') Bad();
        auto digit = static_cast<unsigned>(c - '0');
        if (digit > max || n > (max - digit) / 10) Bad();
        n = n * 10 + digit;
    }
    return n;
}
class Reader {
    std::istream& in_;
    size_t total_ = 0;
public:
    explicit Reader(std::istream& in) : in_(in) {}
    std::string Line() {
        std::string s;
        char c;
        while (in_.get(c)) {
            if (++total_ > 16384 || s.size() > 1024 || c == '\r' || c == '\0') Bad();
            if (c == '\n') return s;
            s.push_back(c);
        }
        Bad();
    }
    std::string Field(const char* name) {
        auto line = Line();
        auto prefix = std::string(name) + " ";
        if (line.rfind(prefix, 0) != 0 || line.size() == prefix.size()) Bad();
        return line.substr(prefix.size());
    }
    void End() { if (Line() != "END" || in_.peek() != std::char_traits<char>::eof()) Bad(); }
};
void Clear(Fields& fields) {
    for (auto& [_, value] : fields) Wipe(value);
    fields.clear();
}
void WipeString(std::string& value) {
    volatile char* p = value.data();
    for (size_t i = 0; i < value.size(); ++i) p[i] = 0;
    value.clear();
}
bool LocalNumericIp(const std::string& s) {
    unsigned char b[16]{};
    if (inet_pton(AF_INET, s.c_str(), b) == 1) {
        char canonical[INET_ADDRSTRLEN]{};
        if (!inet_ntop(AF_INET, b, canonical, sizeof(canonical)) || s != canonical) return false;
        return b[0] == 10 || b[0] == 127 ||
            (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
            (b[0] == 192 && b[1] == 168);
    }
    if (inet_pton(AF_INET6, s.c_str(), b) == 1) {
        char canonical[INET6_ADDRSTRLEN]{};
        if (!inet_ntop(AF_INET6, b, canonical, sizeof(canonical)) || s != canonical) return false;
        bool loopback = std::all_of(b, b + 15, [](unsigned char c) { return c == 0; }) && b[15] == 1;
        return loopback || (b[0] & 0xfe) == 0xfc; // ULA. Link-local needs a scope and is unsupported.
    }
    return false;
}
Router ParseRouter(const std::string& line) {
    std::istringstream parts(line);
    Router r;
    std::string port, extra;
    if (!(parts >> r.identity >> r.endpoint.address >> port) || (parts >> extra) ||
        !Hex64(r.identity) || !LocalNumericIp(r.endpoint.address)) Bad();
    r.endpoint.port = static_cast<uint16_t>(Number(port, 65535));
    if (!r.endpoint.port) Bad();
    return r;
}
std::string Canonical(const Bytes& raw) {
    Fields fields;
    std::string why;
    if (!DecodeDataset(raw, fields, why)) Bad();
    std::string out;
    for (const auto& [type, value] : fields) {
        out.push_back(char(type));
        out.push_back(char(value.size()));
        out.append(reinterpret_cast<const char*>(value.data()), value.size());
    }
    Clear(fields);
    return out;
}
std::string RouterLine(const Router& r) {
    return r.identity + "\n" + r.endpoint.address + "\n" + std::to_string(r.endpoint.port) + "\n";
}
std::vector<std::string> SortedRouterLines(const std::vector<Router>& routers) {
    std::vector<std::string> lines;
    for (const auto& router : routers) lines.push_back(RouterLine(router));
    std::sort(lines.begin(), lines.end());
    return lines;
}
} // namespace

Input ReadInput(std::istream& in) {
    Reader r(in);
    if (r.Line() != "TNT-MAC-MOVE/1") Bad();
    Input x;
    x.mode = r.Field("mode");
    if (x.mode != "inspect" && x.mode != "dispatch" && x.mode != "observe") Bad();
    x.operation = r.Field("operation_id");
    x.review = r.Field("review_revision");
    x.source_generation = Number(r.Field("source_generation"));
    x.target_generation = Number(r.Field("target_generation"));
    x.session = r.Field("session_id");
    x.discovery = r.Field("discovery_revision");
    x.connectivity = r.Field("connectivity_revision");
    for (const auto& value : {x.operation, x.review, x.session, x.discovery, x.connectivity})
        if (!Hex64(value)) Bad();
    std::string source = r.Field("source_dataset"), target = r.Field("target_dataset");
    bool decoded = DecodeHex(source, x.source_dataset) && DecodeHex(target, x.target_dataset);
    WipeString(source);
    WipeString(target);
    if (!decoded) Bad();
    auto count = Number(r.Field("source_count"), 8);
    if (!count) Bad();
    for (unsigned i = 0; i < count; ++i) x.sources.push_back(ParseRouter(r.Field("source_router")));
    x.target = ParseRouter(r.Field("target_router"));
    x.delay = static_cast<unsigned>(Number(r.Field("delay_ms"), 600000));
    if (x.delay < 300000) Bad();
    x.inventory = r.Field("inventory_attestation");
    if (!Hex64(x.inventory)) Bad();
    auto empty = r.Field("controlled_empty");
    auto recovery = r.Field("manual_recovery");
    if (empty != "yes" || recovery != "yes") Bad();
    x.controlled_empty = x.manual_recovery = true;
    x.lifecycle_directory = r.Field("lifecycle_directory");
    x.fenced_at_ms = Number(r.Field("fenced_at_ms"));
    x.expected = r.Field("expected_binding");
    if (x.expected != "-" && !Hex64(x.expected)) Bad();
    r.End();
    if (x.lifecycle_directory.empty() || x.lifecycle_directory.front() != '/' ||
        (x.mode == "dispatch" && x.expected == "-") ||
        (x.mode == "inspect" && x.fenced_at_ms != 0) ||
        (x.mode != "inspect" && !x.fenced_at_ms)) Bad();
    std::set<std::string> identities;
    std::set<std::pair<std::string, uint16_t>> endpoints;
    for (const auto& router : x.sources) {
        if (!identities.insert(router.identity).second ||
            !endpoints.insert({router.endpoint.address, router.endpoint.port}).second) Bad();
    }
    if (!identities.insert(x.target.identity).second ||
        !endpoints.insert({x.target.endpoint.address, x.target.endpoint.port}).second) Bad();
    // Validate both complete datasets before a transport can be constructed.
    DatasetCommitment(x.source_dataset);
    DatasetCommitment(x.target_dataset);
    return x;
}

std::string Sha256(const std::string& input) {
    unsigned char digest[32];
    if (mbedtls_sha256(reinterpret_cast<const unsigned char*>(input.data()), input.size(), digest, 0) != 0)
        throw std::runtime_error("hash_failed");
    std::ostringstream out;
    for (unsigned char c : digest) out << std::hex << std::setw(2) << std::setfill('0') << unsigned(c);
    return out.str();
}
std::string DatasetCommitment(const Bytes& raw) {
    auto canonical = Canonical(raw);
    auto digest = Sha256(canonical);
    WipeString(canonical);
    return digest;
}
std::string RouterBinding(const Router& r) {
    return Sha256("TNT-MAC-ROUTER/1\n" + RouterLine(r));
}
std::string Binding(const Input& x) {
    std::string value = "TNT-MAC-MOVE-BINDING/1\n" + x.operation + "\n" + x.review + "\n" +
        std::to_string(x.source_generation) + "\n" + std::to_string(x.target_generation) + "\n" +
        x.session + "\n" + x.discovery + "\n" + x.connectivity + "\n" + x.inventory + "\n" +
        DatasetCommitment(x.source_dataset) + "\n" + DatasetCommitment(x.target_dataset) + "\n";
    for (const auto& source : SortedRouterLines(x.sources)) value += source;
    value += RouterLine(x.target) + std::to_string(x.delay) + "\n";
    auto digest = Sha256(value);
    WipeString(value);
    return digest;
}
std::string RecoveryBinding(const Input& x) {
    std::string value = "TNT-MAC-MOVE-RECOVERY/1\n" + x.operation + "\n" +
        DatasetCommitment(x.source_dataset) + "\n" + DatasetCommitment(x.target_dataset) + "\n";
    for (const auto& source : SortedRouterLines(x.sources)) value += source;
    value += RouterLine(x.target) + std::to_string(x.delay) + "\n";
    auto digest = Sha256(value);
    WipeString(value);
    return digest;
}
bool Matches(const Bytes& actual, const Bytes& expected) {
    Fields a, e;
    std::string why;
    bool match = DecodeDataset(actual, a, why) && DecodeDataset(expected, e, why) && a == e;
    Clear(a);
    Clear(e);
    return match;
}
bool VerifyJournal(const Input& x, bool dispatch) {
    try {
        Journal journal(x.lifecycle_directory);
        auto body = journal.Read();
        if (body.empty()) return false;
        auto record = DecodeRecord(body);
        std::vector<std::string> bindings;
        for (const auto& source : x.sources) bindings.push_back(RouterBinding(source));
        std::sort(bindings.begin(), bindings.end());
        return record.profile == kProfile && record.operation_id == x.operation &&
            (!dispatch || record.stage == "dispatch_fenced") &&
            record.source_commitment == DatasetCommitment(x.source_dataset) &&
            record.target_commitment == DatasetCommitment(x.target_dataset) &&
            record.target_router_binding == RouterBinding(x.target) && record.router_bindings == bindings &&
            record.fenced_at_ms == x.fenced_at_ms && record.observation_seconds == 30 &&
            record.observe_until_ms - record.fenced_at_ms == static_cast<unsigned long long>(x.delay) + 30000;
    } catch (...) {
        return false;
    }
}

} // namespace tnt::move::mac_worker
