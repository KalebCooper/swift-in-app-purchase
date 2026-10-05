import Foundation
import InAppPurchase
import StoreKit
import Testing

@Suite struct StoreKitErrorMappingTests {
  private struct Cause: Error {}

  static let storeKitErrors: [(StoreKitError, PurchaseError.Code)] = [
    (.invalidPresentationContext, .invalidPresentationContext),
    (.networkError(URLError(.notConnectedToInternet)), .networkUnavailable),
    (.notAvailableInStorefront, .notAvailableInStorefront),
    (.notEntitled, .notEntitled),
    (.systemError(Cause()), .systemError),
    (.unknown, .unknown),
    (.unsupported, .unsupported),
    (.userCancelled, .userCancelled),
  ]

  static let purchaseErrors: [(Product.PurchaseError, PurchaseError.Code)] = [
    (.ineligibleForOffer, .unknown),
    (.invalidOfferIdentifier, .unknown),
    (.invalidOfferPrice, .unknown),
    (.invalidOfferSignature, .unknown),
    (.invalidQuantity, .unknown),
    (.missingOfferParameters, .unknown),
    (.paymentMethodBindingConfigurationRequired, .paymentMethodBindingRequired),
    (.productUnavailable, .productUnavailable),
    (.purchaseNotAllowed, .purchaseNotAllowed),
  ]

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

  @Test func anErrorOfAnotherTypeMapsToUnknownWithNoUnderlyingError() {
    let mapped = PurchaseError(converting: Cause())
    #expect(mapped.code == .unknown)
    #expect(mapped.underlying == nil)
  }
}
