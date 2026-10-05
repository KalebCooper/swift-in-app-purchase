import InAppPurchase
import StoreKit
import SwiftUI

struct ProGate: View {
  @State private var isRestoring = false
  @State private var isShowingSubscriptions = false
  @State private var restoreError: PurchaseError?
  @Environment(PurchaseStore.self) private var store

  var body: some View {
    NavigationStack {
      List {
        if store.isEntitled(to: .pro) {
          Section {
            Label("Pro is unlocked", systemImage: "checkmark.seal.fill")
          } footer: {
            Text("A subscriber in a billing grace period stays unlocked.")
          }
        } else {
          Section("Unlock Pro") {
            Button("See Subscriptions") { isShowingSubscriptions = true }
            if let lifetime = store.product(id: "pro.lifetime") {
              PaywallButton(product: lifetime)
            }
          }
        }
        Section {
          Button("Restore Purchases") {
            Task { await restore() }
          }
          .disabled(isRestoring)
        } footer: {
          if let restoreError {
            Text("Restore failed: \(restoreError.code.rawValue)")
          }
        }
      }
      .navigationTitle("Pro")
    }
    .sheet(isPresented: $isShowingSubscriptions) {
      SubscriptionStoreView(productIDs: ["pro.monthly", "pro.yearly"])
    }
    // Close the sheet when the entitlement changes, not in .onInAppPurchaseCompletion. Without
    // that modifier, a purchase made in the sheet reaches the store as a transaction update.
    .onChange(of: store.isEntitled(to: .pro)) { _, isEntitled in
      if isEntitled { isShowingSubscriptions = false }
    }
  }

  private func restore() async {
    isRestoring = true
    defer { isRestoring = false }
    do {
      // Restoring can ask the customer to sign in, so it runs only from this button.
      try await store.restore()
      restoreError = nil
    } catch {
      restoreError = error
    }
  }
}

#Preview("Locked") {
  ProGate()
    .environment(
      PurchaseStore.preview(products: [
        PurchaseProduct(
          displayName: "Pro Lifetime",
          displayPrice: "$29.99",
          id: "pro.lifetime",
          type: .nonConsumable
        )
      ])
    )
}

#Preview("Unlocked") {
  ProGate()
    .environment(PurchaseStore.preview(purchasedProductIDs: ["pro.yearly"]))
}
