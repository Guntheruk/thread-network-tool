# Live read path

The shared Dart `LiveSession` is used by both the direct native Flutter adapter and the optional localhost development helper. Both call the C++ executable without a shell. No dataset SET, Petition, joiner enablement, reset, deletion or credential-regeneration operation is exposed.

## Native and development transport

The native macOS entry selects `NativeLiveApi`; missing helpers and unsupported platforms select an explicit unavailable adapter. The web preview selects its HTTP adapter only with a valid temporary session fragment. Flutter's browser URL routing is disabled for this single-screen preview so refresh retains that fragment. Neither adapter writes credentials or tokens to browser storage.

The local development server binds IPv4 loopback only, checks the exact Host and optional Origin, and requires a random 256-bit bearer token on every API request. No CORS access is granted. Static content is restricted to the built web directory and is not an API credential source. Session-file publication uses a private staging directory and a non-overwriting hard link after file permissions are restricted. Session tokens and household data belong outside version control.

## Operations

All responses use schema version 1 and mode `live`.

- `GET /api/state`: credential availability and network name, last discovery status/time, advertised routers and their last read result.
- `POST /api/discover {}`: replace discovery observations and invalidate all earlier endpoint handles/read results. Native discovery is bounded; advertisements are provisional. Multiple address/interface observations of a DNS-SD instance are represented as one router, preferring a usable IPv4 endpoint.
- `POST /api/credentials {dataset}`: validate one bounded hex dataset, retain it in process memory, and clear previous read results on successful replacement. Input and native errors are never echoed.
- `POST /api/probe {router_id}`: perform one read against an opaque handle from the last scan. Handles expire after five minutes. No caller-supplied address or port is accepted.

The original credential and probe calls remain an inspection slot. They cannot
feed a network move review. For that review, `POST /api/credentials` requires an
explicit `role` of `source` or `target` alongside `dataset`; `POST /api/probe`
requires that same role alongside `router_id`. The two role credentials remain
separate in memory. A successful role import changes its private generation and
clears that role's reads and any earlier review. Discovery clears all role reads
and the review. A new role read also invalidates the prior review.

`POST /api/network-move/plan` accepts only `target_router_id`, `delay_seconds`
(300–86400), and `empty_source_attestation` with method
`operator_controlled_inventory`, scope `whole_source_network`, and a UTC
`attested_at`. The attestation must be no more than five minutes old and follow
the current credential imports, discovery and source reads. A missing or old
attestation blocks readiness. `GET /api/network-move/plan` returns the current
review or null; evidence changes and expiry clear it. There is no confirm,
dispatch, Petition or SET route.

The server derives source candidates from the authorized source identity,
authenticated source-role reads and provisional advertisements. A matching
advertised Extended PAN ID is a candidate; if that field is absent, a matching
name is a candidate requiring a role-bound read. Advertisements cannot prove
identity or complete inventory. Every observed candidate appears in the preview
and must have a fresh authenticated source-role Active read matching the private
source identity. All source reads must have empty Pending status and the same
Active Timestamp, matching the imported source dataset. The selected target
requires an equivalent fresh target-role read and its Active Timestamp must
match the imported target dataset. Source and target identities must differ.
All checks are made in the session from native evidence; callers cannot supply
readiness booleans or a subset of source routers.

The plan response is local review data (`mode: network_move_review`) with an
opaque `review_id`, `decision` (`ready_for_lab_review` or `needs_evidence`),
blocker codes, all observed candidate router handles/display names/read times,
selected target handle/read time, delay, verification and manual recovery text.
It always says `affected_scope: whole_source_network`,
`unknown_offline_devices: true`, and `inventory_complete: false`. It omits
datasets, keys, PSKc, Extended PAN IDs, channel, Active Timestamp, addresses,
private credential generations and endpoints. `ready_for_lab_review` is not
authorization or evidence that any vendor device supports a network move.

The initial helper permits discovered private IPv4, IPv4 link-local, and ULA IPv6 endpoints. Scoped IPv6 and public/global endpoints remain unavailable in this development adapter; this is a limitation, not evidence that a router is unhealthy.

Router public fields: `id`, `service_name`, `network_name`, `thread_version`, `endpoint_usable`, `probe`. Read fields: `probe_status`, `authenticated`, `identity_match`, `active_status`, `pending_status`, `checked_at`. Addresses, raw TXT records and native payloads are not returned by the helper API. Network names and service names are visible locally; exported reports omit them and contain only counts/statuses.

An overall verified result requires completed read status, successful authentication, matching imported identity, an active read, and a successful pending read (`empty` or `present`). Partial reads cannot produce an overall verified badge. A previous successful observation is time-stamped; it is not continuous health monitoring or proof of migration safety.

## Bounds and secret handling

HTTP request bodies are at most 2 KiB and must complete within five seconds total. Only one engine operation runs per session at a time. Native discovery has an eight-second process alarm; the parent allows twelve seconds. Native probes have a thirty-second alarm and a thirty-five-second parent deadline. Child stdout/stderr are drained and bounded; raw errors are discarded. Child credentials enter stdin only, never argv or environment.

Thread datasets exist in Dart process memory during a session. Dart strings are immutable and cannot provide guaranteed zeroization. No disk persistence, analytics, AI service, vendor account login or Home Assistant dependency is part of this path. Native buffer wiping remains best-effort, not a claim that all library copies are erased.

## Setup guidance versus repair

An existing shared network may require no change. Initial setup can use a preferred network already stored in the mobile keychain: [Apple's border-router configuration guide](https://developer.apple.com/documentation/threadnetwork/configuring-a-border-router) describes adopting existing preferred credentials, and [Eero documents keychain sharing](https://eero.zendesk.com/hc/en-us/articles/360000104706-What-is-Thread). These mechanisms do not establish that two already-configured networks will merge automatically. Future planning should distinguish fresh onboarding, an already-shared network, and repair of an existing split. Do not recommend resetting working hubs merely to recreate a reported setup order.

## Implementation references

- [Apple DNS-SD APIs](https://developer.apple.com/documentation/dnssd)
- [OpenThread Border Agent TXT data](https://openthread.io/reference/group/api-border-agent)
- [Dart HttpServer](https://api.dart.dev/dart-io/HttpServer-class.html) and [Process.start](https://api.dart.dev/dart-io/Process/start.html)
- [Dart macOS temporary directory implementation](https://github.com/dart-lang/sdk/blob/main/runtime/bin/directory_macos.cc)
