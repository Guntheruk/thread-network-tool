#include <commissioner/commissioner.hpp>
#include <event2/event.h>
#include <library/coap.hpp>
#include <library/dtls.hpp>
#include <library/socket.hpp>
#include <atomic>
#include <csignal>
#include <cstdint>
#include <iostream>
#include <memory>

// Isolated, opt-in DTLS Border Agent stand-in. No radio, discovery or LAN bind.
// The PSK is a public synthetic test value; never accept a credential argument.
namespace {
using namespace ot::commissioner;
namespace coap = ot::commissioner::coap;
constexpr uint8_t kPskc[] = {0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,
                             0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa};
std::atomic<bool> stop{false};
void CountAndReply(coap::Coap &server, const coap::Request &request,
                   unsigned &allowed, unsigned &rejected, bool active) {
  if (request.GetType() != coap::Type::kConfirmable ||
      request.GetCode() != coap::Code::kPost || request.GetPayload().size() > 32) {
    ++rejected;
    coap::Response denied{coap::Type::kAcknowledgment, coap::Code::kMethodNotAllowed};
    server.SendResponse(request, denied).IgnoreError();
    return;
  }
  // Only the application's exact read-field Get TLV is accepted.
  const auto &payload = request.GetPayload();
  const ByteArray activeGet{13,4,14,0,2,3};
  const ByteArray pendingGet{13,3,14,52,51};
  if (payload != (active ? activeGet : pendingGet)) {
    ++rejected;
    coap::Response denied{coap::Type::kAcknowledgment, coap::Code::kBadRequest};
    server.SendResponse(request, denied).IgnoreError();
    return;
  }
  ++allowed;
  coap::Response response{coap::Type::kAcknowledgment, coap::Code::kChanged};
  if (active) {
    // Active Timestamp, Channel, Extended PAN ID, Network Name. Synthetic.
    response.Append(ByteArray{14,8,0,0,0,0,0,0,0,1,
                              0,3,0,0,15,
                              2,8,1,2,3,4,5,6,7,8,
                              3,9,'S','y','n','t','h','e','t','i','c'});
  }
  server.SendResponse(request, response).IgnoreError();
}
}

int main() {
  auto *base = event_base_new();
  if (!base) return 2;
  auto socket = std::make_shared<UdpSocket>(base);
  DtlsSession dtls(base, true, socket);
  coap::Coap server(base, dtls);
  unsigned active = 0, pending = 0, rejected = 0, handshakes = 0, dtls_errors = 0;
  int last_dtls_error = 0;
  coap::Resource ag{"/c/ag", [&](const coap::Request &request) {
    CountAndReply(server, request, active, rejected, true);
  }};
  coap::Resource pg{"/c/pg", [&](const coap::Request &request) {
    CountAndReply(server, request, pending, rejected, false);
  }};
  server.AddResource(ag).IgnoreError();
  server.AddResource(pg).IgnoreError();
  server.SetDefaultHandler([&](const coap::Request &request) {
    ++rejected;
    coap::Response denied{coap::Type::kAcknowledgment, coap::Code::kNotFound};
    server.SendResponse(request, denied).IgnoreError();
  });
  DtlsConfig config;
  config.mPSK.assign(std::begin(kPskc), std::end(kPskc));
  if (dtls.Init(config) != ErrorCode::kNone || socket->Bind("::1", 0) != 0) return 3;
  dtls.Connect([&](DtlsSession &, Error error) {
    if (error == ErrorCode::kNone) ++handshakes;
    else { ++dtls_errors; last_dtls_error = static_cast<int>(error.GetCode()); }
  });
  std::cout << "{\"event\":\"ready\",\"port\":" << socket->GetLocalPort() << "}" << std::endl;
  auto *sigterm = evsignal_new(base, SIGTERM, [](evutil_socket_t, short, void *ctx) {
    *static_cast<std::atomic<bool> *>(ctx) = true;
  }, &stop);
  evsignal_add(sigterm, nullptr);
  while (!stop) event_base_loop(base, EVLOOP_ONCE);
  std::cout << "{\"event\":\"counts\",\"active_get\":" << active
            << ",\"pending_get\":" << pending << ",\"rejected\":" << rejected
            << ",\"handshakes\":" << handshakes
            << ",\"dtls_errors\":" << dtls_errors
            << ",\"last_dtls_error\":" << last_dtls_error << "}" << std::endl;
  event_free(sigterm);
  event_base_free(base);
}
