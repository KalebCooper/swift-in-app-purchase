import Foundation

/// The text a ``TipJarView`` shows, supplied by the app so it is localized in the app's own bundle.
public struct TipJarCopy: Sendable {
  /// Shown after a tip completes.
  public let thankYou: LocalizedStringResource
  /// The tip jar's heading.
  public let title: LocalizedStringResource

  /// Creates the tip jar's text.
  public init(thankYou: LocalizedStringResource, title: LocalizedStringResource) {
    self.thankYou = thankYou
    self.title = title
  }
}
