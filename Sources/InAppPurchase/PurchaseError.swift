/// A failure reported by the store.
///
/// The ``code`` says what went wrong and ``underlying`` keeps the error that caused it. Codes are
/// open: a failure with no code here is declared in an extension on ``Code``.
public struct PurchaseError: Error, Sendable {
  /// What went wrong.
  public var code: Code
  /// The error the failure was raised from, such as a `StoreKitError`.
  public var underlying: (any Error & Sendable)?

  /// Creates an error with `code`, raised from `underlying`.
  public init(_ code: Code, underlying: (any Error & Sendable)? = nil) {
    self.code = code
    self.underlying = underlying
  }

  /// A kind of purchase failure.
  public struct Code: Hashable, RawRepresentable, Sendable {
    /// The app's handler threw, so the transaction is not finished and is delivered again.
    public static let deliveryFailed = Code(rawValue: "deliveryFailed")
    /// There is no scene to present the purchase sheet from.
    public static let invalidPresentationContext = Code(rawValue: "invalidPresentationContext")
    /// The store could not be reached.
    public static let networkUnavailable = Code(rawValue: "networkUnavailable")
    /// The product is not sold in the customer's storefront.
    public static let notAvailableInStorefront = Code(rawValue: "notAvailableInStorefront")
    /// The customer does not own the product.
    public static let notEntitled = Code(rawValue: "notEntitled")
    /// The customer must add a payment method before buying.
    public static let paymentMethodBindingRequired = Code(
      rawValue: "paymentMethodBindingRequired")
    /// The store has no product with the requested identifier.
    public static let productUnavailable = Code(rawValue: "productUnavailable")
    /// The device or account is not allowed to make payments.
    public static let purchaseNotAllowed = Code(rawValue: "purchaseNotAllowed")
    /// The store failed in a way the app cannot act on. See ``PurchaseError/underlying``.
    public static let systemError = Code(rawValue: "systemError")
    /// The failure matches no other code. See ``PurchaseError/underlying``.
    public static let unknown = Code(rawValue: "unknown")
    /// The operation is not supported on this platform or by this store.
    public static let unsupported = Code(rawValue: "unsupported")
    /// The store returned a transaction that failed verification.
    public static let unverified = Code(rawValue: "unverified")
    /// The customer cancelled. Only restoring throws this; a purchase returns
    /// ``PurchaseOutcome/userCancelled``.
    public static let userCancelled = Code(rawValue: "userCancelled")

    /// The code's stable name.
    public let rawValue: String

    /// Creates a code named `rawValue`.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }
  }
}
