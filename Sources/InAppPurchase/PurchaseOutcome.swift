/// How a purchase that did not throw ended.
public enum PurchaseOutcome: Hashable, Sendable {
  /// The customer dismissed the purchase sheet.
  case cancelled
  /// The purchase awaits approval, such as an Ask to Buy request. It arrives later through
  /// ``PurchaseClient/transactionUpdates()``.
  case pending
  /// The purchase completed and verified. Deliver its content, then finish it.
  case purchased(PurchaseTransaction)
}
