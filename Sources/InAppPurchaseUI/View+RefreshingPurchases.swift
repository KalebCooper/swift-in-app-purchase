import InAppPurchase
import SwiftUI

extension View {
  /// Calls ``/InAppPurchase/PurchaseStore/refresh()`` whenever the app returns to the foreground,
  /// so a transaction left unfinished, an entitlement that changed, or a failed product load is
  /// picked up when the customer comes back.
  ///
  /// On iOS, iPadOS, Mac Catalyst, tvOS, visionOS, and watchOS, the refresh runs when the scene
  /// leaves the background, not each time it becomes active. A system alert or sheet, such as
  /// StoreKit's own purchase confirmation, makes the scene inactive without leaving the foreground,
  /// and a refresh then would run in the middle of the purchase. On macOS, where a window stays
  /// active while another app has focus, the refresh runs when the scene becomes active.
  ///
  /// The first appearance does not refresh, because `start()` already did that work. A refresh
  /// that is under way runs to completion even if the scene leaves the foreground again, so an
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
    content.onChange(of: scenePhase) { previous, phase in
      guard Self.isReturningToForeground(from: previous, to: phase) else { return }
      Task { await store.refresh() }
    }
  }

  private static func isReturningToForeground(from previous: ScenePhase, to phase: ScenePhase)
    -> Bool
  {
    #if os(macOS)
    // A macOS window stays active while another app has focus, so it leaves the active phase
    // only when hidden or minimized.
    return phase == .active
    #else
    // An alert or sheet over the app moves the scene between active and inactive without it ever
    // leaving the foreground.
    return previous == .background && phase != .background
    #endif
  }
}
