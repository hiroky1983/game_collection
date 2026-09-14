import Foundation

/// 配色のコントラスト検査（WCAG 2.1）。配色のテストと将棋の王手表示のテストで同じ式がコピーされていたので集約する（#529）。
public enum WCAG {
    /// sRGB の相対輝度（WCAG 2.1 の定義）。`hex` は `0xRRGGBB`。
    public static func relativeLuminance(_ hex: UInt32) -> Double {
        func channel(_ raw: UInt32) -> Double {
            let v = Double(raw) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF)
            + 0.7152 * channel((hex >> 8) & 0xFF)
            + 0.0722 * channel(hex & 0xFF)
    }

    /// 2色のコントラスト比（1.0〜21.0）。
    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
