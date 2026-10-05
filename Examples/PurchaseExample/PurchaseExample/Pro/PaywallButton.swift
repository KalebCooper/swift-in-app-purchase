import InAppPurchase
import InAppPurchaseUI
import StoreKit
import SwiftUI

/// Buys one product, for a paywall built from the app's own views.
struct PaywallButton: View {
  @State private var isPurchasing = false
  let product: PurchaseProduct
  @Environment(\.purchase) private var purchase
  @State private var status: String?
  @Environment(PurchaseStore.self) private var store

  var body: some View {
    Button {
      Task { await buy() }
    } label: {
      VStack(alignment: .leading) {
        LabeledContent(product.displayName, value: product.displayPrice)
        if let status {
          Text(status)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
    .disabled(isPurchasing)
  }

  private func buy() async {
    isPurchasing = true
    defer { isPurchasing = false }
    do {
      // The view's purchase action shows the confirmation sheet in this scene.
      switch try await store.purchase(product, using: purchase) {
      case .success:
        // The handler has delivered the content and the store has finished the transaction.
        status = nil
      case .pending:
        status = "Waiting for approval. The purchase arrives when it is approved."
      case .userCancelled:
        status = nil
      }
    } catch {
      status =
        switch error.code {
        case .deliveryFailed:
          "Paid, but delivery failed. It is retried the next time the app opens."
        case .userCancelled:
          nil
        default:
          "Purchase failed: \(error.code.rawValue)"
        }
    }
  }
}

#Preview {
  List {
    PaywallButton(
      product: PurchaseProduct(
        displayName: "100 Coins",
        displayPrice: "$0.99",
        id: "coins.100",
        type: .consumable
      )
    )
  }
  .environment(PurchaseStore.preview())
}
