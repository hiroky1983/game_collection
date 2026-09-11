import SwiftUI
import Core

/// 札の絵柄に載る「主役」（#495）。
///
/// 月の植物（松・梅…）は `HanafudaCard.month` から決まるので持たない。ここに並ぶのは
/// **その月の 4 枚を見分ける決め手**だけ。
public enum HanafudaMotif: String, CaseIterable, Sendable, Equatable {
    case crane      // 鶴
    case warbler    // 鶯
    case curtain    // 幕
    case cuckoo     // 不如帰
    case bridge     // 八橋
    case butterfly  // 蝶
    case boar       // 猪
    case moon       // 月
    case geese      // 雁
    case sakeCup    // 盃
    case deer       // 鹿
    case rainMan    // 小野道風（傘と雨）
    case swallow    // 燕
    case lightning  // 鬼札（雷）
    case phoenix    // 鳳凰
}

/// 絵柄まわりの純粋な定義。**描画そのものは `HanafudaCardFace`（Canvas 1 枚）が行う**。
///
/// 図案は既存メーカーの札を一切参照せず、伝統的なモチーフ（公有）だけを題材に
/// 単純化して起こしている（権利チェックの結論・Issue #495）。
public enum HanafudaCardArt {

    /// その札の主役。カス札は主役を持たない（月の植物だけで描く）。
    public static func motif(for card: HanafudaCard) -> HanafudaMotif? {
        switch card.id {
        case 0:  return .crane
        case 4:  return .warbler
        case 8:  return .curtain
        case 12: return .cuckoo
        case 16: return .bridge
        case 20: return .butterfly
        case 24: return .boar
        case 28: return .moon
        case 29: return .geese
        case 32: return .sakeCup
        case 36: return .deer
        case 40: return .rainMan
        case 41: return .swallow
        case 43: return .lightning
        case 44: return .phoenix
        default: return nil
        }
    }

    /// 月ごとの主色（植物の花・葉に使う）。ライト / ダークで同じ値を使う
    /// （札の面はどちらでも生成りのままなので、地とのコントラストが変わらない）。
    public static func monthColor(_ month: Int) -> Color {
        Color(hex: monthHex(month))
    }

    /// 月ごとの主色（16 進）。テストから直接読めるようにしてある。
    public static func monthHex(_ month: Int) -> UInt32 {
        switch month {
        case 1:  return 0x2E6B4F   // 松：深緑
        case 2:  return 0xC94F6D   // 梅：紅梅
        case 3:  return 0xEE8FA8   // 桜：桜色
        case 4:  return 0x8C7BE0   // 藤：藤色
        case 5:  return 0x5A64C4   // 菖蒲：青紫
        case 6:  return 0xD1435B   // 牡丹：紅
        case 7:  return 0x8E6BB0   // 萩：薄紫
        case 8:  return 0x8C8272   // 芒：薄墨
        case 9:  return 0xE8A33D   // 菊：山吹
        case 10: return 0xD9542B   // 紅葉：朱
        case 11: return 0x3A6EA5   // 柳：藍
        default: return 0xA98BC4   // 桐：桐色
        }
    }

    /// 札の下端に敷く季節の地色。主色を薄めた面で、月ごとの見分けを助ける。
    public static func groundColor(_ month: Int) -> Color {
        monthColor(month).opacity(0.16)
    }

    /// 枝・幹・輪郭に使う共通の墨色。
    public static let inkHex: UInt32 = 0x3A2E27
    public static var ink: Color { Color(hex: inkHex) }

    // MARK: - 種別の帯（#602）

    /// 札の上端に敷く帯の色。**種別（光・タネ・短冊・カス）を色で表す**。
    ///
    /// 図案の色（`monthColor`）とは別に持つ。図案の色は花や葉として見える明るさが要るのに対し、
    /// 帯は上に文字を載せる面なので暗くないと読めず、求められる明るさが逆を向く（#220 と同型）。
    /// 短冊札だけは短冊自身の赤 / 青を使い、**帯を見ただけで赤短・青短が分かる**ようにする
    /// （どちらも役の名前がそのまま付いている）。
    public static func kindHex(for card: HanafudaCard) -> UInt32 {
        if let ribbon = card.ribbon {
            return ribbon == .blue ? blueRibbonBandHex : redRibbonBandHex
        }
        switch card.kind {
        case .hikari:  return 0xD4A93A   // 金
        case .tane:    return 0x2F7050   // 常緑
        case .kasu:    return 0x6F675E   // 薄墨
        // 短冊札は 10 枚すべてが `ribbon` を持つので、ここには来ない（`HanafudaArtTests` で固定）。
        case .tanzaku: return redRibbonBandHex
        }
    }

    public static func kindColor(for card: HanafudaCard) -> Color {
        Color(hex: kindHex(for: card))
    }

    public static let redRibbonBandHex: UInt32 = 0xC63A3A
    public static let blueRibbonBandHex: UInt32 = 0x3E6FB0

    /// 帯の上に載せる文字色。**1 つの色で面と文字の両方は賄えない**ので、
    /// 地の明るさを見て生成りか墨のどちらか読めるほうを選ぶ（#220）。
    public static func bandLabelHex(on background: UInt32) -> UInt32 {
        contrastRatio(background, bandLabelLightHex) >= contrastRatio(background, bandLabelDarkHex)
            ? bandLabelLightHex : bandLabelDarkHex
    }

    public static let bandLabelLightHex: UInt32 = 0xFFFFFF
    public static var bandLabelDarkHex: UInt32 { inkHex }

    /// WCAG のコントラスト比。`bandLabelHex(on:)` の判断に使う。
    public static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func relativeLuminance(_ hex: UInt32) -> Double {
        func channel(_ raw: UInt32) -> Double {
            let v = Double(raw) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF)
            + 0.7152 * channel((hex >> 8) & 0xFF)
            + 0.0722 * channel(hex & 0xFF)
    }

    /// 短冊の色。
    public static func ribbonColor(_ ribbon: HanafudaRibbon) -> Color {
        switch ribbon {
        case .redPoem, .plainRed: return Color(hex: 0xD64545)
        case .blue:               return Color(hex: 0x3E6FB0)
        }
    }

    /// 札の縦横比（実物の花札は約 1.5:1）。
    public static let aspectRatio: CGFloat = 1.5

    /// 48 枚が「同じ月の中で必ず見分けられる」ことの定義。
    ///
    /// 見分けの手掛かりは（主役 / 短冊の色 / どちらも無い＝カス）の 3 種で、
    /// **同じ月に同じ手掛かりの札が 2 枚並ぶのはカスだけ**であることをテストで固定する
    /// （カス同士は絵柄が同じでよい。実物も同月のカスは似た図柄で、役の上でも区別が無い）。
    public static func distinguishingKey(for card: HanafudaCard) -> String {
        if let motif = motif(for: card) { return "motif:\(motif.rawValue)" }
        if let ribbon = card.ribbon { return "ribbon:\(ribbon.rawValue)" }
        return "kasu"
    }
}
