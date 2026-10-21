/// Marketing names of the phones and tablets with LiDAR (phone-capture §5.7), for the Device row
/// of New capture and `record.device.marketingName`. An unknown identifier gives nil and the
/// screen shows the identifier.
///
/// The iPhone 17 Pro identifiers (iPhone18,1 and iPhone18,2) and the iPad Pro (M5) ones are
/// still to be checked against Apple's list of model identifiers (phone-capture §5.7) before
/// release; a wrong entry only changes the name shown and recorded, never the device gate.
public enum DeviceNames {
  public static let table: [String: String] = [
    "iPhone13,3": "iPhone 12 Pro",
    "iPhone13,4": "iPhone 12 Pro Max",
    "iPhone14,2": "iPhone 13 Pro",
    "iPhone14,3": "iPhone 13 Pro Max",
    "iPhone15,2": "iPhone 14 Pro",
    "iPhone15,3": "iPhone 14 Pro Max",
    "iPhone16,1": "iPhone 15 Pro",
    "iPhone16,2": "iPhone 15 Pro Max",
    "iPhone17,1": "iPhone 16 Pro",
    "iPhone17,2": "iPhone 16 Pro Max",
    "iPhone18,1": "iPhone 17 Pro",
    "iPhone18,2": "iPhone 17 Pro Max",
    "iPad8,9": "iPad Pro 11-inch (2nd generation)",
    "iPad8,10": "iPad Pro 11-inch (2nd generation)",
    "iPad8,11": "iPad Pro 12.9-inch (4th generation)",
    "iPad8,12": "iPad Pro 12.9-inch (4th generation)",
    "iPad13,4": "iPad Pro 11-inch (3rd generation)",
    "iPad13,5": "iPad Pro 11-inch (3rd generation)",
    "iPad13,6": "iPad Pro 11-inch (3rd generation)",
    "iPad13,7": "iPad Pro 11-inch (3rd generation)",
    "iPad13,8": "iPad Pro 12.9-inch (5th generation)",
    "iPad13,9": "iPad Pro 12.9-inch (5th generation)",
    "iPad13,10": "iPad Pro 12.9-inch (5th generation)",
    "iPad13,11": "iPad Pro 12.9-inch (5th generation)",
    "iPad14,3": "iPad Pro 11-inch (4th generation)",
    "iPad14,4": "iPad Pro 11-inch (4th generation)",
    "iPad14,5": "iPad Pro 12.9-inch (6th generation)",
    "iPad14,6": "iPad Pro 12.9-inch (6th generation)",
    "iPad16,3": "iPad Pro 11-inch (M4)",
    "iPad16,4": "iPad Pro 11-inch (M4)",
    "iPad16,5": "iPad Pro 13-inch (M4)",
    "iPad16,6": "iPad Pro 13-inch (M4)",
    "iPad17,1": "iPad Pro 11-inch (M5)",
    "iPad17,2": "iPad Pro 11-inch (M5)",
    "iPad17,3": "iPad Pro 13-inch (M5)",
    "iPad17,4": "iPad Pro 13-inch (M5)",
  ]

  /// The marketing name of a model identifier ("iPhone17,1" → "iPhone 16 Pro"), nil when unknown.
  public static func marketingName(for identifier: String) -> String? {
    table[identifier]
  }
}
