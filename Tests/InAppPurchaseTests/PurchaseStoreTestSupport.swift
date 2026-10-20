import Foundation
import InAppPurchase
import InAppPurchaseTesting
import StoreKit
import Synchronization

/// Suspends callers until it is opened, and tells a test when a caller is waiting.
final class Gate: Sendable {
  private struct State {
    var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    var isOpen = false
    var waiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state = Mutex(State())

  /// Suspends until a caller is waiting at the gate, or returns at once if one already is.
  func arrival() async {
    await withCheckedContinuation { continuation in
      let isSomeoneWaiting: Bool = state.withLock { state in
        if !state.waiters.isEmpty { return true }
        state.arrivalWaiters.append(continuation)
        return false
      }
      if isSomeoneWaiting { continuation.resume() }
    }
  }

  /// Lets every waiting caller through, now and later.
  func open() {
    let waiters: [CheckedContinuation<Void, Never>] = state.withLock { state in
      state.isOpen = true
      defer { state.waiters.removeAll() }
      return state.waiters
    }
    for waiter in waiters { waiter.resume() }
  }

  /// Suspends until the gate is opened, or returns at once if it already is.
  func wait() async {
    await withCheckedContinuation { continuation in
      let toResume: [CheckedContinuation<Void, Never>] = state.withLock { state in
        if state.isOpen { return [continuation] }
        state.waiters.append(continuation)
        defer { state.arrivalWaiters.removeAll() }
        return state.arrivalWaiters
      }
      for waiter in toResume { waiter.resume() }
    }
  }
}

/// A sleep a test drives: it records each requested duration and sleeps until woken.
final class ControlledSleep: Sendable {
  private struct State {
    var cancelledSleeps = 0
    var nextToken = 0
    var requestWaiters: [CheckedContinuation<Duration, Never>] = []
    var requests = 0
    var sleepers: [Int: CheckedContinuation<Void, any Error>] = [:]
    var unreturnedRequests: [Duration] = []
  }

  private let state = Mutex(State())

  /// How many sleeps in progress were cancelled.
  var cancelledSleepCount: Int { state.withLock { $0.cancelledSleeps } }

  /// How many sleeps were requested.
  var requestCount: Int { state.withLock { $0.requests } }

  /// Returns the next requested duration, waiting for the request if it has not happened yet.
  func nextRequest() async -> Duration {
    await withCheckedContinuation { continuation in
      let immediate: Duration? = state.withLock { state in
        if !state.unreturnedRequests.isEmpty { return state.unreturnedRequests.removeFirst() }
        state.requestWaiters.append(continuation)
        return nil
      }
      if let immediate { continuation.resume(returning: immediate) }
    }
  }

  /// The sleep handed to the store. Suspends until ``wake()`` or cancellation.
  @Sendable func sleep(for duration: Duration) async throws {
    let token: Int = state.withLock { state in
      defer { state.nextToken += 1 }
      return state.nextToken
    }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let requestWaiter: CheckedContinuation<Duration, Never>? = state.withLock { state in
          if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
            return nil
          }
          state.sleepers[token] = continuation
          state.requests += 1
          if state.requestWaiters.isEmpty {
            state.unreturnedRequests.append(duration)
            return nil
          }
          return state.requestWaiters.removeFirst()
        }
        requestWaiter?.resume(returning: duration)
      }
    } onCancel: {
      let sleeper: CheckedContinuation<Void, any Error>? = state.withLock { state in
        let sleeper = state.sleepers.removeValue(forKey: token)
        if sleeper != nil { state.cancelledSleeps += 1 }
        return sleeper
      }
      sleeper?.resume(throwing: CancellationError())
    }
  }

  /// Ends every sleep in progress.
  func wake() {
    let sleepers: [CheckedContinuation<Void, any Error>] = state.withLock { state in
      defer { state.sleepers.removeAll() }
      return Array(state.sleepers.values)
    }
    for sleeper in sleepers { sleeper.resume() }
  }
}

/// A client that answers from a mock but holds chosen `currentEntitlements()` replies at a gate
/// after reading them, so a test can make an older recompute land after a newer one.
final class GatedEntitlementsClient: PurchaseClient {
  private let callCount = Mutex(0)
  private let gates: [Int: Gate]
  let mock: MockPurchaseClient

  /// Gates the reply of every call to `currentEntitlements()` whose number, counting from one, is
  /// in `gatedCalls`.
  init(mock: MockPurchaseClient, gatedCalls: Set<Int>) {
    self.gates = Dictionary(uniqueKeysWithValues: gatedCalls.map { ($0, Gate()) })
    self.mock = mock
  }

  /// The gate holding the reply of the `call`th call, which must be one of the gated calls.
  func gate(forCall call: Int) -> Gate {
    guard let gate = gates[call] else { preconditionFailure("call \(call) is not gated") }
    return gate
  }

  func currentEntitlements() async -> [PurchaseTransaction] {
    let call: Int = callCount.withLock { count in
      count += 1
      return count
    }
    let reply = await mock.currentEntitlements()
    if let gate = gates[call] { await gate.wait() }
    return reply
  }

  func finish(_ transaction: PurchaseTransaction) async { await mock.finish(transaction) }

  func products(for ids: [String]) async throws(PurchaseError) -> [PurchaseProduct] {
    try await mock.products(for: ids)
  }

  func purchase(
    _ product: PurchaseProduct,
    options: Set<Product.PurchaseOption>,
    purchaser: Purchaser?
  ) async throws(PurchaseError) -> PurchaseOutcome {
    try await mock.purchase(product, options: options, purchaser: purchaser)
  }

