# Candidate pilot gates

This is a proposed gate list, not evidence that a pilot is ready or has run. The
default consumer app has joining disabled; the explicit Mac alpha includes a
separate guarded join worker. Signed-parent loopback tests pass, but controlled
retail acceptance and distribution are unfinished (see `MAC-ALPHA.md`).
Do not invite participants until the required candidate gates below
have evidence for the exact build and supported workflow.

## Gates before inviting participants

| Gate | Countable acceptance evidence | Current status |
| --- | --- | --- |
| Local, no-account operation | On a clean test setup, launch and complete the supported local workflow with no sign-in, Home Assistant, AI service or network connection to a collection service. Record the exact build and observed result. | Local app exists; full candidate workflow is not complete. |
| Mac distribution and installation | Produce the exact candidate with Developer ID signing and notarization; install and launch it on at least one clean Mac account/device without development tools. Record OS, architecture, app version and install outcome. | Local ad hoc package only; Developer ID signing, notarization and clean-Mac installation are unverified. |
| Supported combination and outcome | Name the exact source, target/router model and firmware, OS, app build and operation. In a controlled setup, verify each required step and the final outcome; do not infer support from discovery or credentials alone. | One direct single-router read is verified. Isolated application lost-result recovery passed at `a2949a68`; no retail-vendor join or recovery combination is verified. |
| Recovery | For each proposed supported combination, exercise the documented interrupted, rejected, timeout and mismatch paths in a controlled setup. Record the trigger, user-visible state and verified recovery result. Do not retry an uncertain mutation. | Isolated actual-app lost-result recovery passed at `a2949a68`. Its key-change attempt exited unsuccessfully with cause and physical convergence unknown. Default consumer joining remains disabled; recovery for a retail combination and exact release candidate remains unverified. |
| Optional report preview | If a report is offered, show its exact allowlisted fields locally before any deliberate share/copy action. Record the preview for synthetic data and confirm it excludes credentials, household labels, endpoints, device identities and persistent installation IDs. Report sharing must be optional and separate from email or research signup. | A local redacted report preview exists; the broader candidate report gate is not yet recorded. No collection service is authorized by this document. |

Do not describe a vendor single-router read as whole-source network assessment.
The latter would require enumerating relevant border routers, establishing the
source/target decision, and handling existing accessories with a separately
verified migration and recovery path.

## Pilot size and interpretation

After the gates pass, invite **10–20 deliberately varied participants** as a
practical debugging pilot. Record the count invited, count who start, count who
complete each supported workflow, failure stage/error category, recovery needed,
and exact tested configuration. Include variation in relevant router models,
firmware, OS and device availability where feasible; keep per-combination claims
tied to actual evidence.

This small, self-selected pilot is for finding defects and workflow gaps. It is
not a statistically representative sample and cannot establish market size,
general compatibility, demand, or willingness to pay. Keep research questions
and any optional report sharing separate from the core local workflow.

## Source basis

The release gates follow `docs/RELEASE-PLAN.md`; current platform and packaged
Mac evidence is in `PROGRESS.md`, `docs/MACOS-BUILD.md`,
`docs/ANDROID-BUILD.md` and `docs/GOOGLE-HOME.md`. The 25 October supplied
strategy report recommends a varied 10–20 person debugging pilot and a clean-Mac
distribution check; it explicitly treats these as practical recommendations,
not validation of general demand. Current statuses above reflect the project
records, not new test results.
