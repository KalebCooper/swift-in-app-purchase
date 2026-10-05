import InAppPurchase

extension Entitlement {
  /// Pro is unlocked by the one-time purchase or by either subscription.
  static let pro = Entitlement(["pro.lifetime", "pro.monthly", "pro.yearly"])
}
