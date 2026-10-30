import Foundation

/// こいこいの出来役（#495）。
///
/// 役の点は「文（もん）」で数える。定義と点は `docs/hanafuda-koikoi-rules.md` の照合表に対応し、
/// テスト（`YakuTests`）が表と 1 対 1 で突き合わせる。
public enum HanafudaYaku: String, CaseIterable, Sendable, Equatable, Codable {
    case goko          // 五光
    case shiko         // 四光
    case ameShiko      // 雨四光
    case sanko         // 三光
    case inoshikacho   // 猪鹿蝶
    case akatan        // 赤短
    case aotan         // 青短
    case tsukimizake   // 月見酒
    case hanamizake    // 花見酒
    case tane          // タネ
    case tan           // タン
    case kasu          // カス

    /// 役名（表示言語で引く・#2166）。判定・保存は `rawValue` で行い、この文字列は画面と読み上げにだけ使う。
    public var name: String {
        switch self {
        case .goko:        return tr("五光")
        case .shiko:       return tr("四光")
        case .ameShiko:    return tr("雨四光")
        case .sanko:       return tr("三光")
        case .inoshikacho: return tr("猪鹿蝶")
        case .akatan:      return tr("赤短")
        case .aotan:       return tr("青短")
        case .tsukimizake: return tr("月見酒")
        case .hanamizake:  return tr("花見酒")
        case .tane:        return tr("タネ")
        case .tan:         return tr("タン")
        case .kasu:        return tr("カス")
        }
    }

    /// 1 行に収める所（取り札の横の役の行・早見表の名前の列）に出す短い役名（#2166）。
    /// 英語の `name` は「ローマ字 (英語の説明)」なので、括弧の前のローマ字だけを残す。日本語は `name` のまま。
    public var shortName: String {
        let full = name
        guard let paren = full.range(of: " (") else { return full }
        return String(full[..<paren.lowerBound])
    }

    /// 役早見表に出す成立条件の説明。
    public var requirement: String {
        switch self {
        case .goko:        return tr("光札 5 枚すべて")
        case .shiko:       return tr("柳を除く光札 4 枚")
        case .ameShiko:    return tr("柳を含む光札 4 枚")
        case .sanko:       return tr("柳を除く光札 3 枚")
        case .inoshikacho: return tr("萩に猪・紅葉に鹿・牡丹に蝶")
        case .akatan:      return tr("松・梅・桜の赤短 3 枚")
        case .aotan:       return tr("牡丹・菊・紅葉の青短 3 枚")
        case .tsukimizake: return tr("芒に月 ＋ 菊に盃")
        case .hanamizake:  return tr("桜に幕 ＋ 菊に盃")
        case .tane:        return tr("タネ札 5 枚（1 枚増えるごとに ＋1 文）")
        case .tan:         return tr("短冊札 5 枚（1 枚増えるごとに ＋1 文）")
        case .kasu:        return tr("カス札 10 枚（1 枚増えるごとに ＋1 文）")
        }
    }

    /// 基本の文数（枚数で伸びるタネ・タン・カスは 5 枚 / 10 枚ちょうどのときの値）。
    public var basePoints: Int {
        switch self {
        case .goko:        return 10
        case .shiko:       return 8
        case .ameShiko:    return 7
        case .sanko:       return 5
        case .inoshikacho: return 5
        case .akatan:      return 5
        case .aotan:       return 5
        case .tsukimizake: return 5
        case .hanamizake:  return 5
        case .tane, .tan, .kasu: return 1
        }
    }

    /// 枚数で決まる役（タネ・タン・カス）が成立する枚数。札の組み合わせで決まる役は nil。
    /// 判定（`HanafudaRules`）と早見表の「n枚から」の両方がここを引く。
    public var countThreshold: Int? {
        switch self {
        case .tane, .tan:  return 5
        case .kasu:        return 10
        default:           return nil
        }
    }

    /// 早見表に並べる順（強い役から）。
    public static let displayOrder: [HanafudaYaku] = [
        .goko, .shiko, .ameShiko, .sanko, .inoshikacho, .akatan, .aotan,
        .tsukimizake, .hanamizake, .tane, .tan, .kasu,
    ]
}

/// 成立した役 1 つ。
public struct HanafudaYakuHit: Equatable, Sendable, Codable {
    public let yaku: HanafudaYaku
    /// 実際の文数（タネ 6 枚なら 2 のように、枚数ぶん伸びた後の値）。
    public let points: Int

    public init(yaku: HanafudaYaku, points: Int) {
        self.yaku = yaku
        self.points = points
    }

    public var name: String { yaku.name }
}

/// 1 局に焼き込むルール設定（#495。「1 局 = 1 RuleSet」原則）。
///
/// 対局の途中で設定を変えても**その局には効かない**。局の開始時にこの値を作って
/// スナップショットへ書き、復元時もそれを使う。
public struct HanafudaOptions: Equatable, Sendable, Codable {
    /// 月見酒・花見酒を採用するか。ローカルルール扱いのため開始時に選べる。**既定は ON**。
    public var sakeYakuEnabled: Bool
    /// 1 試合の局数（6 か 12）。
    public var rounds: Int
    /// CPU の強さ。
    public var difficulty: HanafudaDifficulty

