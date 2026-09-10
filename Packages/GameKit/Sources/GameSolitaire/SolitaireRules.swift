import Foundation

/// 山札のめくり方（#498）。世界標準の分岐で、1 枚めくりが本作の既定・現行ルール。
public enum SolitaireDrawMode: String, CaseIterable, Codable, Sendable, Equatable {
    /// 1 枚ずつめくる（既定）。
    case one
    /// 3 枚ずつめくり、使えるのは一番上の 1 枚だけ（標準の draw-3）。
    case three

    /// 1 回の「めくる」で捨て札へ送る枚数。山札の残りがこれより少なければ残り全部。
    public var drawCount: Int {
        switch self {
        case .one:   return 1
        case .three: return 3
        }
    }

    public var label: String {
        switch self {
        case .one:   return "1枚めくり"
        case .three: return "3枚めくり"
        }
    }

    /// 記録の保存先（`GameScore.variant`）。
    ///
    /// **既定（1 枚めくり）は必ず nil**。文字列を入れると保存先が `solitaire` →
    /// `solitaire#draw1` に変わり、これまでの自己ベストがどこからも参照されなくなる
    /// （`docs/ai-devops.md`「1局=1RuleSet」規約3）。
    public var recordVariant: String? {
        self == .three ? "draw3" : nil
    }

    /// 自己ベストの行に出す区分名。既定は区分を持たないので nil。
    public var recordLabel: String? {
        self == .three ? label : nil
    }
}

/// 1 局に焼き込むルールの束（#498。`docs/ai-devops.md`「1局=1RuleSet」原則）。
///
/// 局の開始時に `SolitaireModel` へ焼き込み、進行中の局はこの値だけを見て動く。
/// 設定画面や `UserDefaults` を局中に読みに行かないので、途中でルールが入れ替わることがない。
public struct SolitaireRuleSet: Equatable, Sendable, Codable {
    public var drawMode: SolitaireDrawMode

    public init(drawMode: SolitaireDrawMode = .one) {
        self.drawMode = drawMode
    }

    /// 現行ルール（1 枚めくり）。既定はこれで、挙動は #498 以前と 1 ビットも変わらない。
    public static let standard = SolitaireRuleSet()

    public var drawCount: Int { drawMode.drawCount }
}
