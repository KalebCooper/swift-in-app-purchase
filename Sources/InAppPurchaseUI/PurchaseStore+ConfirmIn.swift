import InAppPurchase
import StoreKit

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit

extension PurchaseStore {
  /// Purchases `product` with `options`, confirming in `scene`, so the confirmation sheet appears
  /// in the scene the customer is looking at. Returns
  /// ``/InAppPurchase/PurchaseOutcome/success(_:)`` only after the handler delivered the
  /// transaction and it was finished.
  ///
  /// The app picks the scene, typically the one holding the view that started the purchase. A
  /// store backed by `MockPurchaseClient` ignores `scene`.
  ///
  /// ```swift
  /// if let scene = view.window?.windowScene {
  ///   _ = try await store.purchase(product, confirmIn: scene)
  /// }
  /// ```
  ///
  /// - Throws: The same errors as ``/InAppPurchase/PurchaseStore/purchase(_:options:)``.
  public func purchase(
    _ product: PurchaseProduct,
    confirmIn scene: some UIScene,
    options: Set<Product.PurchaseOption> = []
  ) async throws(PurchaseError) -> PurchaseOutcome {
    try await purchase(
      product,
      using: Purchaser { product, options in
        try await product.purchase(confirmIn: scene, options: options)
      },
      options: options
    )
  }

  /// Purchases `product` with `options`, confirming near `viewController`. Returns
  /// ``/InAppPurchase/PurchaseOutcome/success(_:)`` only after the handler delivered the
  /// transaction and it was finished.
  ///
  /// A store backed by `MockPurchaseClient` ignores `viewController`.
  ///
  /// - Throws: The same errors as ``/InAppPurchase/PurchaseStore/purchase(_:options:)``.
  public func purchase(
    _ product: PurchaseProduct,
    confirmIn viewController: UIViewController,
    options: Set<Product.PurchaseOption> = []
  ) async throws(PurchaseError) -> PurchaseOutcome {
    try await purchase(
      product,
      using: Purchaser { product, options in
        try await product.purchase(confirmIn: viewController, options: options)
      },
      options: options
    )
  }
}
#endif

#if os(macOS)
import AppKit

extension PurchaseStore {
  /// Purchases `product` with `options`, confirming in `window`, so the confirmation sheet appears
  /// on the window the customer is looking at. Returns
  /// ``/InAppPurchase/PurchaseOutcome/success(_:)`` only after the handler delivered the
  /// transaction and it was finished.
  ///
  /// A store backed by `MockPurchaseClient` ignores `window`.
  ///
  /// - Throws: The same errors as ``/InAppPurchase/PurchaseStore/purchase(_:options:)``.
  public func purchase(
    _ product: PurchaseProduct,
    confirmIn window: NSWindow,
    options: Set<Product.PurchaseOption> = []
  ) async throws(PurchaseError) -> PurchaseOutcome {
    try await purchase(
      product,
      using: Purchaser { product, options in
        try await product.purchase(confirmIn: window, options: options)
      },
      options: options
    )
  }
}
#endif
