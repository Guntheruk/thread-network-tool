# Automatic accessory transfer — optional for v1

The owner explicitly removed seamless transfer of existing Eero-network accessories from the first-release requirements on 25 October 2026. Compatible border-router joining remains the product goal. An empty/new network is the simplest supported initial scenario; an absent advertisement or empty observed child table is not proof that no accessories exist.

No small fix for the earlier sleepy sensor is proven. Three explanations remain plausible: it missed the pending update; it received it but failed to apply or reattach; or it reattached briefly and later controller reachability failed. Router readbacks cannot distinguish them. Successful recommissioning established recovery, not that a factory reset was required.

The prototype's ten-minute delay exceeded the observed child timeout, but child timeout is not a measured maximum polling interval. OpenThread discusses a much longer recommended delay for Network Key changes; extending the timer is a candidate mitigation, not an established repair.

Smallest useful follow-up: one lab sleepy device and controllable routers; compare short and extended pending delays while observing child dataset receipt, polls, attachment, and fresh endpoint reads independently. Keep this separate from the first app build. No automatic reset or deletion should be offered as part of a router-joining operation.

Sources:
- https://github.com/orgs/openthread/discussions/8567
- https://openthread.io/reference/group/api-link-link
- https://github.com/openthread/openthread/blob/main/src/cli/README_DATASET.md
