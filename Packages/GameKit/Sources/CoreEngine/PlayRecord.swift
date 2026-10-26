import Foundation

/// そのゲームの「らしさ」を1行で表すときに主役にする指標（#115）。
///
/// ゲームごとに意味のある数字が違う（2048 はスコア、マインスイーパーはタイム、将棋は勝敗）ため、
/// 保存する値は共通の `PlayRecord` に持たせ、**どれを見出しにするか**だけをこの enum で選ぶ。
/// こうするとハブとリザルトの表示ロジックを 1 か所に集約でき、ゲームごとの分岐を撒かずに済む。
public enum RecordMetric: String, Codable, Equatable, Sendable {
    /// 高いほど良い数値（2048 のスコア、ポーカー / ブラックジャックのチップ）。
    case points
    /// 短いほど良いクリアタイム（マインスイーパー・麻雀ソリティア）。
    case shortestTime
    /// 少ないほど良い手数。
    case fewestMoves
    /// 勝敗と連勝（CPU と対戦するもの）。
    case winLoss
}

/// ゲーム 1 回ぶんの成績。決着を判定した Model が `GameServices.gameDidFinish` へ渡す。
///
/// すべて任意項目で、渡された項目だけが自己ベストの判定対象になる。
public struct GameScore: Equatable, Sendable {
    /// ハブ・リザルトで見出しにする指標。
    public var metric: RecordMetric
    /// 高いほど良い数値（スコア・チップ）。
    public var points: Int?
    /// 到達した最大値（2048 の最大タイル）。高いほど良い。
    public var highestValue: Int?
    /// クリアまでの秒数。短いほど良い。**勝ち / クリアのときだけ記録する**。
    public var seconds: Int?
    /// クリアまでの手数。少ないほど良い。**勝ち / クリアのときだけ記録する**。
    public var moves: Int?
    /// 多人数対戦での最終順位（1 始まり。1 = 一番）。大富豪・いろリレーが載せる（#2606）。
    /// 勝敗（`GameOutcome`）とは別に、4 人中の 2 位と 3 位の違いを通算の平均順位に残すためのもの。
    public var place: Int?
    /// 記録を分けたい区分のキー（マインスイーパーの難易度）。nil ならゲーム単位で 1 件。
    public var variant: String?
    /// 区分の表示名（「初級」など）。ハブの 1 行に添える。
    public var variantLabel: String?
    /// この決着を Game Center のリーダーボードへ送ってよいか（#406）。
    ///
    /// **ローカルの自己ベスト（`PlayRecord`）には影響しない**。救済アイテムを使ったクリアを
    /// 全世界の順位表から外すためだけの旗で、手元の記録は使用の有無を問わず残す（#397 の
    /// 「ローカル記録は使用有無を問わず保存」）。区分（`variant`）で分けると自己ベストの行が
    /// 2 つに割れてしまうので、記録の分割とは別の軸として持つ。
    public var isLeaderboardEligible: Bool

    public init(
        metric: RecordMetric = .winLoss,
        points: Int? = nil,
        highestValue: Int? = nil,
        seconds: Int? = nil,
        moves: Int? = nil,
        place: Int? = nil,
        variant: String? = nil,
        variantLabel: String? = nil,
        isLeaderboardEligible: Bool = true
    ) {
        self.metric = metric
        self.points = points
        self.highestValue = highestValue
        self.seconds = seconds
        self.moves = moves
        self.place = place
        self.variant = variant
        self.variantLabel = variantLabel
        self.isLeaderboardEligible = isLeaderboardEligible
    }
}

