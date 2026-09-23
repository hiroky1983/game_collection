import Foundation
import SwiftUI
import Core

/// いろリレー（#1320）の札の色。4 色はアプリの差し色（`Theme`）をそのまま使う。
///
/// 特定製品の色・配置・書体は写さない（Issue #1320 の権利面の注意）。色そのものは保護対象外だが、
/// 面の意匠（枠・窓・記号）は `ColorRelayCardView` で完全オリジナルに起こしている。
public enum RelayColor: Int, CaseIterable, Codable, Sendable, Hashable {
    case red, green, purple, yellow

    /// 画面と読み上げの呼び名。
    public var name: String {
        switch self {
        case .red:    return "あか"
        case .green:  return "みどり"
        case .purple: return "むらさき"
        case .yellow: return "きいろ"
        }
    }

    /// 札の面の色。差し色の**濃い側**を使う（白い窓に載せた数字の読みやすさを取る）。
    public var color: Color {
        switch self {
        case .red:    return Theme.coral
        case .green:  return Theme.teal
        case .purple: return Theme.purple
        case .yellow: return Theme.yellow
        }
    }
}

/// 札の種類。数字 0〜9 と特殊札 5 種。
public enum RelayKind: Codable, Sendable, Hashable, Equatable {
    case number(Int)
    /// 次の人の番を飛ばす。
    case skip
    /// 回る向きを逆にする。
    case reverse
    /// 次の人が 2 枚引いて番を飛ばされる。
    case drawTwo
    /// 色を選び直す（どの札の上にも出せる）。
    case wild
    /// 色を選び直し、次の人が 4 枚引いて番を飛ばされる。
    case wildDrawFour

    /// 色を持たない万能札か。
    public var isWild: Bool {
        switch self {
        case .wild, .wildDrawFour: return true
        default: return false
        }
    }

    /// 次の人に課す引き札の枚数（無ければ 0）。
    public var penalty: Int {
        switch self {
        case .drawTwo:      return 2
        case .wildDrawFour: return 4
        default:            return 0
        }
    }

    /// 面に描く短い表記（読み上げは `ColorRelayAccessibility` が別に持つ）。
    public var label: String {
        switch self {
        case .number(let n):  return "\(n)"
        case .skip:           return "とばし"
        case .reverse:        return "ぎゃく"
        case .drawTwo:        return "+2"
        case .wild:           return "いろがえ"
        case .wildDrawFour:   return "いろがえ+4"
        }
    }

    /// 手札の並べ替えに使う順序（数字 → 特殊札 → 万能札）。
    var sortOrder: Int {
        switch self {
        case .number(let n):  return n
        case .skip:           return 10
        case .reverse:        return 11
        case .drawTwo:        return 12
        case .wild:           return 13
        case .wildDrawFour:   return 14
        }
    }
}

/// いろリレーの 1 枚。`color` が nil なら万能札。
public struct RelayCard: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: Int
    public let color: RelayColor?
    public let kind: RelayKind

    public init(id: Int, color: RelayColor?, kind: RelayKind) {
        self.id = id
        self.color = color
        self.kind = kind
    }

    public var isWild: Bool { kind.isWild }

    /// 手札に並べる順（色 → 種類）。万能札は末尾。
    public var sortKey: Int {
        (color?.rawValue ?? RelayColor.allCases.count) * 100 + kind.sortOrder
    }
}

public extension RelayCard {
    /// 1 色あたりの構成: 0 が 1 枚・1〜9 が 2 枚ずつ・とばし / ぎゃく / +2 が 2 枚ずつ（25 枚）。
    /// 4 色で 100 枚に、いろがえ 4 枚・いろがえ+4 の 4 枚を足した **108 枚**の山札（未シャッフル）。
    static func makeDeck() -> [RelayCard] {
        var cards: [RelayCard] = []
        var id = 0
        func add(_ color: RelayColor?, _ kind: RelayKind, count: Int) {
            for _ in 0..<count {
                cards.append(RelayCard(id: id, color: color, kind: kind))
                id += 1
            }
        }
        for color in RelayColor.allCases {
            add(color, .number(0), count: 1)
            for n in 1...9 { add(color, .number(n), count: 2) }
            add(color, .skip, count: 2)
            add(color, .reverse, count: 2)
            add(color, .drawTwo, count: 2)
        }
        add(nil, .wild, count: 4)
        add(nil, .wildDrawFour, count: 4)
        return cards
    }
}
