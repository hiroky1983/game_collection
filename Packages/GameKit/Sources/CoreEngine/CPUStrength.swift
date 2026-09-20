import Foundation

/// CPU と 1 対 1 で戦う盤ゲーム（将棋・チェス・五目並べ・オセロ）の強さ 5 段階（#1174）。
///
/// 呼び名・並び・解析の段階はここ 1 か所で持ち、4 ゲームで**完全に同じ言葉**にする
/// （面色と選択 UI は Core 側の `CPUStrengthPicker`）。**探索の中身は各ゲームのエンジンが
/// 個別に持つ**（エンジンは共通化しない。#1174 の決定）。
///
/// `rawValue` は各ゲームのモデルが持つ `aiLevel` そのもので、中断データにもこの数字で入る。
/// **強さの順に並ぶが 0 始まりではない**: 既存 3 段階（0=簡単・1=ふつう・2=むずかしい）の
/// 番号を動かすと、中断データからの再開が 1 段ずれ、段階ごとの強さを固定している既存テストの
/// 意味まで変わってしまう。そのため、あとから足した「入門」を -1、「ガチ」を 3 に置いてある。
public enum CPUStrength: Int, Codable, CaseIterable, Sendable {
    /// 入門。最弱（#1174 で追加）。
    case novice = -1
    /// 簡単。呼び名を変える前の「弱」。
    case easy = 0
    /// ふつう。同じく「普通」。
    case normal = 1
    /// むずかしい。同じく「強」。
    case hard = 2
    /// ガチ。最強（#1174 で追加）。
    case serious = 3

    /// 開始シート・新規対局の既定。
    public static let standard = CPUStrength.normal

    /// 画面に出す呼び名（#1174 で確定。装飾のない短い言葉でトーンを揃えてある）。
    public var label: String {
        switch self {
        case .novice:  return "入門"
        case .easy:    return "簡単"
        case .normal:  return "ふつう"
        case .hard:    return "むずかしい"
        case .serious: return "ガチ"
        }
    }

    /// 解析に載せる段階。既存 3 段階の値（`beginner`/`normal`/`hard`）は動かさないので、
    /// GA4 に貯まっている数字はそのまま続けて読める（#1174）。
    public var analyticsLevel: AnalyticsLevel {
        switch self {
        case .novice:  return .novice
        case .easy:    return .beginner
        case .normal:  return .normal
        case .hard:    return .hard
        case .serious: return .expert
        }
    }

    /// やさしい順の並びでの位置（0 始まり）。`DifficultyLadder` の `currentLevel` に渡す。
    public var ladderIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    // MARK: 生の `aiLevel` からの読み替え

    /// やさしい順に並べた呼び名。`DifficultyLadder` の `levelLabels` に渡す。
    public static let labels: [String] = allCases.map(\.label)

    /// 中断データ・モデルが持つ生の番号を段階に写す。知らない番号は既定に倒す。
    public static func strength(for level: Int) -> CPUStrength {
        CPUStrength(rawValue: level) ?? .standard
    }

    /// `aiLevel` → 並びでの位置。`DifficultyLadder` の `currentLevel`。
    public static func ladderIndex(forLevel level: Int) -> Int { strength(for: level).ladderIndex }

    /// 並びでの位置（0 始まり）→ `aiLevel`。`DifficultyLadder` が勧めてきた段で始め直すのに使う。
    public static func level(atLadderIndex index: Int) -> Int {
        allCases.indices.contains(index) ? allCases[index].rawValue : standard.rawValue
    }

    /// 解析の段階（`aiLevel` から直接）。
    public static func analyticsLevel(forLevel level: Int) -> AnalyticsLevel {
        strength(for: level).analyticsLevel
    }
}
