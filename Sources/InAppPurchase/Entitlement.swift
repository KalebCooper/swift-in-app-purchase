/// A set of products that each unlock the same feature.
///
/// Declare an entitlement once, such as "Pro is the monthly, the yearly, or the lifetime product",
/// and ask whether the customer owns any of them.
///
/// ```swift
/// extension Entitlement {
///   static let pro = Entitlement(["pro.lifetime", "pro.monthly", "pro.yearly"])
/// }
///
/// if store.isEntitled(to: .pro) {
///   ProContent()
/// }
/// ```
public struct Entitlement: Hashable, Sendable {
  /// The identifiers of the products that unlock the feature.
  public let productIDs: Set<String>

  /// Creates an entitlement that any of `productIDs` unlocks.
  public init(_ productIDs: Set<String>) {
    self.productIDs = productIDs
  }
}
