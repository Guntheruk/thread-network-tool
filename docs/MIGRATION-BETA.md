# Migration beta — proposed product scope

Richard asked on 25 October 2026 to account for sleepy devices and to consider
moving devices between networks as beta features. This extends the product plan;
it does not enable mutation commands or authorize a household migration. Automatic
accessory transfer remains optional for the first release.

## Keep the operations distinct

| Operation | Intended result | Important boundary |
| --- | --- | --- |
| Check networks | Discover routers, import authorized credentials and verify individual reads. | The implemented core is read-only; discovery is not a complete accessory inventory. |
| Join a router — beta | Put a compatible border router on a selected existing network. | Vendor-specific behavior can affect attached devices; support must be demonstrated for the actual model and firmware. |
| Move a network — beta | Coordinate a pending Thread dataset update across a source network. | This is a network-wide operation, not an individual accessory selector. |
| Move one accessory — beta | Change one supported accessory's Thread connection while preserving its controller pairings. | Requires an authorized controller/fabric path and supported device commands; router credentials alone are insufficient. |
| Share an accessory with another app | Add another Matter fabric/controller. | This is separate from changing the accessory's Thread network. |

OpenThread describes [active and pending datasets](https://openthread.io/reference/cli/concepts/dataset).
Matter defines administrator-only network commissioning operations in its
[cluster definition](https://github.com/project-chip/connectedhomeip/blob/master/examples/lighting-app/lighting-common/lighting-app.matter).
The [Matter fabric model](https://developers.home.google.com/matter/primer/fabric)
explains why multi-admin sharing is a different operation. Google documents a
[border-router join route](https://developers.home.google.com/apis/android/device/border-router),
which is not proof of an arbitrary individual-accessory transfer route.

## Information the app must show

1. **Exactly what will move.** Selected device/router, authenticated source and
   target identities, and whether the operation affects one device or a network.
   Name matches are not identity proof. Unobserved/offline devices remain unknown.
2. **Device support and authority.** Model/firmware where available, the actual
   supported command, controller permission and authorized target credentials.
   No supported route means unavailable, not a speculative command attempt.
3. **Sleep and readiness.** Thread polling, child timeout, Matter ICD timing,
   last successful read and ordinary model-specific wake instructions where known.
   Unknown timing is shown as unknown. A display turning on is not proof that the
   radio received an update.
4. **An explicit plan.** Propagation delay when applicable, what may be interrupted,
   when verification will run, and whether recovery is demonstrated or manual.
   Never advertise universal rollback or a guaranteed finish time.
5. **Verified outcome.** An accepted command is only one step. Completion requires
   fresh target network evidence and operational Matter reads, followed by a
   meaningful observation period for that device. Source/target router reads alone
   do not prove an accessory recovered.

Readiness also includes source/target reachability, local IPv6 connectivity,
device power where observable, and any update already pending on the network.
Changes in Wi-Fi connection or another controller's concurrent update must stop
an outdated plan from being applied. Thread version alone is not compatibility.

Thread poll period and child timeout are [separate settings](https://openthread.io/reference/group/api-link-link).
Matter ICD idle/active periods are another [device-configured layer](https://project-chip.github.io/connectedhomeip-doc/platforms/ti/matter-users-guide/enabling_icd_on_ti_devices.html).
The earlier kitchen experiment did not observe the sensor receiving its pending
dataset. A longer delay is a candidate mitigation, not a proven repair. See
DEVICE-TRANSFER-ASSESSMENT.md; do not turn a protocol default or a maintainer's
key-change recommendation into a universal sensor timeout.

## Beta behavior and implementation order

Keep experimental operations off by default and label each supported operation
individually. Enabling beta is not approval to change a device. The final review
names the affected device/network and target; the owner confirms that operation.

Use a resumable state machine: inspect → plan → confirm → send → wait → verify →
complete or needs attention. Preserve a redacted operation record across an app
restart. Duplicate clicks must not issue duplicate changes. Cancel before sending
is distinct from stopping observation after a change has already been sent.
After restart, reacquire authorized credentials and read current state before
continuing; never blindly replay a network-changing command. Any persistent
credential storage or encrypted recovery export needs its own explicit design.

First add capability and incomplete-inventory reporting. Then validate one router
and one sleepy accessory on an isolated test network, including missed updates,
lost connectivity, app restart, and failed recovery. Only expose a mutation route
after that device/firmware path passes. Add further device support incrementally.
There is no automatic factory reset, removal from a home, or credential regeneration.

These flows need protocol state and evidence, not AI. AI could later explain a
redacted report, but must not decide authority, readiness or success.
