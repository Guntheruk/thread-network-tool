# Initial read-only engine contract

Version 1. C ABI:

    const char* tnt_version(void);
    int tnt_inspect_dataset(const char* hex, char* output, size_t output_capacity);

Caller owns buffers. The current parser accepts a maximum of 254 decoded bytes, page 0 and channels 11–26; this is a supported subset, not universal Thread policy validation. Inputs are bounded, NUL-terminated text. Function never throws across ABI. Return 0 success, 1 invalid input, 2 output too small or invalid output buffer. Write bounded JSON only where capacity permits. No secrets in output or error text. Engine exports via a shared library named thread_network_core (platform extension).

Successful JSON keys: schema_version (1), valid (true), network_name, extended_pan_id (16 lowercase hex chars), channel (integer), pan_id (4 hex chars), active_timestamp (16 hex chars), has_network_key (true), has_pskc (true), unknown_tlv_types (integer array). Failed inspection: schema_version (1), valid (false), error_code, message. No raw field bytes in errors.

CLI `thread-network inspect` reads exactly one dataset hex line from stdin and emits the same JSON. No argv secret option. CLI `thread-network probe <numeric-ip> <port>` reads one dataset line from stdin, validates it, extracts PSKc internally, and requests active metadata and pending status via OT Commissioner. Output JSON identifies authenticated state and match/mismatch against imported network identity. Probe is optional at compile time; if absent return explicit unsupported outcome. Probe must not petition or send any SET. POSIX CLI enforces a 30-second process deadline for synchronous upstream calls and exits 124 with a redacted timeout result. Callers should additionally use a bounded subprocess wait. Failed, partial, or mismatched probes exit nonzero.

Build: CMake with core/tests independent of OpenThread; `TNT_WITH_COMMISSIONER=ON` and `TNT_COMMISSIONER_SOURCE` opt into the pinned upstream source. Use isolated build directories, never change upstream checkout.

Flutter uses a platform-independent model. The parser FFI adapter and smoke test remain available. Live discovery and authenticated reads use the bounded native executable through a shared Dart session, exposed directly to native Flutter or through an authenticated localhost development helper. The web preview only claims live results when that helper supplies them; otherwise it remains explicitly synthetic. See LIVE-READ-CONTRACT.md for transport, state and privacy boundaries.

CLI `thread-network discover` requires no stdin. The macOS implementation browses `_meshcop._udp.local`, resolves safe numeric endpoints and emits only allowlisted advertisement metadata. It uses a seven-second collection window, an eight-second process alarm, a 32-service cap and a 64-row cap. Other platforms return explicit unsupported status. Its results are discovery observations, never authenticated identity or endpoint health.
