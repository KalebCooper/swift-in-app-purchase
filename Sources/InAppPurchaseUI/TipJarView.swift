import InAppPurchase
import SwiftUI

/// A tip jar that offers consumable products from a ``/InAppPurchase/PurchaseStore`` and renders
/// each one through an app-supplied view.
public struct TipJarView<Tip: View>: View {
  private let copy: TipJarCopy
  private let productIDs: [String]
  private let store: PurchaseStore
  private let tip: (PurchaseProduct) -> Tip

  /// Creates a tip jar that offers the products with `productIDs`, in that order, and renders each
  /// with `tip`.
  public init(
    copy: TipJarCopy,
    productIDs: [String],
    store: PurchaseStore,
    @ViewBuilder tip: @escaping (PurchaseProduct) -> Tip
  ) {
    self.copy = copy
    self.productIDs = productIDs
    self.store = store
    self.tip = tip
  }

  /// The tip jar's content.
  public var body: some View {
    EmptyView()
  }
}
