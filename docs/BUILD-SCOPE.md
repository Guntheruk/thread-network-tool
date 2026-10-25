# Build scope — 25 October 2026

Owner approved building the four-platform Flutter/C++ plan. Latest correction: automatic transfer of devices from the old Eero network is not a requirement for the first release. Investigate a simple fix, but do not make seamless end-device migration a gate for the whole product.

First product target: discover networks, import authorized credentials, inspect live state, plan joining compatible border routers to a selected existing network, and make limitations clear. An empty/new source network is a useful initial scenario. Thread disabled in a vendor app must be detected/explained, not silently enabled or represented as discoverable.

This initial build delivers a portable read-only engine, native CLI, synthetic-fixture Flutter flow, and meaningful tests. Migration stays disabled pending explicit lab validation. No existing home settings are changed as part of this build.

Architecture: Flutter/Dart shared UI; a small C ABI around a C++ engine; Swift/Kotlin integrations later for protected credential APIs. Mac protocol baseline is OpenThread Commissioner commit 448f807e3246c46e5b82e4cdc12a9b0fb2a646ae. Windows native networking and iOS linking require separate validation. Google Home Android/iOS integrations are planned; no actual Nest model is verified.

Acceptance for this build:
1. Dataset validation rejects malformed, duplicate, incomplete, and oversized input without echoing secrets.
2. Native metadata output has no key, PSKc, or raw dataset; uncertainty is explicit.
3. Optional OT-backed probe connects and performs GET operations only. No Petition/SET is reachable.
4. Flutter screens cover discovery, credential import, assessment, and a disabled migration review; demo data is visibly labelled.
5. Build/test evidence distinguishes Mac native core, Flutter web preview, native desktop packaging, and other-platform gaps.

Use a separate repo; do not modify Recursive Systems. The owner requested the private GitHub repository `Guntheruk/thread-network-tool` for PR review. Release licensing and vendor entitlements remain decisions before public distribution.

Later owner direction: use Recursive Systems' visual style for a simpler interface,
document Google Home integration, and plan separate beta flows for router/network
and individual-device moves. These are described in INTERFACE.md, GOOGLE-HOME.md
and MIGRATION-BETA.md. Joining remains disabled in this implementation. The owner
also requested a GitHub repository and PR review workflow; the initial repository
is private while release licensing and compatibility remain unresolved.
