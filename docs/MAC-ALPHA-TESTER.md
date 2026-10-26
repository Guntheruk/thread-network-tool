# Mac Eero alpha: local tester quickstart

This is a local development build, not a released or broadly supported product. The packaged join has been tested with synthetic peers, not a retail Eero move. The local package is ad hoc signed, not notarized; clean-Mac installation and full-app execution on Intel hardware have not been verified. Do not invite pilot participants until the [pilot gates](PILOT.md) are met. See the [acceptance record](MAC-ALPHA-ACCEPTANCE.md) for the exact package and evidence.

**Do not use a working household as a test network.** A real join needs a separately authorized, controlled setup. The action changes the entire source Thread network, not just the Eero you select. It can interrupt that network, does not move accessories, and has no automatic rollback. The source must have no accessories; independently inventory it and all source Eeros. A missing advertisement or an empty list in the app does not prove the network is empty or that every Eero is present.

## Prepare

- Use the exact local alpha package named in the acceptance record. The ordinary package is read-only; only the explicitly built Mac alpha includes the join worker. Launch it on the build Mac. If macOS blocks the app, stop and report the message; trusted signing, notarization and installation are separate outstanding work.
- Identify the **network to join** (the one you keep) and the **Eero network to move** (the empty source). You need the complete Active operational dataset for each. Treat both datasets as passwords: do not put them in messages, screenshots, reports or command lines.
- For the Eero source, choose the guided eero route and copy its Active operational dataset from the eero app. The guide does not prescribe a fixed vendor menu path. For the network to join, use an existing authorized Home Assistant import or Advanced entry. Home Assistant is optional; the Mac app cannot retrieve Apple credentials. Do not regenerate credentials to make a test possible.

## Review a controlled setup

1. Open **Find routers**, then **Join Eeros to a network**. Discovery is only an advertisement, not proof of identity or a complete inventory.
2. Set up the **network to join**, select its router and choose **Check network to join**. Set up the **Eero network to move**, then **Check Eero** for each source router. Resolve failed, missing, changed or mismatched endpoints before proceeding. Link-local IPv6 addresses with a zone identifier are unsupported.
3. Confirm from your independent inventory that the source is your Eero network, every source Eero is represented and the source has no accessories. Read the whole-source review. Only proceed through the final confirmation if the controlled operation has been explicitly authorized and the details remain correct.
4. Keep the app in the foreground while it waits for propagation and performs its bounded read-only checks. A configuration-verified result means the original source endpoints repeatedly authenticated with the target settings and the target stayed unchanged; it does not prove accessory connectivity, radio coverage or a working Thread data path.

## If interrupted or uncertain

Stop and preserve the result. **Do not repeat the join**, reset devices, regenerate credentials or assume a timeout means nothing happened. A response can be lost after a change was sent, and rollback is not guaranteed. If the app is closed, backgrounded or the screen is left, automatic checks stop; after reopening, recovery checks are manual. Re-enter the same two credentials and use the original endpoint bindings. Changed or missing endpoints need attention rather than substitution. If the app cannot establish the result, leave the operation unresolved and seek help before any further change. See [alpha recovery details](MAC-ALPHA.md).

## Share a useful, safe report

The app offers a **Redacted report** preview and optional copy. Review it before sharing. It is an assessment report, not proof of a completed move. Share the exact app build, macOS version and architecture, the stage reached, the visible result category and a redacted report if useful. Do not share datasets, keys, tokens, network or household names, addresses, device identities, screenshots containing them, raw logs or the app's private recovery files. Report sharing is optional and does not enroll you in telemetry or research.
