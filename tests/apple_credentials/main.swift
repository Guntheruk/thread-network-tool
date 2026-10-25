import Foundation

func require(_ value: @autoclosure () -> Bool, _ message: String) {
  precondition(value(), message)
}
let gate = AppleCredentialRequestGate()
var replies: [[String: Any]] = []
let client = NSObject()
let first = gate.start(id: 1, client: client, timeout: 10) { replies.append($0) }!
require(gate.start(id: 2, client: client, timeout: 10, reply: { _ in }) == nil,
        "Concurrent consent must be blocked")
gate.cancel(id: 2)
require(replies.isEmpty, "Another request cannot cancel this request")
gate.cancel(id: 1)
require(replies.count == 1 && replies[0]["status"] as? String == "cancelled", "Cancellation replies once")
require(gate.start(id: 2, client: client, timeout: 10, reply: { _ in }) == nil,
        "Cancelled OS prompt must keep its slot until its callback")
gate.complete(first, response: ["status": "available", "dataset": Data([1, 2])])
require(replies.count == 1, "Late success after cancellation must not deliver credentials")
let second = gate.start(id: 2, client: client, timeout: 0.01) { replies.append($0) }!
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
require(replies.count == 2 && replies[1]["status"] as? String == "timedOut", "Native deadline replies once")
require(gate.start(id: 3, client: client, timeout: 10, reply: { _ in }) == nil,
        "Timed out OS prompt must keep its slot")
gate.complete(second, response: ["status": "available", "dataset": Data([3, 4])])
require(replies.count == 2, "Late success after timeout must be discarded")
let third = gate.start(id: 3, client: client, timeout: 10) { replies.append($0) }!
gate.complete(first, response: ["status": "failure"])
require(gate.start(id: 4, client: client, timeout: 10, reply: { _ in }) == nil,
        "Stale callback must not release a newer prompt")
gate.complete(third, response: ["status": "available", "dataset": Data([5, 6])])
gate.complete(third, response: ["status": "failure"])
require(replies.count == 3 && replies[2]["dataset"] as? Data == Data([5, 6]), "Valid completion replies only once")
print("Apple credential request gate: 11 checks passed")
