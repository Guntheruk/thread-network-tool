# Credential access and the optional phone companion

The app needs complete operational datasets for the networks being kept and
moved. Discovery does not reveal them. A Matter pairing code cannot replace a
Thread dataset.

| Route | Current state | Remaining work or evidence |
| --- | --- | --- |
| Copy from eero | Guided copying and local validation implemented | App/version differences; authenticated checks must confirm the selected network. |
| Advanced import | Implemented; datasets stay in memory | The person must already have an authorized complete dataset. |
| Existing Home Assistant | Optional selected-network importer implemented and tested with loopback servers | Actual HA server compatibility remains unverified; HA is not required by the core app. |
| Mac saved credentials | Public API and a local probe exist; access is unproven | Current unentitled Mac probe timed out. Legitimate native/Catalyst/iPad-on-Mac provisioning remains unresolved. |
| Apple saved credentials | iOS request bridge and unsigned builds implemented | Provisioning, actual consent/retrieval, secure desktop transfer, and separate distribution approval. |
| Android saved credentials | Thread SDK bridge and APK build implemented | Actual device retrieval and desktop transfer. |

Home Assistant exposes admin-authorized `thread/list_datasets` and
`thread/get_dataset_tlv` WebSocket reads. An optional importer must require
explicit authorization and network selection, keep credentials/authentication
out of logs/reports, and validate the selected dataset. It must not change
preferred networks, regenerate credentials or enable routers. Not every HA
installation already contains Apple's credentials.

Apple's preferred-credential API presents a consent prompt. The returned network
must match the intended network: preferred does not inherently mean Apple or
HomePod. A framework compiling on Mac does not establish a supported native
macOS provisioning route. See `APPLE-ACCESS.md`.

The owner prefers Mac-only credential retrieval. The Mac project's negative
probe concerns its current unentitled configuration; it does not prove that a
legitimately provisioned native, Catalyst or iPad-app-on-Mac route is impossible.
Require actual signed retrieval evidence before claiming success.

A phone companion is a fallback when credentials are unavailable elsewhere. It
is not required when another authorized source already has them.
Paid developer membership alone does not grant distribution approval for the
Thread entitlement.

The owner questioned installing a phone app solely for credential transfer and
suggested a useful mobile product could become a product wedge. That remains an
open possibility. Continue the desktop workflow without making a companion
mandatory. Mobile diagnostics must reflect observable capabilities; credential
access does not provide a complete device inventory or authority over every
accessory.

## Primary references

- [Home Assistant Thread WebSocket implementation](https://github.com/home-assistant/core/blob/dev/homeassistant/components/thread/websocket_api.py)
- [Home Assistant Thread integration](https://www.home-assistant.io/integrations/thread/)
- [Apple preferred credential retrieval](https://developer.apple.com/documentation/threadnetwork/thclient/retrievepreferredcredentials(_:))
- [Apple development and distribution entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.manage-thread-network-credentials)
