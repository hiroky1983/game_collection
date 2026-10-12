import Core

/// 出す数の桁数。
public enum AnzanDigits: Int, CaseIterable, Codable, Sendable {
    case one = 1
    case two = 2
    case three = 3

    public var label: String { label(language: nil) }

    /// `language` を指定した表示名（nil ならいまの表示言語）。記録用の区分名は日本語で引く。
    func label(language: AppLanguage?) -> String { tr("%lld桁", rawValue, language: language) }

    /// 出す数の範囲。0 で始まる数は出さない（1 桁は 1〜9、2 桁は 10〜99）。
    public var range: ClosedRange<Int> {
        switch self {
        case .one:   return 1...9
        case .two:   return 10...99
        case .three: return 100...999
        }
    }

    /// 開始シートの副題（「1〜9」など）。
    public var subtitle: String { tr("%1$lld〜%2$lld", range.lowerBound, range.upperBound) }
}

/// 出す数の個数（そろばん教室の言い方では「口数」）。
public enum AnzanCount: Int, CaseIterable, Codable, Sendable {
    case five = 5
    case ten = 10
    case fifteen = 15

    public var label: String { label(language: nil) }

    /// `language` を指定した表示名（nil ならいまの表示言語）。記録用の区分名は日本語で引く。
    func label(language: AppLanguage?) -> String { tr("%lld個", rawValue, language: language) }
}

/// 表示の速さ。1 つの数を出してから次の数を出すまでの間隔で決める。
public enum AnzanSpeed: String, CaseIterable, Codable, Sendable {
    case slow
    case normal
    case fast

    public var label: String { label(language: nil) }

    /// `language` を指定した表示名（nil ならいまの表示言語）。記録用の区分名は日本語で引く。
    func label(language: AppLanguage?) -> String {
        switch self {
        case .slow:   return tr("ゆっくり", language: language)
        case .normal: return tr("ふつう", language: language)
        case .fast:   return tr("はやい", language: language)
        }
    }

    /// 1 つの数を出してから次を出すまでの間隔（ミリ秒）。
    public var intervalMilliseconds: Int {
        switch self {
        case .slow:   return 1500
        case .normal: return 1000
        case .fast:   return 600
        }
    }

    /// 開始シートの副題（「1.5秒」など）。
    public var subtitle: String {
        switch self {
        case .slow:   return tr("1.5秒")
        case .normal: return tr("1秒")
        case .fast:   return tr("0.6秒")
        }
    }
}

/// 1 問ぶんの難易度。桁数・個数・速さの 3 軸をそれぞれ選ぶ（#1321 の受け入れ条件）。
///
/// 「1局=1RuleSet」（`docs/ai-devops.md`）の作法どおり、問題を出すときに Model へ焼き込み、
/// 問題の途中で設定が変わっても進行中の問題には効かない。
public struct AnzanSettings: Codable, Equatable, Sendable {
    public var digits: AnzanDigits
    public var count: AnzanCount
    public var speed: AnzanSpeed

    public init(digits: AnzanDigits, count: AnzanCount, speed: AnzanSpeed) {
        self.digits = digits
        self.count = count
        self.speed = speed
    }

    /// 初めて開いたときの既定（いちばんやさしい組）。
    public static let standard = AnzanSettings(digits: .one, count: .five, speed: .slow)

    /// 記録（自己ベスト・連続正解）を分ける区分のキー。3 軸の組ごとに 1 件。
    public var variant: String { "d\(digits.rawValue)-n\(count.rawValue)-\(speed.rawValue)" }

    /// 区分の表示名（「2桁・10個・ふつう」）。画面の見出しに使う。いまの表示言語で引く。
    public var variantLabel: String { tr("%1$@・%2$@・%3$@", digits.label, count.label, speed.label) }

    /// 記録（`GameScore.variantLabel`）に保存する区分名。保存されてハブの記録行に出るので、
    /// 表示言語によらず日本語で組む（表示の英語化は #2168）。
    public var recordVariantLabel: String {
        [digits.label(language: .japanese), count.label(language: .japanese), speed.label(language: .japanese)]
            .joined(separator: "・")  // i18n-keep: 記録に保存する区分名（表示の英語化は #2168）
    }

    /// 難しさの段。3 軸それぞれの段（0 始まり）の和で、0（全部いちばんやさしい）〜 6。
    public var rank: Int {
        (AnzanDigits.allCases.firstIndex(of: digits) ?? 0)
            + (AnzanCount.allCases.firstIndex(of: count) ?? 0)
            + (AnzanSpeed.allCases.firstIndex(of: speed) ?? 0)
    }

    /// `game_start` の `level`（#500）。3 軸の組は 27 通りあるので、段の和を 4 段階へ丸めて送る
    /// （27 通りをそのまま送ると GA4 の値の集合がこのゲームだけ膨らんで横断で読めない）。
    public var analyticsLevel: AnalyticsLevel {
        switch rank {
        case ...1:  return .beginner
        case 2...3: return .normal
        case 4...5: return .hard
        default:    return .expert
        }
    }
}

/// 中断データ。**問題そのものは復元しない**（表示のタイミングで成り立つゲームなので、途中から
/// 戻しても遊べない）。最後に選んだ難易度だけを控え、次に開いたときの初期値にする。
public struct AnzanSnapshot: Codable, Equatable, Sendable {
    public var settings: AnzanSettings

    public init(settings: AnzanSettings) {
        self.settings = settings
    }
}
