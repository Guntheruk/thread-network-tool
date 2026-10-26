#include <stdio.h>
#include <openthread/platform/radio.h>
#include "instance/instance.hpp"
#include "thread/key_manager.hpp"
#include "thread/mle.hpp"
#include "mac/sub_mac.hpp"
#include "test_platform.h"
#include "test_util.hpp"
static uint32_t sRadioCounter;
static unsigned sKeyInstalls;
static uint32_t sHostCounterAtKeyInstall;
static uint32_t sSubMacCounterAtKeyInstall;
static otRadioFrame sTxFrame;
static uint8_t sPsdu[OT_RADIO_FRAME_MAX_SIZE];
extern "C" otRadioCaps otPlatRadioGetCaps(otInstance *) { return OT_RADIO_CAPS_TRANSMIT_SEC; }
extern "C" otRadioFrame *otPlatRadioGetTransmitBuffer(otInstance *)
{
    sTxFrame.mPsdu = sPsdu;
    return &sTxFrame;
}
extern "C" void otPlatRadioSetMacKey(otInstance *aInstance, uint8_t, uint8_t,
                                     const otMacKeyMaterial *, const otMacKeyMaterial *,
                                     const otMacKeyMaterial *, otRadioKeyType)
{
    // Match the pinned simulation platform's key-install behavior (radio.c:1142-1143).
    sRadioCounter = 0;
    ++sKeyInstalls;
    auto &instance = *static_cast<ot::Instance *>(aInstance);
    sHostCounterAtKeyInstall = instance.Get<ot::KeyManager>().Get154MacFrameCounter();
    sSubMacCounterAtKeyInstall = instance.Get<ot::Mac::SubMac>().GetFrameCounter();
}
extern "C" void otPlatRadioSetMacFrameCounter(otInstance *, uint32_t aCounter) { sRadioCounter = aCounter; }
extern "C" void otPlatRadioSetMacFrameCounterIfLarger(otInstance *, uint32_t aCounter)
{
    if (aCounter > sRadioCounter) sRadioCounter = aCounter;
}
int main(void)
{
    printf("PLATFORM_KEY_REFERENCES_ENABLE=%d\n", OPENTHREAD_CONFIG_PLATFORM_KEY_REFERENCES_ENABLE);
    printf("MULTI_RADIO=%d TREL_ENABLE=%d\n", OPENTHREAD_CONFIG_MULTI_RADIO, OPENTHREAD_CONFIG_RADIO_LINK_TREL_ENABLE);
    VerifyOrQuit(!OPENTHREAD_CONFIG_MULTI_RADIO && !OPENTHREAD_CONFIG_RADIO_LINK_TREL_ENABLE);
    auto *instance = testInitInstance();
    VerifyOrQuit(instance != nullptr);
    auto &manager = instance->Get<ot::KeyManager>();
    ot::NetworkKey oldKey;
    manager.GetNetworkKey(oldKey);
    ot::NetworkKey newKey = oldKey;
    newKey.m8[0] ^= 0x80;
    VerifyOrQuit(manager.GetCurrentKeySequence() == 0);
    manager.SetAllMacFrameCounters(12345, false);
    VerifyOrQuit(sRadioCounter == 12345);
    const unsigned installsBefore = sKeyInstalls;
    manager.SetNetworkKey(newKey);
    printf("key_installs_delta=%u host_at_install=%u submac_at_install=%u host_after=%u radio_after=%u seq=%u\n",
           sKeyInstalls-installsBefore, sHostCounterAtKeyInstall, sSubMacCounterAtKeyInstall,
           manager.Get154MacFrameCounter(), sRadioCounter, manager.GetCurrentKeySequence());
    fflush(stdout);
    VerifyOrQuit(sKeyInstalls == installsBefore + 1, "new key must reach transmit-security radio");
    VerifyOrQuit(manager.GetCurrentKeySequence() == 0, "test exercises unchanged key sequence");
    VerifyOrQuit(manager.GetMaximumMacFrameCounter() == manager.Get154MacFrameCounter(),
                 "single-radio MLE advertised maximum equals 154 counter");
    VerifyOrQuit(manager.Get154MacFrameCounter() == sRadioCounter,
                 "host advertises a counter different from the radio's next secured TX");
    VerifyOrQuit(instance->Get<ot::Mac::SubMac>().GetFrameCounter() == sRadioCounter,
                 "SubMac counter must agree with radio");
    VerifyOrQuit(sHostCounterAtKeyInstall == 0 && sSubMacCounterAtKeyInstall == 0,
                 "own counters must reset before key installation");
    manager.SetAllMacFrameCounters(6789, false);
    const unsigned installsBeforeSameKey = sKeyInstalls;
    manager.SetNetworkKey(newKey);
    VerifyOrQuit(sKeyInstalls == installsBeforeSameKey, "unchanged key must not reinstall radio keys");
    VerifyOrQuit(manager.Get154MacFrameCounter() == 6789 && sRadioCounter == 6789 &&
                 instance->Get<ot::Mac::SubMac>().GetFrameCounter() == 6789,
                 "unchanged key must preserve own counters and replay protection");
    puts("PASS unchanged-key no-op preserves nonzero counters");
    testFreeInstance(instance);
    puts("PASS network-key replacement keeps host/SubMac/radio counters synchronized");
    return 0;
}
