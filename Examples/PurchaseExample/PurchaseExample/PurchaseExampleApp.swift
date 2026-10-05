import InAppPurchase
import InAppPurchaseUI
import SwiftData
import SwiftUI

@main
struct PurchaseExampleApp: App {
  private let container: ModelContainer
  @State private var store = PurchaseStore(productIDs: [
    "coins.100", "coins.500", "pro.lifetime", "pro.monthly", "pro.yearly", "tip.large",
    "tip.medium", "tip.small",
  ])
  @State private var thankedTransactionIDs: Set<UInt64> = []

  init() {
    do {
      container = try ModelContainer(for: CoinGrant.self)
    } catch {
      fatalError("Could not open the coin store: \(error)")
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView(thankedTransactionIDs: thankedTransactionIDs)
        .environment(store)
        .refreshingPurchases(store)
        .task {
          // One handler delivers every product, one transaction at a time. The store finishes
          // each transaction only after the handler returns.
          await store.start { event in
            switch event {
            case .purchased(let transaction) where transaction.productID.hasPrefix("tip."):
              // A transaction can arrive more than once, so key the thank-you on its id.
              thankedTransactionIDs.insert(transaction.id)
            case .purchased(let transaction) where transaction.productID.hasPrefix("coins."),
              .revoked(let transaction) where transaction.productID.hasPrefix("coins."):
              try CoinDelivery.deliver(event, in: container.mainContext)
            default:
              // Owning Pro is the content, so there is nothing to deliver.
              break
            }
          }
        }
    }
    .modelContainer(container)
  }
}
