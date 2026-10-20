import StoreKit

extension PurchaseError {
  /// Creates the error that `error` reports, keeping `error` as ``underlying``.
  package init(storeKitError error: StoreKitError) {
    let code: Code
    switch error {
    case .invalidPresentationContext: code = .invalidPresentationContext
    case .networkError: code = .networkUnavailable
    case .notAvailableInStorefront: code = .notAvailableInStorefront
    case .notEntitled: code = .notEntitled
    case .systemError: code = .systemError
    case .unknown: code = .unknown
    case .unsupported: code = .unsupported
    case .userCancelled: code = .userCancelled
    @unknown default: code = .unknown
    }
    self.init(code, underlying: error)
  }

  /// Creates the error that `error` reports, keeping `error` as ``underlying``.
  package init(purchaseError error: Product.PurchaseError) {
    let code: Code
    switch error {
    case .paymentMethodBindingConfigurationRequired: code = .paymentMethodBindingRequired
    case .productUnavailable: code = .productUnavailable
    case .purchaseNotAllowed: code = .purchaseNotAllowed
    // Each of these rejects the purchase options the app passed, or an offer the customer cannot
    // take. No code names that, and `underlying` tells them apart.
    case .ineligibleForOffer, .invalidOfferIdentifier, .invalidOfferPrice, .invalidOfferSignature,
      .invalidQuantity, .missingOfferParameters:
      code = .unknown
    @unknown default: code = .unknown
    }
    self.init(code, underlying: error)
  }

  /// Creates the error for `error`, thrown by StoreKit or by a ``Purchaser``.
  ///
  /// StoreKit throws untyped errors. An error of a type named here is kept as ``underlying``, and a
  /// `PurchaseError` passes through unchanged; any other becomes ``Code/unknown`` with no underlying error, because it need not be `Sendable`.
  package init(converting error: any Error) {
    switch error {
    case let error as StoreKitError: self.init(storeKitError: error)
    case let error as Product.PurchaseError: self.init(purchaseError: error)
    case let error as VerificationResult<Transaction>.VerificationError:
      self.init(.unverified, underlying: error)
    case let error as CancellationError: self.init(.unknown, underlying: error)
    case let error as PurchaseError: self = error
    default: self.init(.unknown)
    }
  }
}
