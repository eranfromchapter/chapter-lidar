import Foundation

/// The words of "Delete all photos" on the Captures home's account dialog (field-test and UI-test
/// modes only; never in a Release build): the dialog's button, the in-page confirmation and the
/// line said afterwards.
public enum DeletePhotosText {
  /// The account dialog's destructive button, and the confirmation's destructive button.
  public static let button = "Delete all photos"
  public static let title = "Delete all photos?"
  public static let message =
    "This erases every site photo Space Capture holds on this phone, including the copies in "
    + "drafts and sealed packages. Scans, plans and field controls stay. This cannot be undone."
  public static let cancel = "Cancel"
  /// While the photos are being erased.
  public static let deleting = "Deleting photos\u{2026}"
  /// After the erasure: "Deleted 3 photos", "Deleted 1 photo", "No photos to delete".
  public static func result(deleted: Int) -> String {
    switch deleted {
    case 0: return "No photos to delete"
    case 1: return "Deleted 1 photo"
    default: return "Deleted \(deleted) photos"
    }
  }

  /// `result(deleted:)`, with how many files could not be removed when some could not.
  public static func result(deleted: Int, failures: Int) -> String {
    let line = result(deleted: deleted)
    guard failures > 0 else { return line }
    return "\(line). \(failures == 1 ? "1 file" : "\(failures) files") could not be deleted."
  }
}