/// 1 ゲーム（区分がある場合は 1 区分）ぶんの自己ベストと通算成績。
///
/// 盤面・棋譜は持たない。持つのは下の数値だけで、**プレイ回数が増えても項目数は増えない**
/// （区分ぶんだけ横に増えるが、上限は登録ゲーム数 + 難易度数で固定）。
public struct PlayRecord: Codable, Equatable, Sendable {
    /// 見出しにする指標。
    public var metric: RecordMetric
    /// 区分の表示名（マインスイーパーの「初級」など）。**保存した時点の文字列**で、言語を切り替えても
    /// 書き換わらない。画面に出す名前は `recordKey` から引き直す（`RecordFormat`・#2199）。
    public var variantLabel: String?
    /// この記録の保存先のキー（`PlayLog.recordKey`。例: `sudoku#normal`）。表示のたびに区分名を引き直すための
    /// 手がかりで、**保存はしない**（`PlayLog` が記録を渡すときに付ける）。nil なら `variantLabel` をそのまま出す。
    public var recordKey: String?
    /// 終局した回数（勝敗を問わない）。
    public var plays: Int
    public var wins: Int
    public var losses: Int
    public var draws: Int
    /// 現在の連勝数。勝ち以外（負け・引き分け）で 0 に戻る。
    public var currentStreak: Int
    /// 過去最高の連勝数。
    public var bestStreak: Int
    /// 現在の連敗数（#2614）。負けで +1、勝ち・引き分けで 0 に戻る。難易度の「階段」が一段やさしい段を勧める材料。
    ///
    /// **必ず Optional にする**（`lastPlayedAt` と同じ理由。旧データには鍵が無い）。nil は 0 連敗と同じ意味で、
    /// 連敗していない記録には鍵ごと書かない。読むときは `lossStreak` を使う。
    public var currentLossStreak: Int?
    /// 自己ベストのスコア・チップ。
    public var bestPoints: Int?
    /// 到達した最大値（2048 の最大タイル）。
    public var highestValue: Int?
    /// 最短クリアタイム（秒）。
    public var bestSeconds: Int?
    /// 最少クリア手数。
    public var fewestMoves: Int?
    /// 順位（1 始まり）の累計と、その順位を記録した回数（#2606）。平均順位 = 累計 ÷ 回数。
    ///
    /// **必ず Optional にする**（`lastPlayedAt` と同じ理由。旧データには鍵が無い）。順位を載せない決着
    /// （旧版の記録・順位を持たないゲーム）は回数に数えず、平均から外れる。2 つの整数だけなので、
    /// プレイ回数が増えても保存サイズは増えない。
    public var placeTotal: Int?
    public var placeCount: Int?
    /// 最後に決着した日時。レコメンドの「久しぶり枠」（#335）が使う。
    ///
    /// **必ず Optional にする**。旧データ（この項目が入る前に保存された JSON）には鍵が無く、
    /// 非 Optional にすると `PlayLog` のデコードが丸ごと失敗して**全記録が空に倒れる**
    /// （`PlayLog.init` の壊れた JSON へのフォールバック）。日付が無いものは
    /// 「いつ遊んだか分からないくらい前」として扱う。
    public var lastPlayedAt: Date?

    /// `recordKey` は保存しない（`PlayLog` の保存形式は変えない）。
    private enum CodingKeys: String, CodingKey {
        case metric, variantLabel, plays, wins, losses, draws, currentStreak, bestStreak, currentLossStreak
        case bestPoints, highestValue, bestSeconds, fewestMoves, placeTotal, placeCount, lastPlayedAt
    }

    public init(
        metric: RecordMetric = .winLoss,
        variantLabel: String? = nil,
        recordKey: String? = nil,
        plays: Int = 0,
        wins: Int = 0,
        losses: Int = 0,
        draws: Int = 0,
        currentStreak: Int = 0,
        bestStreak: Int = 0,
        currentLossStreak: Int? = nil,
        bestPoints: Int? = nil,
        highestValue: Int? = nil,
        bestSeconds: Int? = nil,
        fewestMoves: Int? = nil,
        placeTotal: Int? = nil,
        placeCount: Int? = nil,
        lastPlayedAt: Date? = nil
    ) {
        self.metric = metric
        self.variantLabel = variantLabel
        self.recordKey = recordKey
        self.plays = plays
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.currentStreak = currentStreak
        self.bestStreak = bestStreak
        self.currentLossStreak = currentLossStreak
        self.bestPoints = bestPoints
        self.highestValue = highestValue
        self.bestSeconds = bestSeconds
        self.fewestMoves = fewestMoves
        self.placeTotal = placeTotal
        self.placeCount = placeCount
        self.lastPlayedAt = lastPlayedAt
    }

