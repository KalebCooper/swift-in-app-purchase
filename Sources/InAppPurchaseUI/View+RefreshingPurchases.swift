import InAppPurchase
import SwiftUI

extension View {
  /// Calls ``/InAppPurchase/PurchaseStore/refresh()`` whenever the scene becomes active, so a
  /// transaction left unfinished, an entitlement that changed, or a failed product load is picked
  /// up when the customer returns to the app.
  ///
  /// The first appearance does not refresh, because `start()` already did that work. A refresh
  /// that is under way runs to completion even if the scene leaves the active phase again, so an
  /// unfinished transaction is never abandoned partway through delivery. Attach it once, near the
  /// root of the scene.
  ///
  /// ```swift
  /// ContentView()
  ///   .refreshingPurchases(store)
  /// ```
  public func refreshingPurchases(_ store: PurchaseStore) -> some View {
    modifier(RefreshingPurchases(store: store))
  }
}

private struct RefreshingPurchases: ViewModifier {
  @Environment(\.scenePhase) private var scenePhase
  let store: PurchaseStore

  func body(content: Content) -> some View {
    content.onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      Task { await store.refresh() }
    }
  }
}
