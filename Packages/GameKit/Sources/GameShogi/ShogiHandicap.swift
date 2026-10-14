import Foundation
import CoreEngine

/// 将棋の手合い（#2179）。平手と、上手が駒を落とす駒落ち（飛車落ち・角落ち）。
///
/// 上手（駒を落とした側）は盤の上＝後手の位置に座り、**先に指す**（将棋の決まり）。
/// 手合いは**開始局面（`initialSFEN`）そのもの**に焼き込む。中断データは開始局面を持っているので、
/// 続きから再開しても手合いが保たれ、スナップショットに項目を足す必要も無い（`detect`）。
public enum ShogiHandicap: String, CaseIterable, Sendable {
    case even
    case rook
    case bishop

    /// 開始局面の SFEN。駒落ちは上手＝後手の駒を 1 枚欠き、後手番（上手が先）で始まる。
    public var initialSFEN: String {
        switch self {
        case .even:   return Position.startSFEN
        case .rook:   return "lnsgkgsnl/7b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL w - 1"
        case .bishop: return "lnsgkgsnl/1r7/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL w - 1"
        }
    }

    /// 開始局面の SFEN から手合いを読み取る。駒落ちの 2 つ以外は平手として扱う。
    public static func detect(initialSFEN: String) -> ShogiHandicap {
        allCases.first { $0 != .even && $0.initialSFEN == initialSFEN } ?? .even
    }

    /// 駒を落とした側（上手）が盤の上＝後手の位置に座る。平手には上手がいない。
    public static let upperSide: Side = .white

    /// KIF の `手合割：` に書く名前（棋譜の書式そのもの）。
    public var kifName: String {
        switch self {
        case .even:   return "平手"  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
        case .rook:   return "飛車落ち"  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
        case .bishop: return "角落ち"  // i18n-keep: 棋譜（KIF）の書式そのもの（日本語の形式）
        }
    }

    /// 画面に出す名前。
    public var title: String {
        switch self {
        case .even:   return tr("平手")
        case .rook:   return tr("飛車落ち")
        case .bishop: return tr("角落ち")
        }
    }
}

/// 駒を落とす（上手になる）のはどちらか。
public enum ShogiHandicapDropper: String, CaseIterable, Sendable {
    /// 自分が落とす（自分が上手＝後手の位置で、先に指す）。
    case player
    /// CPU が落とす（CPU が上手で先に指す。自分は駒の揃った下手）。
    case cpu

    /// 人間が座る側。上手は後手の位置。
    var humanSide: Side {
        self == .player ? ShogiHandicap.upperSide : ShogiHandicap.upperSide.opponent
    }

    /// 人間の座る側から、落とす側を読み取る（開始局面が駒落ちのときだけ意味を持つ）。
    static func from(humanSide: Side) -> ShogiHandicapDropper {
        humanSide == ShogiHandicap.upperSide ? .player : .cpu
    }

    var title: String {
        switch self {
        case .player: return tr("自分が落とす")
        case .cpu:    return tr("CPUが落とす")
        }
    }
}

/// 手合いと落とす側の組。記録の区分・解析の `mode`・画面の表示名の出どころ。
public struct ShogiMatchSetting: Equatable, Sendable {
    public var handicap: ShogiHandicap
    public var dropper: ShogiHandicapDropper

    public init(handicap: ShogiHandicap, dropper: ShogiHandicapDropper) {
        self.handicap = handicap
        self.dropper = dropper
    }

    /// 平手は落とす側を持たない（`dropper` は使わない）。
    public var isHandicap: Bool { handicap != .even }

    /// 記録を分ける区分のキー。**平手は nil のまま**にする（従来の保存先 `shogi` に通算成績が
    /// 残っているため。ここに文字列を入れると旧記録がどこからも参照されなくなる）。
    /// 落とす側まで分けるのは、自分が落とした勝ちと CPU に落とされた勝ちが別物だから。
    public var recordVariant: String? {
        isHandicap ? "\(handicap.rawValue)-\(dropper.rawValue)" : nil
    }

    /// 記録に保存する区分名（日本語の控え）。ハブ・共有文に出す名前は `RecordVariantLabels` が
    /// `recordVariant` のキーから表示のたびに引き直す（#2240）ので、保存と表示で綴りが食い違わない。
    public var recordVariantLabel: String? {
        recordVariant.map { RecordVariantLabels.stored(gameID: "shogi", variant: $0) }
    }

    /// 解析イベントの `mode`。平手も値を持つ（`recordVariant` と違い保存先には使わないので互換の問題が無い）。
    public var analyticsMode: AnalyticsMode {
        switch (handicap, dropper) {
        case (.even, _):         return .even
        case (.rook, .player):   return .rookPlayer
        case (.rook, .cpu):      return .rookCPU
        case (.bishop, .player): return .bishopPlayer
        case (.bishop, .cpu):    return .bishopCPU
        }
    }

    /// ステータスバー・遊び方に出す短い名前。平手は nil（従来どおり何も足さない）。
    public var displayName: String? {
        guard isHandicap else { return nil }
        return tr("%1$@・%2$@", handicap.title, dropper.title)
    }
}