    /// 現在の連敗数（記録が無ければ 0）。
    public var lossStreak: Int { currentLossStreak ?? 0 }

    /// 平均順位（1 始まり）。順位を記録した決着が 1 回も無ければ nil。
    public var averagePlace: Double? {
        guard let total = placeTotal, let count = placeCount, count > 0 else { return nil }
        return Double(total) / Double(count)
    }

    /// 何か 1 つでも記録があるか。何も無いゲームはハブに 1 行も出さない。
    public var hasAnyRecord: Bool {
        plays > 0
    }
}

/// 直近の 1 回で「自己ベストが更新されたか」の内訳。リザルトの「自己ベスト更新！」の判定に使う。
///
/// **同点は更新扱いにしない**（すべて狭義の大小比較）。同じスコアで何度も「更新！」が出ると
/// 表示の意味が薄れるため。
public struct RecordUpdate: Equatable, Sendable {
    public var points: Bool
    public var highestValue: Bool
    public var seconds: Bool
    public var moves: Bool
    public var streak: Bool

    public init(
        points: Bool = false,
        highestValue: Bool = false,
        seconds: Bool = false,
        moves: Bool = false,
        streak: Bool = false
    ) {
        self.points = points
        self.highestValue = highestValue
        self.seconds = seconds
        self.moves = moves
        self.streak = streak
    }

    /// 1 つでも更新されたか。
    public var isNewBest: Bool {
        points || highestValue || seconds || moves || streak
    }
}

/// 決着 1 回ぶんの記録結果。更新後の記録と、その回の更新内訳をまとめて Model に返す。
public struct RecordResult: Equatable, Sendable {
    public let record: PlayRecord
    public let update: RecordUpdate

    public init(record: PlayRecord, update: RecordUpdate) {
        self.record = record
        self.update = update
    }
}

public extension PlayRecord {
    /// 自分（古い側）を `newer`（新しい側）に畳み込んだ記録を返す（#383）。
    ///
    /// キーの付け替え（区分の後付け）で新旧2件に割れてしまった記録を1件に戻すためのもの。
    /// 通算は足し合わせ、自己ベストは良いほうを採り、「今」を表す項目
    /// （見出しの指標・区分名・現在の連勝）は**新しい側を優先する**。
    /// 古い記録の連勝は既に途切れているため、足したり大きいほうを採ったりしない。
    func merged(into newer: PlayRecord) -> PlayRecord {
        var result = newer
        result.plays  += plays
        result.wins   += wins
        result.losses += losses
        result.draws  += draws
        result.bestStreak = max(bestStreak, newer.bestStreak)
        result.bestPoints   = Self.better(bestPoints, newer.bestPoints, by: >)
        result.highestValue = Self.better(highestValue, newer.highestValue, by: >)
        result.bestSeconds  = Self.better(bestSeconds, newer.bestSeconds, by: <)
        result.fewestMoves  = Self.better(fewestMoves, newer.fewestMoves, by: <)
        if let count = placeCount, count > 0 {
            result.placeTotal = (newer.placeTotal ?? 0) + (placeTotal ?? 0)
            result.placeCount = (newer.placeCount ?? 0) + count
        }
        if let mine = lastPlayedAt, mine > (newer.lastPlayedAt ?? .distantPast) {
            result.lastPlayedAt = mine
        }
        return result
    }

