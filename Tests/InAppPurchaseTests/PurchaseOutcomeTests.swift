import Foundation
import InAppPurchase
import Testing

@Suite struct PurchaseOutcomeTests {
  private let transaction = PurchaseTransaction(
    id: 5,
    productID: "tip.small",
    productType: .consumable,
    purchaseDate: Date(timeIntervalSince1970: 1_800_000_000)
  )

  @Test func aSuccessCarriesItsTransaction() {
    let outcome = PurchaseOutcome.success(transaction)

    guard case .success(let carried) = outcome else {
      Issue.record("expected .success")
      return
    }
    #expect(carried == transaction)
  }

  @Test func pendingAndUserCancelledCarryNothing() {
    let pending = PurchaseOutcome.pending
    let cancelled = PurchaseOutcome.userCancelled

    if case .pending = pending {} else { Issue.record("expected .pending") }
    if case .userCancelled = cancelled {} else { Issue.record("expected .userCancelled") }
  }

  @Test func aPurchaseEventCarriesItsTransaction() {
    let event = TransactionEvent.purchased(transaction)

    guard case .purchased(let carried) = event else {
      Issue.record("expected .purchased")
      return
    }
    #expect(carried == transaction)
  }

  @Test func aRevocationEventIsNotAPurchaseEvent() {
    let event = TransactionEvent.revoked(transaction)

    if case .purchased = event { Issue.record("a revocation matched .purchased") }
    guard case .revoked(let carried) = event else {
      Issue.record("expected .revoked")
      return
    }
    #expect(carried == transaction)
  }
}