    public init(
        sakeYakuEnabled: Bool = true,
        rounds: Int = 6,
        difficulty: HanafudaDifficulty = .normal
    ) {
        self.sakeYakuEnabled = sakeYakuEnabled
        self.rounds = HanafudaOptions.allowedRounds.contains(rounds) ? rounds : 6
        self.difficulty = difficulty
    }

    /// 選べる局数。
    public static let allowedRounds = [6, 12]

    /// 自己ベスト・通算成績を分けて数えるための区分キー（`GameScore.variant`・#827）。
    ///
    /// 既定（6 局・酒の役あり・普通）は **nil のまま**にする。ここに文字列を入れると記録の保存先が
    /// `hanafuda` から `hanafuda#…` に変わり、これまでの自己ベストがどこからも参照されなくなる。
    /// 既定と違う軸だけを `-` でつなぐ（例: 12 局・酒の役なし・弱 → `r12-nosake-easy`）。
    public var recordVariant: String? {
        let parts = variantParts(rounds: "r\(rounds)", noSake: "nosake", difficulty: difficulty.rawValue)
        return parts.isEmpty ? nil : parts.joined(separator: "-")
    }

    /// ハブ・リザルトの記録行に添える区分名。既定は従来どおり添えない。
    /// 表示言語で引く（#2166）。記録に残るのは保存した時点の言語の文字列。
    public var recordVariantLabel: String? {
        let parts = variantParts(rounds: tr("%lld局", rounds), noSake: tr("酒の役なし"),
                                 difficulty: tr("CPU%@", difficulty.label))
        return parts.isEmpty ? nil : parts.joined(separator: tr("・"))
    }

    /// Game Center のリーダーボードへ送ってよいか。
    ///
    /// **順位表は既定ルール固定**（1局=1RuleSet 規約 4）。12 局戦は 6 局戦のおよそ倍の文数が出るうえ、
    /// 酒の役の有無・CPU の強さでも文数の出方が変わるので、同じ表に混ぜると「どのルールで遊んだか」の
    /// 表になる。既定外の自己ベストは `recordVariant` でローカルに別枠管理する。
    public var isLeaderboardEligible: Bool {
        self == HanafudaOptions()
    }

    /// 既定と違う軸の表記だけを、局数 → 酒の役 → 強さの順に並べる。
    private func variantParts(rounds: String, noSake: String, difficulty: String) -> [String] {
        let standard = HanafudaOptions()
        var parts: [String] = []
        if self.rounds != standard.rounds { parts.append(rounds) }
        if sakeYakuEnabled != standard.sakeYakuEnabled { parts.append(noSake) }
        if self.difficulty != standard.difficulty { parts.append(difficulty) }
        return parts
    }
}

/// CPU の強さ（#495）。
public enum HanafudaDifficulty: String, CaseIterable, Sendable, Equatable, Codable {
    case easy, normal, hard

    public var label: String {
        switch self {
        case .easy:   return tr("かんたん")
        case .normal: return tr("ふつう")
        case .hard:   return tr("むずかしい")
        }
    }

    /// 開始シートに出す強さの説明（#2803）。`HanafudaAI` の中身と一致させる
    /// （かんたん = 無作為に取る・こいこいしない／ふつう = 役の文数で選ぶ／むずかしい = 相手の役の芽も見る）。
    public var detail: String {
        switch self {
        case .easy:   return tr("札を無作為に選ぶ・こいこいしない")
        case .normal: return tr("役を狙う・7文までこいこい")
        case .hard:   return tr("相手の役も阻む・慎重にこいこい")
        }
    }
}

// MARK: - 役の判定

public enum HanafudaScoring {