    /// 「片方だけある」を落とさずに良いほうを選ぶ。両方あるときだけ `isBetter` で比べる。
    private static func better(_ a: Int?, _ b: Int?, by isBetter: (Int, Int) -> Bool) -> Int? {
        guard let a else { return b }
        guard let b else { return a }
        return isBetter(a, b) ? a : b
    }

    /// 決着 1 回を既存の記録に反映した結果を返す純粋関数。永続化から切り離してテストできるようにする。
    ///
    /// - Parameters:
    ///   - previous: それまでの記録。初回は nil。
    ///   - at: 決着した日時（#335 の「久しぶり枠」に使う）。テストから固定できるよう引数で受ける。
    /// - Note: タイムと手数は**勝ち / クリアのときだけ**取り込む。負けた局の経過時間を
    ///   「最短クリアタイム」に混ぜると、投了した瞬間が常に最短になってしまうため。
    static func applying(
        outcome: GameOutcome,
        score: GameScore,
        to previous: PlayRecord?,
        at date: Date = Date()
    ) -> RecordResult {
        var record = previous ?? PlayRecord()
        var update = RecordUpdate()

        // 見出しの指標と区分名は常に最新の申告で上書きする（表示名の変更に追従するため）。
        record.metric = score.metric
        if let label = score.variantLabel { record.variantLabel = label }

        record.plays += 1
        // 前後する日時で呼ばれても巻き戻らない（端末の時計がずれて補正されたときなど）。
        // 「最後に遊んだのはいつか」を古いほうに倒すと、久しぶり枠が実際より古い候補として拾う。
        if date > (record.lastPlayedAt ?? .distantPast) {
            record.lastPlayedAt = date
        }
        switch outcome {
        case .win:
            record.wins += 1
            record.currentStreak += 1
            record.currentLossStreak = nil
            if record.currentStreak > record.bestStreak {
                record.bestStreak = record.currentStreak
                // 初勝利（1 連勝）も「更新」ではあるが、演出としては煩いので 2 連勝以上に絞る。
                update.streak = record.currentStreak >= 2
            }
        case .loss:
            record.losses += 1
            record.currentStreak = 0
            record.currentLossStreak = record.lossStreak + 1
        case .draw:
            record.draws += 1
            // 引き分けは「連勝」ではないため連勝は途切れる。
            record.currentStreak = 0
            record.currentLossStreak = nil
        }

        // 順位は勝敗とは別に累計する（1 位未満は不正値として取り込まない）。
        if let place = score.place, place >= 1 {
            record.placeTotal = (record.placeTotal ?? 0) + place
            record.placeCount = (record.placeCount ?? 0) + 1
        }

        // 初回は記録として残すが、0 点では「更新」と言わない（#1067）。言うと共有ボタン（#1043）が
        // 「自己ベスト 0」を外へ出す。チャリンコおじさんの `isNewBestDistance`（#983）と同じ物差し。
        if let points = score.points, points > (record.bestPoints ?? Int.min) {
            update.points = record.bestPoints != nil || points > 0
            record.bestPoints = points
        }
        if let highest = score.highestValue, highest > (record.highestValue ?? Int.min) {
            update.highestValue = record.highestValue != nil || highest > 0
            record.highestValue = highest
        }
        if outcome == .win {
            if let seconds = score.seconds, seconds < (record.bestSeconds ?? Int.max) {
                record.bestSeconds = seconds
                update.seconds = true
            }
            if let moves = score.moves, moves < (record.fewestMoves ?? Int.max) {
                record.fewestMoves = moves
                update.moves = true
            }
        }

        return RecordResult(record: record, update: update)
    }
}