  func sync() async throws(PurchaseError) { try await mock.sync() }

  func unfinished() async -> [PurchaseTransaction] { await mock.unfinished() }

  func updates() -> AsyncStream<PurchaseTransaction> { mock.updates() }
}

/// A client that answers from a mock but holds every `products(for:)` call at a gate before asking
/// the mock, and counts the calls, so a test can overlap two product loads.
final class GatedProductsClient: PurchaseClient {
  /// Holds every product request until opened.
  let gate = Gate()
  let mock: MockPurchaseClient
  private let productsCalls = Mutex(0)

  init(mock: MockPurchaseClient) {
    self.mock = mock
  }

  /// How many times `products(for:)` was called.
  var productsCallCount: Int { productsCalls.withLock { $0 } }

  func currentEntitlements() async -> [PurchaseTransaction] { await mock.currentEntitlements() }

  func finish(_ transaction: PurchaseTransaction) async { await mock.finish(transaction) }

  func products(for ids: [String]) async throws(PurchaseError) -> [PurchaseProduct] {
    productsCalls.withLock { $0 += 1 }
    await gate.wait()
    // A load that runs in a cancelled caller's task fails here, as StoreKit's own request would.
    if Task.isCancelled { throw PurchaseError(.unknown, underlying: CancellationError()) }
    return try await mock.products(for: ids)
  }

  func purchase(
    _ product: PurchaseProduct,
    options: Set<Product.PurchaseOption>,
    purchaser: Purchaser?
  ) async throws(PurchaseError) -> PurchaseOutcome {
    try await mock.purchase(product, options: options, purchaser: purchaser)
  }

  func sync() async throws(PurchaseError) { try await mock.sync() }

  func unfinished() async -> [PurchaseTransaction] { await mock.unfinished() }

  func updates() -> AsyncStream<PurchaseTransaction> { mock.updates() }
}

/// A client that answers from a mock but runs `whilePurchasing` inside every purchase call before
/// the mock answers, as StoreKit records a purchase whose call then ends cancelled or failed.
final class InterruptedPurchaseClient: PurchaseClient {
  let mock: MockPurchaseClient
  private let whilePurchasing: @Sendable () async -> Void

  init(mock: MockPurchaseClient, whilePurchasing: @escaping @Sendable () async -> Void) {
    self.mock = mock
    self.whilePurchasing = whilePurchasing
  }

  func currentEntitlements() async -> [PurchaseTransaction] { await mock.currentEntitlements() }

  func finish(_ transaction: PurchaseTransaction) async { await mock.finish(transaction) }

  func products(for ids: [String]) async throws(PurchaseError) -> [PurchaseProduct] {
    try await mock.products(for: ids)
  }

  func purchase(
    _ product: PurchaseProduct,
    options: Set<Product.PurchaseOption>,
    purchaser: Purchaser?
  ) async throws(PurchaseError) -> PurchaseOutcome {
    await whilePurchasing()
    return try await mock.purchase(product, options: options, purchaser: purchaser)
  }

  func sync() async throws(PurchaseError) { try await mock.sync() }

  func unfinished() async -> [PurchaseTransaction] { await mock.unfinished() }

  func updates() -> AsyncStream<PurchaseTransaction> { mock.updates() }
}

/// Records what a store's handler is given and how it ran, and can misbehave on request.
@MainActor
final class HandlerRecorder {
  /// What the first invocation does before returning, after any gate, or `nil` to do nothing.
  var actionForFirstInvocation: (@MainActor () async -> Void)?
  /// How many invocations are running right now.
  private(set) var active = 0
  /// The error every invocation throws, or `nil` to return normally.
  var error: (any Error)?
  /// Every event received, in order.
  private(set) var events: [TransactionEvent] = []
  /// What the mock had finished at the moment each invocation began.
  private(set) var finishedAtInvocation: [[PurchaseTransaction]] = []
  /// A gate the first invocation waits at before returning, or `nil` to return at once.
  var gateForFirstInvocation: Gate?
  /// The most invocations that ever ran at the same time.
  private(set) var maxActive = 0
  /// Each event as its invocation begins, for a test to await.
  let starts: AsyncStream<TransactionEvent>

  private let mock: MockPurchaseClient
  private let startsContinuation: AsyncStream<TransactionEvent>.Continuation

  init(mock: MockPurchaseClient) {
    self.mock = mock
    (starts, startsContinuation) = AsyncStream.makeStream(of: TransactionEvent.self)
  }

  func handle(_ event: TransactionEvent) async throws {
    active += 1
    maxActive = max(maxActive, active)
    defer { active -= 1 }
    let isFirst = events.isEmpty
    events.append(event)
    finishedAtInvocation.append(mock.finishedTransactions)
    startsContinuation.yield(event)
    if isFirst, let gateForFirstInvocation { await gateForFirstInvocation.wait() }
    if isFirst, let actionForFirstInvocation { await actionForFirstInvocation() }
    if let error { throw error }
  }
}

extension TransactionEvent {
  /// The transaction of a `.purchased` event, or `nil` for any other case.
  var purchased: PurchaseTransaction? {
    if case .purchased(let transaction) = self { return transaction }
    return nil
  }

  /// The transaction of a `.revoked` event, or `nil` for any other case.
  var revoked: PurchaseTransaction? {
    if case .revoked(let transaction) = self { return transaction }
    return nil
  }
}

struct HandlerFailure: Error {}
