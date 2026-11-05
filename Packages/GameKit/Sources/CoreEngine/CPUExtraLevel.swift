import Foundation

/// `CPUStrength` の並びの外にある、1 ゲームだけの段（将棋の「達人」#2698）。
///
/// `CPUStrength.strength(for:)` は知らない番号を黙って「ふつう」に倒すので、共通外の段は
/// 呼び名・記録区分・解析の値・階段の扱いをここ 1 か所に持たせ、各所で個別に先取りしない
/// （#3110 の再発防止・#3147）。
public struct CPUExtraLevel: Sendable, Equatable {
    /// 生の `aiLevel`。`CPUStrength.allCases` の `rawValue` と重ならないこと（`CPULevel` が検出する）。
    public let level: Int
    public let label: String
    /// 記録の区分キー。駒落ちなどの区分は `recordVariant(handicapVariant:)` で後ろに足す。
    public let recordVariantKey: String
    public let analyticsLevel: AnalyticsLevel

    public init(level: Int, label: String, recordVariantKey: String, analyticsLevel: AnalyticsLevel) {
        self.level = level
        self.label = label
        self.recordVariantKey = recordVariantKey
        self.analyticsLevel = analyticsLevel
    }

    /// 手合いの区分の前にキーを付ける（`master-rook-player`）。手合いが無ければキーだけ（`master`）。
    public func recordVariant(handicapVariant: String?) -> String {
        handicapVariant.map { "\(recordVariantKey)-\($0)" } ?? recordVariantKey
    }
}

/// 生の `aiLevel` が指す段。共通の段か、共通外の段か。
public enum CPULevel: Sendable, Equatable {
    case strength(CPUStrength)
    case extra(CPUExtraLevel)

    /// 知らない番号は `nil`（`CPUStrength.strength(for:)` のように既定へ倒さない）。
    /// 共通の段と番号が重なる `extras` は共通の段を優先せず `nil` にして、テストで気づけるようにする。
    public init?(level: Int, extras: [CPUExtraLevel]) {
        let matched = extras.filter { $0.level == level }
        if let strength = CPUStrength(rawValue: level) {
            guard matched.isEmpty else { return nil }
            self = .strength(strength)
        } else if matched.count == 1, let extra = matched.first {
            self = .extra(extra)
        } else {
            return nil
        }
    }

    /// 中断データなど、外から来た番号用。知らない番号は既定の「ふつう」。
    public init(levelOrStandard level: Int, extras: [CPUExtraLevel]) {
        self = CPULevel(level: level, extras: extras) ?? .strength(.standard)
    }

    public var label: String {
        switch self {
        case .strength(let s): return s.label
        case .extra(let e): return e.label
        }
    }

    public var analyticsLevel: AnalyticsLevel {
        switch self {
        case .strength(let s): return s.analyticsLevel
        case .extra(let e): return e.analyticsLevel
        }
    }

    /// 共通の並び（`DifficultyLadder`）に載る段か。共通外の段は勧める先が無いので載らない。
    public var isOnLadder: Bool {
        if case .strength = self { return true }
        return false
    }
}
