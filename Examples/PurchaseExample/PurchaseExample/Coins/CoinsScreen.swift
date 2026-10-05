import InAppPurchase
import StoreKit
import SwiftData
import SwiftUI

struct CoinsScreen: View {
  @Query private var grants: [CoinGrant]
  @Environment(PurchaseStore.self) private var store

  var body: some View {
    NavigationStack {
      List {
        Section {
          LabeledContent("Balance") {
            Text(grants.reduce(0) { $0 + $1.coins }, format: .number)
          }
        }
        Section("Buy Coins") {
          ForEach(CoinDelivery.coinsPerPack.keys.sorted(), id: \.self) { id in
            if let product = store.product(id: id) {
              PaywallButton(product: product)
            }
          }
        }
      }
      .navigationTitle("Coins")
    }
  }
}

#Preview {
  CoinsScreen()
    .environment(
      PurchaseStore.preview(products: [
        PurchaseProduct(
          displayName: "100 Coins",
          displayPrice: "$0.99",
          id: "coins.100",
          type: .consumable
        ),
        PurchaseProduct(
          displayName: "500 Coins",
          displayPrice: "$3.99",
          id: "coins.500",
          type: .consumable
        ),
      ])
    )
    .modelContainer(for: CoinGrant.self, inMemory: true)
}