/// 記録を表示言語の 1 行に整形する。ハブのカードとリザルトで同じ表記を使うためのもの。
///
/// **数字・単位・「ベスト」「最短」などは、語順ごと文言の表の書式で組む**（多言語⑤ #2168）。
/// 日本語は「最少 24手」「3勝5敗・2連勝中」、英語は「Best: 24 moves」「3W 5L · 2-win streak」のように
/// 言語ごとに語順と単位が変わるため、文字列をつなげて組まない。日本語の表記は #2168 の前と 1 文字も変えない
/// （`PlayRecordTests` が日本語の全表記を縛る）。
///
/// - 各関数の `language` は省略時にいまの表示言語（`AppLanguageStore.shared`）。テストは明示して引く。
/// - 桁区切りの数は `number` で整形してから `%@` で渡す。英語の単数・複数は、その整形済みの数でも選べる
///   （`StringTable` が `1,234` のような数字の文字列も数として扱う）。
/// - 区分の表示名は、記録の保存先のキー（`recordKey`）から表示のたびに引き直す（`RecordVariantLabels`・#2199）。
///   キーが無い・引けない記録だけ、保存された `variantLabel` をそのまま出す。
public enum RecordFormat {
    /// 秒数を `M:SS` / `H:MM:SS` に整形する。言語によらず同じ表記。
    public static func time(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%d:%02d", m, sec)
    }

    /// 記録に添える区分名。キーから表示言語で引き直し、引けなければ保存済みの文字列。
    static func variantLabel(of record: PlayRecord, language: AppLanguage?) -> String? {
        guard let stored = record.variantLabel else { return nil }
        return record.recordKey.flatMap { RecordVariantLabels.label(recordKey: $0, language: language) } ?? stored
    }

    /// 3 桁区切りの数値（12,340）。日本語・英語とも同じ表記。
    public static func number(_ value: Int) -> String {
        let digits = String(abs(value))
        var grouped = ""
        for (offset, ch) in digits.enumerated() {
            if offset > 0, (digits.count - offset) % 3 == 0 { grouped.append(",") }
            grouped.append(ch)
        }
        return (value < 0 ? "-" : "") + grouped
    }

    /// 順位（1 始まり）。日本語は「1位」、英語は序数「1st」「2nd」「3rd」「4th」「11th」「21st」。
    ///
    /// 各ゲームの順位の表示（麻雀・ころころリレー・柵越えの順位表など）はこれを使う。
    /// 英語の序数は数で接尾辞が 4 通りに分かれ、文言の表の複数形（one / other）では表せないのでここで組む。
    /// 表の「%@位」の英語（`%@`）は検査のために置いているだけで、英語のときは引かない。
    public static func rank(_ place: Int, language: AppLanguage? = nil) -> String {
        let language = language ?? AppLanguageStore.shared.language
        switch language {
        case .japanese: return tr("%@位", number(place), language: language)
        case .english: return number(place) + ordinalSuffix(place)
        }
    }