    /// 取り札から成立している役をすべて求める（純粋関数）。
    ///
    /// - 光札の役（五光 / 四光 / 雨四光 / 三光）は**互いに排他**で、最も高い 1 つだけを返す。
    /// - 赤短・青短は猪鹿蝶と同じく**重複して数える**（赤短の 3 枚は「タン」にも数える）。
    ///   これが標準ルールで、除外すると赤短だけで止まって「タン」が伸びなくなる。
    /// - 月見酒・花見酒は `options.sakeYakuEnabled` が false のとき数えない。
    ///   このとき菊に盃は**タネ札としてだけ**働く（札そのものは変わらない）。
    public static func yaku(for captured: [HanafudaCard], options: HanafudaOptions) -> [HanafudaYakuHit] {
        var hits: [HanafudaYakuHit] = []
        let ids = Set(captured.map(\.id))

        // 光札。強い順に 1 つだけ採る。
        let hikari = captured.filter { $0.kind == .hikari }
        let hasRain = ids.contains(HanafudaCard.rainManID)
        let brightWithoutRain = hikari.count - (hasRain ? 1 : 0)
        if hikari.count == 5 {
            hits.append(HanafudaYakuHit(yaku: .goko, points: HanafudaYaku.goko.basePoints))
        } else if hikari.count == 4 {
            let yaku: HanafudaYaku = hasRain ? .ameShiko : .shiko
            hits.append(HanafudaYakuHit(yaku: yaku, points: yaku.basePoints))
        } else if brightWithoutRain >= 3 {
            hits.append(HanafudaYakuHit(yaku: .sanko, points: HanafudaYaku.sanko.basePoints))
        }

        // 猪鹿蝶。
        if HanafudaCard.inoshikachoIDs.isSubset(of: ids) {
            hits.append(HanafudaYakuHit(yaku: .inoshikacho, points: HanafudaYaku.inoshikacho.basePoints))
        }

        // 赤短・青短。
        let ribbons = captured.compactMap(\.ribbon)
        if ribbons.filter({ $0 == .redPoem }).count == 3 {
            hits.append(HanafudaYakuHit(yaku: .akatan, points: HanafudaYaku.akatan.basePoints))
        }
        if ribbons.filter({ $0 == .blue }).count == 3 {
            hits.append(HanafudaYakuHit(yaku: .aotan, points: HanafudaYaku.aotan.basePoints))
        }

        // 酒の役。
        if options.sakeYakuEnabled, ids.contains(HanafudaCard.sakeCupID) {
            if ids.contains(HanafudaCard.moonID) {
                hits.append(HanafudaYakuHit(yaku: .tsukimizake, points: HanafudaYaku.tsukimizake.basePoints))
            }
            if ids.contains(HanafudaCard.curtainID) {
                hits.append(HanafudaYakuHit(yaku: .hanamizake, points: HanafudaYaku.hanamizake.basePoints))
            }
        }

        // 枚数で伸びる役。
        appendCountYaku(&hits, count: captured.filter { $0.kind == .tane }.count, yaku: .tane)
        appendCountYaku(&hits, count: captured.filter { $0.kind == .tanzaku }.count, yaku: .tan)
        appendCountYaku(&hits, count: captured.filter { $0.kind == .kasu }.count, yaku: .kasu)

        return hits
    }

    private static func appendCountYaku(
        _ hits: inout [HanafudaYakuHit], count: Int, yaku: HanafudaYaku
    ) {
        guard let threshold = yaku.countThreshold, count >= threshold else { return }
        hits.append(HanafudaYakuHit(yaku: yaku, points: 1 + (count - threshold)))
    }

    /// 役の合計文数。
    public static func points(for captured: [HanafudaCard], options: HanafudaOptions) -> Int {
        yaku(for: captured, options: options).reduce(0) { $0 + $1.points }
    }

    /// あがった側の最終得点。基本点に倍率を掛ける。
    ///
    /// - 7 文以上は 2 倍（標準ルール）。
    /// - 相手がこいこいを宣言していたら 2 倍（こいこい返し）。宣言**回数**ではなく
    ///   「1 度でも宣言したか」で決まる。
    /// - 両方成立したら 4 倍（乗算）。
    public static func finalScore(base: Int, opponentDeclaredKoiKoi: Bool) -> Int {
        guard base > 0 else { return 0 }
        var multiplier = 1
        if base >= sevenMonThreshold { multiplier *= 2 }
        if opponentDeclaredKoiKoi { multiplier *= 2 }
        return base * multiplier
    }

    /// 「7 文以上で 2 倍」の境目。
    public static let sevenMonThreshold = 7

    /// 最終得点にどの倍率が掛かったかの内訳（リザルトの説明に使う）。
    ///
    /// **返すのは日本語の原文**（局の結果ごと中断データに保存されるため、言語で変えない）。
    /// 画面と読み上げには `reasonLabel(_:)` で表示言語の文言にしてから出す（#2166）。
    public static func multiplierReasons(base: Int, opponentDeclaredKoiKoi: Bool) -> [String] {
        var reasons: [String] = []
        if base >= sevenMonThreshold { reasons.append("7文以上で2倍") }  // i18n-keep: 中断データに保存する倍率の理由（表示は reasonLabel で訳す）
        if opponentDeclaredKoiKoi { reasons.append("こいこい返しで2倍") }  // i18n-keep: 中断データに保存する倍率の理由（表示は reasonLabel で訳す）
        return reasons
    }

    /// `multiplierReasons` の 1 項目を表示言語の文言にする（#2166）。知らない文字列はそのまま返す。
    public static func reasonLabel(_ reason: String) -> String {
        switch reason {
        case "7文以上で2倍": return tr("7文以上で2倍")  // i18n-keep: 中断データに保存する倍率の理由（表示は reasonLabel で訳す）
        case "こいこい返しで2倍": return tr("こいこい返しで2倍")  // i18n-keep: 中断データに保存する倍率の理由（表示は reasonLabel で訳す）
        default: return reason
        }
    }
}
