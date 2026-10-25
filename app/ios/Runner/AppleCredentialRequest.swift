import Foundation

/// Main-queue state shared by the iOS channel and its asynchronous callbacks.
/// Finishing a reply never releases the prompt slot; only Apple's callback does.
final class AppleCredentialRequestGate {
  final class Request {
    let id: Int
    let client: AnyObject
    private var reply: (([String: Any]) -> Void)?
    private var deadline: DispatchWorkItem?

    init(id: Int, client: AnyObject, timeout: TimeInterval,
         reply: @escaping ([String: Any]) -> Void) {
      self.id = id
      self.client = client
      self.reply = reply
      let deadline = DispatchWorkItem { [weak self] in
        self?.finish(["status": "timedOut"])
      }
      self.deadline = deadline
      DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: deadline)
    }

    func finish(_ response: [String: Any]) {
      let callback = reply
      reply = nil
      deadline?.cancel()
      deadline = nil
      callback?(response)
    }
  }

  private var pending: Request?

  func start(id: Int, client: AnyObject, timeout: TimeInterval,
             reply: @escaping ([String: Any]) -> Void) -> Request? {
    guard pending == nil else { return nil }
    let request = Request(id: id, client: client, timeout: timeout, reply: reply)
    pending = request
    return request
  }

  func cancel(id: Int) {
    guard let request = pending, request.id == id else { return }
    request.finish(["status": "cancelled"])
  }

  func complete(_ request: Request, response: [String: Any]) {
    guard pending === request else { return }
    pending = nil
    request.finish(response)
  }
}
