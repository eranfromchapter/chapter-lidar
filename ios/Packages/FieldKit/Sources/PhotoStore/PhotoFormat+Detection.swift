import FieldRules
import Foundation

extension PhotoFormat {
  /// Recognizes JPEG and HEIC by their first bytes. Nil for anything else (PNG, PDF, empty).
  public static func detect(_ data: Data) -> PhotoFormat? {
    let head = [UInt8](data.prefix(12))
    if head.count >= 3, head[0] == 0xFF, head[1] == 0xD8, head[2] == 0xFF { return .jpeg }
    if head.count >= 12, head[4] == 0x66, head[5] == 0x74, head[6] == 0x79, head[7] == 0x70 {
      // "ftyp" box; the major brand follows.
      let brand = String(decoding: head[8..<12], as: UTF8.self)
      if ["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"].contains(brand) {
        return .heic
      }
    }
    return nil
  }
}
