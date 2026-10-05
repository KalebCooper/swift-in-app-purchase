/// A failure reported by a ``PurchaseClient``.
///
/// The ``code`` says what went wrong and ``underlying`` keeps the error that caused it. Codes are
/// open: a client with failures of its own declares them in an extension on ``Code``.
public struct PurchaseError: Error, Sendable {
  /// What went wrong.
  public let code: Code
  /// The product the failure concerns, when there is one.
  public let productID: String?
  /// The error the failure was raised from, such as a `StoreKitError`.
  public let underlying: (any Error & Sendable)?

  /// Creates an error with `code` for `productID`, raised from `underlying`.
  public init(
    _ code: Code,
    productID: String? = nil,
    underlying: (any Error & Sendable)? = nil
  ) {
    self.code = code
    self.productID = productID
    self.underlying = underlying
  }

  /// A kind of purchase failure.
  public struct Code: Hashable, RawRepresentable, Sendable {
    /// The store returned a transaction that failed verification.
    public static let failedVerification = Code(rawValue: "failedVerification")
    /// The store has no product with the requested identifier for the current storefront.
    public static let productUnavailable = Code(rawValue: "productUnavailable")
    /// The device or account is not allowed to make payments.
    public static let purchaseNotAllowed = Code(rawValue: "purchaseNotAllowed")
    /// The store failed for a reason no other code describes. See ``PurchaseError/underlying``.
    public static let system = Code(rawValue: "system")

    /// The code's stable name.
    public let rawValue: String

    /// Creates a code named `rawValue`.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }
  }
}
