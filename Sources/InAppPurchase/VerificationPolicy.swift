/// What a ``StoreKitPurchaseClient`` does with a transaction whose signature fails verification.
public enum VerificationPolicy: Sendable {
  /// Treat an unverified transaction as valid. Suitable only where the purchase carries no value
  /// worth protecting.
  case acceptUnverified
  /// Reject an unverified transaction with ``PurchaseError/Code/failedVerification`` and exclude it
  /// from entitlements.
  case rejectUnverified
}
