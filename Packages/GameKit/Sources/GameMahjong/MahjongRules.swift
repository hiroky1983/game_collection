import Foundation

/// 対局の長さ（#639・`docs/ai-devops.md`「1局=1RuleSet」の規約）。
///
/// 値型で持ち、**対局の開始時に `MahjongModel` へ焼き込む**。進行中の対局はこの値だけを見て動き、
/// 開始シートの選択（= 次の対局に使う設定）を対局中に読みに行かない。読みに行く形にすると、
/// 対局の途中で選択が変わったときに終局条件と順位の根拠が前半と後半で入れ替わる。
public enum MahjongGameLength: String, Codable, Sendable, CaseIterable, Identifiable {
    /// 東1局〜東4局（v1.1.4 までと 1 ビットも変わらない現行ルール）。
    case tonpuu
    /// 東1局だけを打って順位を決める一局戦（#639）。
    case singleHand

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tonpuu:     return "東風戦"
        case .singleHand: return "一局戦"
        }
    }

    public var summary: String {
        switch self {
        case .tonpuu:     return "東1局から東4局まで打って順位を決める、いつもの対局"
        case .singleHand: return "東1局だけで順位を決める短い対局。すきま時間に1局だけ"
        }
    }

    /// 打ち切る局数（東 n 局の n の上限）。
    ///
    /// `MahjongModel.playerCount` と同じ 4 だが、そちらは「参加人数」で意味が違うため参照しない
    /// （`MahjongModel` は `@MainActor` 隔離で、この値型からは読めないという事情もある）。
    public var roundCount: Int {
        switch self {
        case .tonpuu:     return 4
        case .singleHand: return 1
        }
    }

    /// 親の連荘（親の和了・親の聴牌流局で本場が増え、同じ局を続ける）があるか。
    ///
    /// 一局戦で連荘を認めると「1局で終わる」という約束のほうが破れる（親が和了り続けるかぎり
    /// 東1局1本場・2本場…と伸びる）。**連荘が無いので、その変形であるアガリやめも起きない。**
    public var allowsDealerRepeat: Bool { self == .tonpuu }

    /// 自己ベスト・通算成績を分けて数えるための区分キー（`GameScore.variant`）。
    ///
    /// 東風戦は **nil のまま**にする。ここに文字列を入れると記録の保存先が `mahjong4` から
    /// `mahjong4#tonpuu` に変わり、これまでの通算成績がどこからも参照されなくなる。
    public var recordVariant: String? {
        self == .tonpuu ? nil : rawValue
    }

    /// ハブ・リザルトの記録行に添える区分名。東風戦は従来どおり添えない。
    public var recordVariantLabel: String? {
        self == .tonpuu ? nil : title
    }

    /// Game Center のリーダーボードへ送ってよいか。
    ///
    /// **順位表は東風戦固定**。一局戦は 1 局の出来だけで順位が決まるぶん結果のばらつきが大きく、
    /// 同じ表に混ぜると「どちらのルールで遊んだか」の表になる。四人打ち麻雀は現時点で
    /// `metric` が `.winLoss` のため送信対象のリーダーボード自体を持たないが、後から
    /// 追加されたときに一局戦が黙って混ざらないよう、区分と同じ軸をここでも立てておく。
    public var isLeaderboardEligible: Bool {
        self == .tonpuu
    }
}
