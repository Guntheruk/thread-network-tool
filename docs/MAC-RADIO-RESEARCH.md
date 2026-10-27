# Mac internal Thread radio research

On 25 October 2026, a separate ordinary-user probe on an M3 Pro Mac running
macOS 27.0.1 received real replies from the built-in radio coprocessor. This
experiment is not integrated into the application or distributed with it.

## Access mechanism and evidence

The newer [pythreadradio project](https://github.com/JJTech0130/pythreadradio)
uses the local TSI Skywalk channel and Spinel rather than the entitlement-gated
CoreThreadRadio service. The inspected upstream revision was
`b150bc1ff0e186c14ba3ad5b6378fa235c061d55`. The earlier
[threadctl project](https://github.com/JJTech0130/threadctl) uses a different
private XPC path; its entitlement requirements do not establish the requirements
of the direct coprocessor path.

The test checked that Apple's radio daemon was idle, opened the channel once,
sent only GET requests for firmware version, protocol version and capabilities,
and closed it. It used no root privileges, private entitlements, resets,
configuration writes, scans, attachment or network credentials. System security
settings were unchanged, and the daemon remained idle afterward.

The firmware identified itself as OpenThread revision `g8a19434b8`, built
1 April 2026, with Spinel protocol 4.3. Its capabilities included 2.4 GHz
IEEE 802.15.4 and raw MAC support. This is actual local coprocessor communication,
not a network request to a border router.

## What this does not establish

- No RF frames were captured and no sensor-specific radio diagnosis was made.
- App Sandbox access, distribution compatibility and other Mac models are untested.
- This is an experimental private transport, not an Apple-supported public API.
- Direct radio access does not grant a Matter fabric or make a sensor's data
  readable without the relevant controller authority.
- The ordinary application still uses LAN communication with border routers.

The prototype and its sanitized result remain private local research artifacts.
No upstream code or new dependency was incorporated into this repository, and
no licence or distribution decision follows from this experiment.

## Next controlled verification

First test GET-only snapshots of PHY enabled, channel, raw-stream state,
promiscuous mode and supported channels. Stop if Apple's daemon is active,
values are unsupported or malformed, or the radio is already in use.

The stock upstream sniffer resets and configures the radio and does not restore
its settings, even when reset is skipped. Any future short receive test needs a
separate bounded implementation with validated initial values, acknowledgements,
state restoration and cleanup. Collect only necessary local aggregates, avoid
recording payloads or credentials, and do not treat absent packets as proof that
a sleeping device is disconnected. No such receive test has been run.
