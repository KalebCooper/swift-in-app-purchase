import Foundation
import InAppPurchase
import StoreKit
import Testing

@Suite struct StoreKitErrorMappingTests {
  private struct Cause: Error {}

  // `invalidPresentationContext` arrived in OS 27, so it joins the list only where it exists.
  static let storeKitErrors: [(StoreKitError, PurchaseError.Code)] = {
    var errors: [(StoreKitError, PurchaseError.Code)] = [
      (.networkError(URLError(.notConnectedToInternet)), .networkUnavailable),
      (.notAvailableInStorefront, .notAvailableInStorefront),
      (.notEntitled, .notEntitled),
      (.systemError(Cause()), .systemError),
      (.unknown, .unknown),
      (.unsupported, .unsupported),
      (.userCancelled, .userCancelled),
    ]
    if #available(iOS 27.0, macOS 27.0, tvOS 27.0, visionOS 27.0, watchOS 27.0, *) {
      errors.append((.invalidPresentationContext, .invalidPresentationContext))
    }
    return errors
  }()

  // `paymentMethodBindingConfigurationRequired` arrived in OS 26.5, so it joins the list only
  // where it exists.
  static let purchaseErrors: [(Product.PurchaseError, PurchaseError.Code)] = {
    var errors: [(Product.PurchaseError, PurchaseError.Code)] = [
      (.ineligibleForOffer, .unknown),
      (.invalidOfferIdentifier, .unknown),
      (.invalidOfferPrice, .unknown),
      (.invalidOfferSignature, .unknown),
      (.invalidQuantity, .unknown),
      (.missingOfferParameters, .unknown),
      (.productUnavailable, .productUnavailable),
      (.purchaseNotAllowed, .purchaseNotAllowed),
    ]
    if #available(iOS 26.5, macOS 26.5, tvOS 26.5, visionOS 26.5, watchOS 26.5, *) {
      errors.append((.paymentMethodBindingConfigurationRequired, .paymentMethodBindingRequired))
    }
    return errors
  }()

  @Test(arguments: storeKitErrors)
  func aStoreKitErrorMapsToItsCodeAndIsKept(error: StoreKitError, code: PurchaseError.Code) {
    let mapped = PurchaseError(storeKitError: error)
    #expect(mapped.code == code)
    #expect(mapped.underlying is StoreKitError)
  }

  @Test(arguments: purchaseErrors)
  func aProductPurchaseErrorMapsToItsCodeAndIsKept(
    error: Product.PurchaseError,
    code: PurchaseError.Code
  ) {
    let mapped = PurchaseError(purchaseError: error)
    #expect(mapped.code == code)
    #expect(mapped.underlying as? Product.PurchaseError == error)
  }

  @Test(arguments: storeKitErrors)
  func anUntypedStoreKitErrorMapsLikeATypedOne(error: StoreKitError, code: PurchaseError.Code) {
    let mapped = PurchaseError(converting: error as any Error)
    #expect(mapped.code == code)
    #expect(mapped.underlying is StoreKitError)
  }

  @Test(arguments: purchaseErrors)
  func anUntypedProductPurchaseErrorMapsLikeATypedOne(
    error: Product.PurchaseError,
    code: PurchaseError.Code
  ) {
    let mapped = PurchaseError(converting: error as any Error)
    #expect(mapped.code == code)
    #expect(mapped.underlying as? Product.PurchaseError == error)
  }

  @Test(
    arguments: [
      VerificationResult<Transaction>.VerificationError.invalidCertificateChain,
      .invalidDeviceVerification,
      .invalidEncoding,
      .invalidSignature,
      .missingRequiredProperties,
      .revokedCertificate,
    ]
  )
  func aVerificationErrorMapsToUnverifiedAndIsKept(
    error: VerificationResult<Transaction>.VerificationError
  ) {
    let mapped = PurchaseError(converting: error)
    #expect(mapped.code == .unverified)
    #expect(mapped.underlying as? VerificationResult<Transaction>.VerificationError == error)
  }

  @Test func cancellationMapsToUnknownAndIsKept() {
    let mapped = PurchaseError(converting: CancellationError())
    #expect(mapped.code == .unknown)
    #expect(mapped.underlying is CancellationError)
  }

  @Test(arguments: [PurchaseError.Code.networkUnavailable, .userCancelled])
  func aPurchaseErrorKeepsItsCode(code: PurchaseError.Code) {
    let mapped = PurchaseError(converting: PurchaseError(code, underlying: Cause()) as any Error)
    #expect(mapped.code == code)
    #expect(mapped.underlying is Cause)
  }

  @Test func anErrorOfAnotherTypeMapsToUnknownWithNoUnderlyingError() {
    let mapped = PurchaseError(converting: Cause())
    #expect(mapped.code == .unknown)
    #expect(mapped.underlying == nil)
  }
}
