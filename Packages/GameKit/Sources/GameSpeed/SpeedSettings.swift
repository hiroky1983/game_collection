import Core

/// CPU の反応の速さ。出せる札を見つけてから台札に置くまでの間で決める。
///
/// あなたの側に制限時間は無い。速さで競うのは「CPU より先に出せるか」だけで、
/// いちばんゆっくりの段は VoiceOver で手札と台札を読み終えてから出しても間に合う長さにしてある
/// （反射神経に頼らない設計との整合。Issue #1323）。
public enum SpeedLevel: String, CaseIterable, Codable, Sendable {
    case slow
    case normal
    case fast

    public var label: String {
        switch self {
        case .slow:   return "ゆっくり"
        case .normal: return "ふつう"
        case .fast:   return "はやい"
        }
    }

    /// CPU が出せる札を見つけてから置くまでの基準（ミリ秒）。実際は ±20% の揺らぎが乗る。
    public var reactionMilliseconds: Int {
        switch self {
        case .slow:   return 2600
        case .normal: return 1400
        case .fast:   return 750
        }
    }

    /// 開始シートの副題（「約2.6秒」など）。
    public var subtitle: String {
        switch self {
        case .slow:   return "約2.6秒で出す"
        case .normal: return "約1.4秒で出す"
        case .fast:   return "約0.75秒で出す"
        }
    }

    /// `game_start` の `level`（#500）。3 段階なので入門は使わない。
    public var analyticsLevel: AnalyticsLevel {
        switch self {
        case .slow:   return .beginner
        case .normal: return .normal
        case .fast:   return .hard
        }
    }
}

/// 1 ゲームぶんの設定。いまは CPU の速さだけ。
///
/// 「1局=1RuleSet」（`docs/ai-devops.md`）の作法どおり、ゲームを始めるときに Model へ焼き込み、
/// 途中で設定が変わっても進行中のゲームには効かない。
public struct SpeedSettings: Codable, Equatable, Sendable {
    public var level: SpeedLevel

    public init(level: SpeedLevel) {
        self.level = level
    }

    /// 初めて開いたときの既定。
    public static let standard = SpeedSettings(level: .normal)

    /// 記録（勝敗・連勝・最速）を分ける区分のキー。速さごとに 1 件。
    public var variant: String { level.rawValue }

    /// 区分の表示名。ハブの記録行と画面の見出しに使う。
    public var variantLabel: String { level.label }
}

/// 中断データ。**ゲームそのものは復元しない**（同時進行の駆け引きで成り立つゲームなので、途中から
/// 戻しても遊べない）。最後に選んだ速さだけを控え、次に開いたときの初期値にする（ぱっと暗算 #1321 と同じ）。
public struct SpeedSnapshot: Codable, Equatable, Sendable {
    public var settings: SpeedSettings

    public init(settings: SpeedSettings) {
        self.settings = settings
    }
}
