import InAppPurchase
import Testing

@Suite struct PurchaseErrorTests {
  private struct Cause: Error, Sendable, Equatable {
    let reason: String
  }

  @Test func codesWithTheSameRawValueAreEqual() {
    #expect(PurchaseError.Code(rawValue: "unverified") == .unverified)
    #expect(PurchaseError.Code.unverified == .unverified)
  }

  @Test func distinctCodesAreNotEqual() {
    #expect(PurchaseError.Code.unverified != .unknown)
    #expect(PurchaseError.Code.userCancelled != .deliveryFailed)
  }

  @Test(
    arguments: [
      (PurchaseError.Code.deliveryFailed, "deliveryFailed"),
      (.invalidPresentationContext, "invalidPresentationContext"),
      (.networkUnavailable, "networkUnavailable"),
      (.notAvailableInStorefront, "notAvailableInStorefront"),
      (.notEntitled, "notEntitled"),
      (.paymentMethodBindingRequired, "paymentMethodBindingRequired"),
      (.productUnavailable, "productUnavailable"),
      (.purchaseNotAllowed, "purchaseNotAllowed"),
      (.systemError, "systemError"),
      (.unknown, "unknown"),
      (.unsupported, "unsupported"),
      (.unverified, "unverified"),
      (.userCancelled, "userCancelled"),
    ]
  )
  func everyStaticCodeIsNamedAfterItself(code: PurchaseError.Code, name: String) {
    #expect(code.rawValue == name)
  }

  @Test func theStaticCodesAreAllDistinct() {
    let codes: Set<PurchaseError.Code> = [
      .deliveryFailed, .invalidPresentationContext, .networkUnavailable,
      .notAvailableInStorefront, .notEntitled, .paymentMethodBindingRequired,
      .productUnavailable, .purchaseNotAllowed, .systemError, .unknown, .unsupported,
      .unverified, .userCancelled,
    ]

    #expect(codes.count == 13)
  }

  @Test func aClientCanDeclareACodeOfItsOwn() {
    let code = PurchaseError.Code(rawValue: "quotaExceeded")

    #expect(code != .unknown)
    #expect(code == PurchaseError.Code(rawValue: "quotaExceeded"))
  }

  @Test func anErrorHasNoUnderlyingErrorByDefault() {
    let error = PurchaseError(.productUnavailable)

    #expect(error.code == .productUnavailable)
    #expect(error.underlying == nil)
  }

  @Test func anErrorKeepsTheUnderlyingErrorItWasRaisedFrom() throws {
    let error = PurchaseError(.systemError, underlying: Cause(reason: "offline"))

    let cause = try #require(error.underlying as? Cause)
    #expect(cause == Cause(reason: "offline"))
  }

  @Test func anErrorIsCaughtByItsCode() {
    func fail() throws(PurchaseError) {
      throw PurchaseError(.notEntitled)
    }

    do {
      try fail()
      Issue.record("fail() did not throw")
    } catch {
      #expect(error.code == .notEntitled)
    }
  }
}