    /// 英語の序数の接尾辞（1st の st）。11〜13 は th（11th・112th）。
    static func ordinalSuffix(_ place: Int) -> String {
        let n = abs(place)
        if (11...13).contains(n % 100) { return "th" }
        switch n % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    /// ハブのゲームカードに出す 1 行。記録がまだ無ければ nil（＝何も出さない）。
    ///
    /// - Parameters:
    ///   - records: そのゲームの全区分の記録（マインスイーパーなら難易度 3 件）。
    ///   - gameID: そのゲームの ID。**チャリンコおじさん（`runner`）だけ**、本編の記録を
    ///     「2-3 まで到達」の形にする（#931）。他のゲームは指標だけで表記が決まるので省略できる。
    ///   - language: 表示言語。省略時はいまの表示言語。
    public static func hubLine(_ records: [PlayRecord], gameID: String? = nil, language: AppLanguage? = nil) -> String? {
        let played = records.filter(\.hasAnyRecord)
        guard let metric = played.first?.metric else { return nil }

        switch metric {
        case .shortestTime:
            // 区分が複数あるときは一番速い記録を代表にする（1 行に収めるため）。
            guard let best = played.compactMap({ r in r.bestSeconds.map { ($0, variantLabel(of: r, language: language)) } })
                .min(by: { $0.0 < $1.0 }) else { return nil }
            if let label = best.1 {
                return tr("最短 %1$@（%2$@）", time(best.0), label, language: language)
            }
            // 1 行（SE・最大文字サイズでも折り返さない長さ）に収めるため、手数は出さず連勝だけ添える（#2597）。
            return withBestStreak(tr("最短 %@", time(best.0), language: language),
                                  streak: played.map(\.bestStreak).max() ?? 0, language: language)
        case .points:
            // 区分が複数あるときは**区分なし（本編）の記録を代表**にする。チャリンコおじさんは
            // 本編＝到達ステージ数（区分なし）、エンドレス＝走行距離 m（区分あり）で桁が違い、
            // 最大値を取るとエンドレスを 1 回走っただけで「ベスト 12」が「ベスト 3,412」に化ける（#675）。
            // 本編の記録がまだ無ければ従来どおり最大値。
            if let base = played.first(where: { $0.variantLabel == nil }), let points = base.bestPoints {
                // チャリンコおじさんの本編は「どこまで到達したか」が記録の主役（#931。秒数は廃止）。
                if gameID == runnerGameID { return runnerStageLine(clearedStage: points, language: language) }
                return bestLine(points, highlight: highlight(gameID: gameID, value: base.highestValue, language: language),
                                language: language)
            }
            guard let best = played.compactMap(\.bestPoints).max() else { return nil }
            return bestLine(best, highlight: highlight(gameID: gameID, value: played.compactMap(\.highestValue).max(),
                                                       language: language), language: language)
        case .fewestMoves:
            guard let best = played.compactMap(\.fewestMoves).min() else { return nil }
            return tr("最少 %@手", number(best), language: language)
        case .winLoss:
            let streak = played.map(\.currentStreak).max() ?? 0
            let base = withBestSeconds(withAveragePlace(winLossText(played, language: language), played, language: language),
                                       played.compactMap(\.bestSeconds).min(), language: language)
            return streak >= 2 ? tr("%1$@・%2$lld連勝中", base, streak, language: language) : base
        }
    }

    /// 最高連勝を末尾に添える。`.winLoss` と同じ閾値（2 連勝以上）に満たなければ行をそのまま返す。
    private static func withBestStreak(_ line: String, streak: Int, language: AppLanguage?) -> String {
        streak >= 2 ? tr("%1$@・最高%2$lld連勝", line, streak, language: language) : line
    }

    /// ポーカー・ブラックジャックの ID（`PokerModel.gameID` / `BlackjackModel.gameID`）。Core からは参照できないので文字列で持つ。
    static let pokerGameID = "poker"
    static let blackjackGameID = "blackjack"

    /// `PokerHandRank` の序数（`rawValue`・0 始まり）に対応する役名。食い違わないことは `GamePokerTests` が突き合わせる。
    static func pokerRankName(_ rawValue: Int, language: AppLanguage?) -> String? {
        let names = [tr("ハイカード", language: language), tr("ワンペア", language: language), tr("ツーペア", language: language),
                     tr("スリーカード", language: language), tr("ストレート", language: language), tr("フラッシュ", language: language),
                     tr("フルハウス", language: language), tr("フォーカード", language: language),
                     tr("ストレートフラッシュ", language: language), tr("ロイヤルフラッシュ", language: language)]
        return names.indices.contains(rawValue) ? names[rawValue] : nil
    }

    /// 記録の保存先のキー（`sudoku#normal` 形式）から、ゲーム ID を取り出す。キーが無ければ nil。
    static func gameID(of record: PlayRecord) -> String? {
        record.recordKey.map { String($0.prefix { $0 != "#" }) }
    }

    /// ポーカーの「いちばん強い役」・ブラックジャックの「最高連勝」を、`PlayRecord.highestValue` から読んだ短い表記（#2591）。
    /// 対象外のゲーム・値が無い／連勝 0 のときは nil（見た目を変えない）。
    static func highlight(gameID: String?, value: Int?, language: AppLanguage?) -> String? {
        guard let value else { return nil }
        switch gameID {
        case pokerGameID: return pokerRankName(value, language: language)
        case blackjackGameID: return value >= 1 ? tr("最高%lld連勝", value, language: language) : nil
        default: return nil
        }
    }

    private static func bestLine(_ points: Int, highlight: String?, language: AppLanguage?) -> String {
        guard let highlight else { return tr("ベスト %@", number(points), language: language) }
        return tr("ベスト %1$@・%2$@", number(points), highlight, language: language)
    }

    /// チャリンコおじさんの ID（`RunnerModel.gameID`）。Core からは GameRunner を参照できないので
    /// 文字列で持つ（`GameCenterLeaderboard.leaderboardID(gameID:variant:)` と同じ扱い）。
    static let runnerGameID = "runner"
    /// チャリンコおじさんのステージ数と、1 つの世界が受け持つ面数（`RunnerRules.stageCount` /
    /// `RunnerWorld.stagesPerWorld` の写し。Core からは GameRunner を参照できないので値で持つ）。
    /// 食い違わないことは `GameRunnerTests`（`RunnerHubLineTests`）が全面について突き合わせる。
    static let runnerStageCount = 60
    static let runnerStagesPerWorld = 6

    /// チャリンコおじさんの本編の 1 行（#931）。
    ///
    /// 記録の `bestPoints` は**クリアした面の番号**（`RunnerModel.clearStage` が送る値。順位表
    /// `asobiba.runner.stage` と同じ）で、画面に出すのはその次＝到達した面「2-3 まで到達」。
    /// 最終面をクリアしていれば「全 N 面クリア」（N は `runnerStageCount`）。面の表記「世界-面」は
    /// `RunnerWorld.code(forStage:)` と同じ割り方（`runnerStagesPerWorld` 面ずつ）。
    public static func runnerStageLine(clearedStage: Int, language: AppLanguage? = nil) -> String {
        let cleared = max(0, clearedStage)
        guard cleared < runnerStageCount else { return tr("全 %lld 面クリア", runnerStageCount, language: language) }
        let reached = cleared + 1
        let world = (reached - 1) / runnerStagesPerWorld + 1
        let index = (reached - 1) % runnerStagesPerWorld + 1
        return tr("%1$lld-%2$lld まで到達", world, index, language: language)
    }

    /// 「3勝5敗」「1勝2敗1分」の表記。引き分けは 0 のときだけ省く。
    ///
    /// 大富豪は4人中1位が勝ち・最下位が負け・**中位は引き分け**扱いのため、勝ちも負けも 0 のまま
    /// 引き分けだけが積み上がる状態が普通に起きる。勝敗だけを見て「記録なし」に倒すと、
    /// 遊んでいるのにハブに何も出ないゲームができてしまう。
    private static func winLossText(_ records: [PlayRecord], language: AppLanguage?) -> String {
        let wins = records.reduce(0) { $0 + $1.wins }
        let losses = records.reduce(0) { $0 + $1.losses }
        let draws = records.reduce(0) { $0 + $1.draws }
        return draws > 0
            ? tr("%1$lld勝%2$lld敗%3$lld分", wins, losses, draws, language: language)
            : tr("%1$lld勝%2$lld敗", wins, losses, language: language)
    }

    /// 順位を記録した決着があれば、勝敗の後ろに「平均2.1位」を添える（#2606）。無ければそのまま。
    ///
    /// 区分が複数ある記録は累計を足してから割る（区分ごとの平均を平均しない）。
    private static func withAveragePlace(_ line: String, _ records: [PlayRecord], language: AppLanguage?) -> String {
        let count = records.reduce(0) { $0 + ($1.placeCount ?? 0) }
        guard count > 0 else { return line }
        let total = records.reduce(0) { $0 + ($1.placeTotal ?? 0) }
        let average = String(format: "%.1f", Double(total) / Double(count))
        return tr("%1$@・平均%2$@位", line, average, language: language)
    }

    /// ノルマ到達までの最速秒数を記録しているゲーム（カードしりとり・#2609）だけ、勝敗の後ろに「最速42秒」を添える。無ければそのまま。
    private static func withBestSeconds(_ line: String, _ seconds: Int?, language: AppLanguage?) -> String {
        guard let seconds else { return line }
        return tr("%1$@・最速%2$lld秒", line, seconds, language: language)
    }

    /// リザルトに出す 1 行（そのゲームの自己ベスト）。記録が無ければ nil。
    public static func resultLine(_ record: PlayRecord, language: AppLanguage? = nil) -> String? {
        guard record.hasAnyRecord else { return nil }
        switch record.metric {
        case .shortestTime:
            guard let best = record.bestSeconds else {
                // まだ一度もクリアしていない。挑戦した回数だけを出す（「記録なし」で終わらせない）。
                return tr("クリア記録なし（%lld回挑戦）", record.plays, language: language)
            }
            var line = tr("最短タイム %1$@・%2$lld回クリア", time(best), record.wins, language: language)
            // 手数を記録しているゲームだけ「最少 n手」、2 連勝以上なら「最高n連勝」を添える（#2597）。
            if let moves = record.fewestMoves {
                line = tr("%1$@・最少 %2$@手", line, number(moves), language: language)
            }
            return withBestStreak(line, streak: record.bestStreak, language: language)
        case .points:
            guard let best = record.bestPoints else { return nil }
            // ポーカー・ブラックジャックの highestValue は「役」「連勝」で、数としての「最大」ではない。
            // 出せない値（連勝 0）のときも「最大 0」には倒さない。
            let id = gameID(of: record)
            if id == pokerGameID || id == blackjackGameID {
                guard let text = highlight(gameID: id, value: record.highestValue, language: language) else {
                    return tr("自己ベスト %@", number(best), language: language)
                }
                return tr("自己ベスト %1$@（%2$@）", number(best), text, language: language)
            }
            if let highest = record.highestValue {
                return tr("自己ベスト %1$@（最大 %2$@）", number(best), number(highest), language: language)
            }
            return tr("自己ベスト %@", number(best), language: language)
        case .fewestMoves:
            guard let best = record.fewestMoves else { return nil }
            return tr("最少手数 %@手", number(best), language: language)
        case .winLoss:
            let base = tr("通算 %@", withBestSeconds(withAveragePlace(winLossText([record], language: language), [record],
                                                                     language: language),
                                                    record.bestSeconds, language: language),
                          language: language)
            return record.bestStreak >= 2 ? tr("%1$@・最高%2$lld連勝", base, record.bestStreak, language: language) : base
        }
    }

    /// 自己ベストを更新したリザルトから共有するときの文言（#1043）。記録が無ければ nil。
    ///
    /// **記録を前面に出す**（#1043 の決裁）。アプリ名だけの文言は設定画面の「アプリをシェア」が
    /// 既に持っていて、受け手に「何点取れるか試したい」という理由を渡せないため。
    /// 2 行目はリザルトの 1 行（`resultLine`）と同じ表記にし、画面で見た記録がそのまま届くようにする。
    /// App Store の URL は文言に含めない（共有シート側が別の項目として添える）。
    ///
    /// - Parameter title: ハブに出しているゲームの表示名（`GameModule.title`）。
    public static func shareMessage(title: String, record: PlayRecord, language: AppLanguage? = nil) -> String? {
        guard let line = resultLine(record, language: language) else { return nil }
        // 区分ごとに記録を分けているゲーム（マインスイーパーの難易度）は、どの区分の記録かを添える。
        if let label = variantLabel(of: record, language: language) {
            return tr("あそびばの「%1$@」（%2$@）で記録更新！\n%3$@", title, label, line, language: language)
        }
        return tr("あそびばの「%1$@」で記録更新！\n%2$@", title, line, language: language)
    }
}
