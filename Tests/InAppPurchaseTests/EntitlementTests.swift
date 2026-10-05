import InAppPurchase
import Testing

@Suite struct EntitlementTests {
  @Test func keepsTheProductIDsItWasCreatedWith() {
    let entitlement = Entitlement(["pro.monthly", "pro.yearly"])

    #expect(entitlement.productIDs == ["pro.monthly", "pro.yearly"])
  }

  @Test func entitlementsOverTheSameIDsAreEqualWhateverTheOrder() {
    let first = Entitlement(["pro.monthly", "pro.yearly", "pro.lifetime"])
    let second = Entitlement(["pro.lifetime", "pro.monthly", "pro.yearly"])

    #expect(first == second)
    #expect(first.hashValue == second.hashValue)
  }

  @Test func entitlementsOverDifferentIDsAreNotEqual() {
    #expect(Entitlement(["pro.monthly"]) != Entitlement(["pro.yearly"]))
    #expect(Entitlement(["pro.monthly"]) != Entitlement(["pro.monthly", "pro.yearly"]))
  }

  @Test func anEntitlementOverNoIDsMatchesNoPurchase() {
    let entitlement = Entitlement([])

    #expect(entitlement.productIDs.isEmpty)
    #expect(entitlement.productIDs.isDisjoint(with: ["pro.monthly"]))
  }

  @Test func equalEntitlementsCollapseInASet() {
    let entitlements: Set<Entitlement> = [
      Entitlement(["pro.monthly"]),
      Entitlement(["pro.monthly"]),
      Entitlement(["pro.yearly"]),
    ]

    #expect(entitlements.count == 2)
  }
}
