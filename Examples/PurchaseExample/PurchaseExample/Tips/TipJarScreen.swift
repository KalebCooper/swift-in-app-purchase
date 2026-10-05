import InAppPurchase
import StoreKit
import SwiftUI

struct TipJarScreen: View {
  let thankedTransactionIDs: Set<UInt64>

  var body: some View {
    NavigationStack {
      // A purchase made in StoreView arrives as a transaction update, which the store delivers to
      // the app's handler. Attaching .onInAppPurchaseCompletion would take it off that path.
      StoreView(ids: ["tip.small", "tip.medium", "tip.large"])
        .safeAreaInset(edge: .top) {
          if !thankedTransactionIDs.isEmpty {
            Text("Thank you for ^[\(thankedTransactionIDs.count) tip](inflect: true)!")
              .font(.headline)
              .frame(maxWidth: .infinity)
              .padding()
              .background(.thinMaterial)
          }
        }
        .navigationTitle("Tips")
    }
  }
}

#Preview {
  TipJarScreen(thankedTransactionIDs: [1])
    .environment(PurchaseStore.preview())
}
