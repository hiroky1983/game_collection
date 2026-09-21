import SwiftUI
import Core

/// 神経衰弱のカードの絵柄（#601 → #1244）。
///
/// v1.1.5 までの 18 種の抽象図形は廃止し、カードしりとり（#1243）と同じ**具体物カード**
/// （`ObjectCardKind`・ドット絵）に総入れ替えした。絵は Core の 1 か所で持つので、
/// 神経衰弱側では描かない。
///
/// **OS の絵文字は使わない**（意匠が iOS のバージョンで変わるため）。
///
/// `rawValue` は**中断データに書く識別子**（`ObjectCardKind.rawValue`）なので、一度出した値は変えない。
public typealias ConcentrationFigure = ObjectCardKind

/// 更新をまたいで中断が消えないよう、旧版が中断データに書いた識別子を読み替える。
///
/// 旧図形・旧絵文字は**先頭の 18 種と同じ並びのまま**新しいカードに対応づける
/// （`ObjectCardKind.allCases` の i 番目）。盤で使われるのは最大 18 種（18 ペア）で、
/// 1 対 1 の対応なので、読み替えても対が崩れない。
enum LegacyConcentrationFigure: CaseIterable {
    case circle, square, triangle, heart, star, crescent, droplet, leaf
    case diamond, flower, ring, sun, note, bolt, house, cloud, cross, arrow

    /// v1.1.4〜v1.1.5 の中断データに書かれていた図形の識別子。
    var identifier: String { String(describing: self) }

    /// v1.1.3 まで中断データに書かれていた絵文字。並びは当時の `concentrationSymbols` の先頭 18 個。
    var emoji: String {
        switch self {
        case .circle:   return "🍎"
        case .square:   return "🍊"
        case .triangle: return "🍋"
        case .heart:    return "🍇"
        case .star:     return "🍓"
        case .crescent: return "🍒"
        case .droplet:  return "🍑"
        case .leaf:     return "🥝"
        case .diamond:  return "🌸"
        case .flower:   return "🌻"
        case .ring:     return "🌈"
        case .sun:      return "⭐"
        case .note:     return "🎵"
        case .bolt:     return "🎃"
        case .house:    return "🎄"
        case .cloud:    return "🎁"
        case .cross:    return "🐶"
        case .arrow:    return "🐱"
        }
    }

    var replacement: ObjectCardKind {
        ObjectCardKind.allCases[Self.allCases.firstIndex(of: self)!]
    }

    static let byOldSymbol: [String: ObjectCardKind] = {
        var out: [String: ObjectCardKind] = [:]
        for legacy in allCases {
            out[legacy.identifier] = legacy.replacement
            out[legacy.emoji] = legacy.replacement
        }
        return out
    }()
}

extension ConcentrationFigure {
    /// 中断データの文字列を図案に戻す。現行の識別子を先に見て、無ければ旧版の図形・絵文字を引く。
    /// どちらでもない文字列は**読み替えず nil**（既定へ倒すと、対を成さない盤面が
    /// 「復元成功」として通ってしまう）。
    static func decode(_ raw: String) -> ConcentrationFigure? {
        if let figure = ConcentrationFigure(rawValue: raw) { return figure }
        return LegacyConcentrationFigure.byOldSymbol[raw]
    }
}

// MARK: - 表示

/// 絵柄 1 つぶん。描画は Core の `ObjectCardArt`（20×20 ドット・補間なし）。
struct ConcentrationFigureView: View {
    let figure: ConcentrationFigure

    var body: some View {
        ObjectCardArt(figure)
            .accessibilityHidden(true)  // 読み上げ文はカード側（`CardView`）が持つ
    }
}
