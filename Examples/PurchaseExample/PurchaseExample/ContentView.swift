import InAppPurchase
import SwiftData
import SwiftUI

struct ContentView: View {
  let thankedTransactionIDs: Set<UInt64>

  var body: some View {
    TabView {
      Tab("Tips", systemImage: "heart") {
        TipJarScreen(thankedTransactionIDs: thankedTransactionIDs)
      }
      Tab("Pro", systemImage: "star") {
        ProGate()
      }
      Tab("Coins", systemImage: "circle.circle") {
        CoinsScreen()
      }
    }
  }
}

#Preview {
  ContentView(thankedTransactionIDs: [])
    .environment(PurchaseStore.preview())
    .modelContainer(for: CoinGrant.self, inMemory: true)
}
