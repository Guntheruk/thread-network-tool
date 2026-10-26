# Optional Home Assistant access

The desktop app can read Thread credentials already saved in an existing Home
Assistant. Home Assistant is optional: eero copying, Advanced import and the
separately gated Apple route remain available. This route needs no phone
handoff, Home Assistant installation, cloud account or network change.

It does not guarantee that Home Assistant has Apple/eero credentials. Home
Assistant must already have the dataset you want, expose its Thread API and
accept the existing administrator token you choose to supply. An empty store,
missing Thread API, rejected token and insufficient administrator access have
distinct messages. This app does not install integrations or change which
network Home Assistant prefers.

## Consumer flow

1. Choose **Use Home Assistant** in network access setup for the intended role.
2. Enter your chosen server's base address and an existing access token. Use
   HTTPS with a normally trusted certificate whenever possible. The token field
   is masked, and the app clears it when connecting or closing the dialog.
3. For HTTP, explicitly acknowledge that the token and dataset travel without
   encryption. HTTP is accepted only on loopback, RFC1918 private IPv4 or IPv6
   unique-local addresses. Public, link-local and multicast HTTP destinations
   are refused. Use only a trusted private network; private addressing alone
   does not authenticate the server.
4. Click **Connect and list networks**. No dataset is retrieved at this stage.
   Choose a saved network yourself; no preferred or first network is selected.
5. Click **Import selected network**. The app requests that exact dataset ID,
   matches the returned name, extended PAN ID, PAN ID and channel to the selected
   list metadata, then invokes the existing complete dataset validator and the
   caller's existing source/target access callback. Import does not verify that
   a router uses those credentials; the separate authenticated check does that.

The supplied URL must be a base `http://` or `https://` address, with an optional
port. URLs containing credentials, queries, fragments or extra paths are
refused. Reverse-proxy path prefixes and browser/web access are unsupported in
this first route; web builds show the explicit desktop-app fallback.

## Transport and privacy boundaries

The only WebSocket commands sent are authentication, `thread/list_datasets` and
`thread/get_dataset_tlv`. There is no write, discovery subscription, preferred
network change, retry or automatic dataset selection. Authentication is sent only
after the expected `auth_required` message, over the same fixed-origin socket.
Redirects are disabled before the HTTP upgrade; no token or dataset can follow
a redirect to another server. HTTPS retains Dart/platform certificate and
hostname validation, without a permissive certificate callback.

The HTTP destination is resolved once per connection. Every returned address
must pass the private-address policy, and the socket connects to the actual
validated numeric address. It never performs a second hostname lookup after
approving a private address, preventing HTTP DNS rebinding to a public address.
Connections bypass proxies so the checked destination is the actual destination.
HTTPS also uses the fixed numeric socket while retaining original-host TLS
verification.

Each list operation has one 15-second total deadline across DNS, connection,
authentication and listing; fetching has its own 15-second deadline. Cancellation
closes the socket/client and invalidates late responses before import. A busy
operation cannot overlap another. Leaving the route or closing the dialog clears
the token and listed networks and closes the connection. No credentials are
stored in preferences/files, logs, reports, command-line arguments or URLs.
Immutable language/runtime strings cannot promise physical memory zeroization;
this is session-only use, not a secure-memory vault.

A socket guard bounds individual WebSocket frames and complete fragmented
messages at 32 KiB before the WebSocket library aggregates them, with compression
disabled,
JSON nesting is capped at 16, lists at 64 networks, tokens at 4096 characters,
network names at 16 UTF-8 bytes and dataset hex at 254 decoded bytes. Only fixed
error enums cross the provider boundary; raw HTTP/server/TLS error messages,
server error text, tokens and datasets do not appear in failure text.

## Evidence and limits

Verified 26 October 2026 against the Home Assistant project's current read-only
Thread WebSocket implementation and its documented authentication protocol.
Both dataset commands require administrator permission. The dataset store and
its parser confirm the metadata uses plain hex identifiers and UTF-8 names.

Local tests use synthetic loopback WebSocket servers and datasets, never a
household server or token. Coverage includes the chosen nonpreferred ID reaching
the supplied role callback, explicit actions, empty/admin/missing states,
malformed/bounded data, name/XPAN/PAN/channel mismatches, deadline/cancellation,
redirect refusal, DNS address pinning, mixed private/public DNS refusal,
untrusted TLS rejection and fixed error redaction. Narrow enlarged-text layouts
and masked/cleared token behavior are checked separately from transport.

No live Home Assistant compatibility or packaged Mac runtime is established by
these tests. Existing Home Assistant versions and account policies may differ;
unsupported responses fail closed. Run locally from `app/`:

```
flutter test test/home_assistant_credentials_test.dart test/home_assistant_setup_test.dart
```

Local verification used the repository's pinned Flutter 3.47.8 / Dart 3.13.7
toolchain. The message guard does not depend on Dart's newer per-frame
`maxPayloadLength` API; it enforces both frame and fragmented-message limits.

Primary references:

- [Home Assistant Thread read-only WebSocket commands](https://github.com/home-assistant/core/blob/dev/homeassistant/components/thread/websocket_api.py)
- [Home Assistant WebSocket authentication and result protocol](https://contributors.home-assistant.io/core/internals/websocket-api/)
- [Home Assistant Thread dataset metadata](https://github.com/home-assistant/core/blob/dev/homeassistant/components/thread/dataset_store.py)
- [Home Assistant library TLV parser](https://github.com/home-assistant-libs/python-otbr-api/blob/main/python_otbr_api/tlv_parser.py)
