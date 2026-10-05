/// A change to a transaction that the app acts on.
///
/// A refund arrives as its own case so it cannot be mistaken for a grant.
public enum TransactionEvent: Sendable {
  /// The customer bought something. Deliver its content.
  case purchased(PurchaseTransaction)
  /// The App Store refunded or revoked a purchase. Take back what it delivered.
  case revoked(PurchaseTransaction)
}
