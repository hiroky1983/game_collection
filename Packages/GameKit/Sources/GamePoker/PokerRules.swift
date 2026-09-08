import Foundation

// MARK: - RuleSet

/// 1 局のあいだ変わらないルールの束（#496・「1局=1RuleSet」原則の初適用）。
///
/// 値型で持ち、**局の開始時に `PokerModel` へ焼き込む**。進行中の局はこの値だけを見て動き、
/// 開始シートの選択（＝次の局に使う設定）を局中に読みに行かない。設定を「いま参照する」形に
/// すると、局の途中で設定が変わったときに配当の根拠が入れ替わり、同じ局の前半と後半で
/// 別のルールが適用されうる。
public enum PokerRuleSet: String, Codable, Sendable, CaseIterable, Identifiable {
    /// 現行ルール（ポット総取り・役配当なし）。v1.1.3 までと 1 ビットも変わらない。
    case standard
    /// 役ボーナス表 + ダブルアップ。
    case bonus

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: return "スタンダード"
        case .bonus:    return "ボーナスルール"
        }
    }

    public var summary: String {
        switch self {
        case .standard: return "ポットの総取りだけで競う、いつもの5カードドロー"
        case .bonus:    return "勝負に勝つと役ごとのボーナス。さらにダブルアップに挑戦できる"
        }
    }

    /// 自己ベストを分けて数えるための区分キー（`GameScore.variant`）。
    ///
    /// スタンダードは **nil のまま**にする。ここに文字列を入れると記録の保存先が
    /// `poker` から `poker#standard` に変わり、これまでの自己ベストがどこからも参照されなくなる。
    public var recordVariant: String? {
        self == .standard ? nil : rawValue
    }

    /// ハブ・リザルトの記録行に添える区分名。スタンダードは従来どおり添えない。
    public var recordVariantLabel: String? {
        self == .standard ? nil : title
    }

    /// Game Center のリーダーボードへ送ってよいか。
    ///
    /// **順位表はスタンダード固定**（ボーナスルールは配当の出どころが増えるぶんチップが伸びるので、
    /// 同じ表に混ぜると「どちらのルールで遊んだか」の表になってしまう）。ボーナスルールの
    /// 自己ベストは `recordVariant` でローカルに別枠管理する。
    public var isLeaderboardEligible: Bool {
        self == .standard
    }
}

// MARK: - 役ボーナス表

/// 役 1 つぶんのボーナス配当。
public struct PokerBonusPayout: Identifiable, Equatable, Sendable {
    public let rank: PokerHandRank
    /// ポットとは別に配当されるチップ。
    public let chips: Int

    public var id: Int { rank.rawValue }
}

/// 役ボーナスの配当表（`PokerRuleSet.bonus` のときだけ効く）。
///
/// 刻みは「1 段上がるごとにおおよそ倍以上」。アンティ 10 枚・ベット 20 枚・持ち点 100 枚の
/// 経済に対して、**ツーペア（+10）はアンティ 1 回ぶん、フルハウス（+100）で持ち点が倍**になる
/// 大きさに合わせてある。ワンペア以下に配当を付けないのは、ほぼ毎局出る役に配当を付けると
/// ボーナスが「勝てば必ずもらえる上乗せ」になり、役を狙う動機が消えるため。
public enum PokerBonusTable {

    /// 強い役から順（画面の配当表もこの順で出す）。
    public static let payouts: [PokerBonusPayout] = [
        PokerBonusPayout(rank: .royalFlush,    chips: 1000),
        PokerBonusPayout(rank: .straightFlush, chips: 500),
        PokerBonusPayout(rank: .fourOfAKind,   chips: 250),
        PokerBonusPayout(rank: .fullHouse,     chips: 100),
        PokerBonusPayout(rank: .flush,         chips: 60),
        PokerBonusPayout(rank: .straight,      chips: 40),
        PokerBonusPayout(rank: .threeOfAKind,  chips: 20),
        PokerBonusPayout(rank: .twoPair,       chips: 10),
    ]

    /// その役のボーナス。表に無い役（ワンペア・ハイカード）は 0。
    public static func chips(for rank: PokerHandRank) -> Int {
        payouts.first { $0.rank == rank }?.chips ?? 0
    }
}

// MARK: - ダブルアップ

/// ダブルアップの予想。
public enum PokerHighLow: String, Sendable, Equatable {
    case high, low
}

/// 1 回めくった結果。
public enum PokerDoubleUpResult: String, Sendable, Equatable {
    /// 当たり。賭け金が倍になる。
    case success
    /// 外れ。賭け金を失う。
    case failure
    /// 同じ数字。賭け金はそのままで、挑戦回数も減らさずに引き直す。
    case push
}

/// ダブルアップの進行状態（`.result` の中の小さな状態機械）。
///
/// `.result` は `PokerModel.persist()` の保存対象外なので、この状態は中断データに載らない
/// （途中でアプリを閉じたら次回は新しい局から始まる）。
public struct PokerDoubleUp: Equatable, Sendable {
    /// いま賭かっているチップ。外すと 0 になる。
    public internal(set) var stake: Int
    /// 見えている札。この札より上か下かを当てる。
    public internal(set) var baseCard: PokerCard
    /// めくった札。まだ予想していなければ nil。
    public internal(set) var drawnCard: PokerCard?
    /// 当てた回数。`PokerModel.maxDoubleUpStreak` に達したら打ち止め。
    public internal(set) var streak: Int
    /// 直近のめくりの結果。まだ予想していなければ nil。
    public internal(set) var result: PokerDoubleUpResult?
    /// 精算済み（受け取ったか、外した）。二重に受け取らないための目印でもある。
    public internal(set) var isSettled: Bool = false
    /// 受け取ったチップ。外したときは 0。
    public internal(set) var payout: Int = 0

    /// 予想を待っている（次にめくれる）状態か。
    public var isAwaitingGuess: Bool { drawnCard == nil && !isSettled }
}
