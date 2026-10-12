import Foundation
import Testing
@testable import CoreEngine

/// 数字・単位・記録の表示を言語ごとの語順にした（多言語⑤ #2168）ことの検査。
///
/// - 英語: ハブの 1 行・リザルトの 1 行・共有の文言・順位の表記が、語順と単数・複数まで含めて英語になること。
/// - 日本語: #2168 の前の実装（下の `LegacyJapaneseRecordFormat`。文字列をつなげて組んでいた版の写し）と、
///   **あらゆる記録の組み合わせで 1 文字も変わらない**こと。
@Suite("記録の表示の多言語（#2168）")
struct RecordFormatLocalizationTests {
    // MARK: - 日本語は 1 文字も変わらない

    /// 総当たりに使う記録。指標・区分名・勝敗・連勝・ベストの有無と桁を組み合わせる。
    static var sampleRecords: [PlayRecord] {
        var records: [PlayRecord] = []
        let metrics: [RecordMetric] = [.points, .shortestTime, .fewestMoves, .winLoss]
        let labels: [String?] = [nil, "初級", "荷運びモード"]
        let counts = [0, 1, 2, 3, 12, 1_234]
        let values: [Int?] = [nil, 0, 1, 7, 59, 83, 3_600, 3_725, 12_340, 1_234_567]
        for metric in metrics {
            for label in labels {
                for plays in [0, 1, 5, 1_500] {
                    for wins in counts where wins <= max(plays, 1) {
                        for value in values {
                            records.append(PlayRecord(
                                metric: metric, variantLabel: label, plays: plays,
                                wins: wins, losses: plays / 3, draws: plays % 4 == 0 ? 0 : plays % 4,
                                currentStreak: wins % 4, bestStreak: wins,
                                bestPoints: value, highestValue: value.map { $0 * 2 },
                                bestSeconds: value, fewestMoves: value
                            ))
                        }
                    }
                }
            }
        }
        return records
    }

    @Test("ハブ・リザルト・共有の 1 行は、日本語では #2168 の前と 1 文字も変わらない")
    func japaneseIsUnchanged() {
        let records = Self.sampleRecords
        #expect(records.count > 1_000, "総当たりの組み合わせが少なすぎる")
        for record in records {
            #expect(RecordFormat.resultLine(record, language: .japanese) == LegacyJapaneseRecordFormat.resultLine(record))
            #expect(RecordFormat.shareMessage(title: "2048", record: record, language: .japanese)
                    == LegacyJapaneseRecordFormat.shareMessage(title: "2048", record: record))
            for gameID in [nil, "runner", "2048"] {
                #expect(RecordFormat.hubLine([record], gameID: gameID, language: .japanese)
                        == LegacyJapaneseRecordFormat.hubLine([record], gameID: gameID))
            }
        }
        // 区分が複数ある（代表を選ぶ）場合も同じ。
        for (a, b) in zip(records, records.reversed()) where a.metric == b.metric {
            #expect(RecordFormat.hubLine([a, b], language: .japanese) == LegacyJapaneseRecordFormat.hubLine([a, b]))
        }
        for stage in 0...50 {
            #expect(RecordFormat.runnerStageLine(clearedStage: stage, language: .japanese)
                    == LegacyJapaneseRecordFormat.runnerStageLine(clearedStage: stage))
        }
    }

    @Test("言語を省略すると、いまの表示言語（swift test では日本語）で出る")
    func defaultLanguageIsCurrent() {
        for record in Self.sampleRecords.prefix(300) {
            #expect(RecordFormat.resultLine(record) == RecordFormat.resultLine(record, language: AppLanguageStore.shared.language))
            #expect(RecordFormat.hubLine([record]) == RecordFormat.hubLine([record], language: AppLanguageStore.shared.language))
        }
    }

    // MARK: - 英語

    @Test("ハブの 1 行（英語）")
    func englishHubLines() {
        func hub(_ records: [PlayRecord], gameID: String? = nil) -> String? {
            RecordFormat.hubLine(records, gameID: gameID, language: .english)
        }
        #expect(hub([PlayRecord(metric: .points, plays: 1, bestPoints: 12_340)]) == "Best 12,340")
        #expect(hub([PlayRecord(metric: .shortestTime, plays: 1, wins: 1, bestSeconds: 83)]) == "Best 1:23")
        #expect(hub([PlayRecord(metric: .shortestTime, variantLabel: "Beginner", plays: 1, wins: 1, bestSeconds: 45)])
                == "Best 0:45 (Beginner)")
        #expect(hub([PlayRecord(metric: .fewestMoves, plays: 1, wins: 1, fewestMoves: 24)]) == "Best: 24 moves")
        #expect(hub([PlayRecord(metric: .fewestMoves, plays: 1, wins: 1, fewestMoves: 1)]) == "Best: 1 move")
        #expect(hub([PlayRecord(metric: .fewestMoves, plays: 1, wins: 1, fewestMoves: 1_001)]) == "Best: 1,001 moves")
        #expect(hub([PlayRecord(metric: .winLoss, plays: 4, wins: 3, losses: 1, currentStreak: 1)]) == "3W 1L")
        #expect(hub([PlayRecord(metric: .winLoss, plays: 6, wins: 5, losses: 1, currentStreak: 2)]) == "5W 1L · 2-win streak")
        #expect(hub([PlayRecord(metric: .winLoss, plays: 3, draws: 3)]) == "0W 0L 3D")
        #expect(hub([PlayRecord(metric: .points, plays: 1, bestPoints: 3)], gameID: "runner") == "Reached 1-4")
        #expect(RecordFormat.runnerStageLine(clearedStage: 17, language: .english) == "Reached 3-6")
        #expect(RecordFormat.runnerStageLine(clearedStage: 42, language: .english) == "All 42 stages cleared")
    }

    @Test("リザルトの 1 行（英語・単数と複数）")
    func englishResultLines() {
        func result(_ record: PlayRecord) -> String? { RecordFormat.resultLine(record, language: .english) }
        #expect(result(PlayRecord(metric: .points, plays: 1, bestPoints: 12_340, highestValue: 1_024))
                == "Personal best 12,340 (highest 1,024)")
        #expect(result(PlayRecord(metric: .points, plays: 1, bestPoints: 500)) == "Personal best 500")
        #expect(result(PlayRecord(metric: .shortestTime, plays: 1, wins: 1, bestSeconds: 83)) == "Best time 1:23 · 1 clear")
        #expect(result(PlayRecord(metric: .shortestTime, plays: 9, wins: 4, bestSeconds: 3_725)) == "Best time 1:02:05 · 4 clears")
        #expect(result(PlayRecord(metric: .shortestTime, plays: 1)) == "Not cleared yet (1 try)")
        #expect(result(PlayRecord(metric: .shortestTime, plays: 3)) == "Not cleared yet (3 tries)")
        #expect(result(PlayRecord(metric: .fewestMoves, plays: 1, wins: 1, fewestMoves: 24)) == "Fewest moves: 24")
        #expect(result(PlayRecord(metric: .winLoss, plays: 4, wins: 3, losses: 1, bestStreak: 1)) == "Overall 3W 1L")
        #expect(result(PlayRecord(metric: .winLoss, plays: 9, wins: 6, losses: 1, draws: 2, bestStreak: 4))
                == "Overall 6W 1L 2D · Best streak 4")
    }

    @Test("共有の文言（英語）")
    func englishShareMessages() {
        let points = PlayRecord(metric: .points, plays: 1, bestPoints: 12_340, highestValue: 1_024)
        #expect(RecordFormat.shareMessage(title: "2048", record: points, language: .english)
                == "New record in 2048 on Asobiba!\nPersonal best 12,340 (highest 1,024)")
        let easy = PlayRecord(metric: .shortestTime, variantLabel: "Beginner", plays: 1, wins: 1, bestSeconds: 83)
        #expect(RecordFormat.shareMessage(title: "Minesweeper", record: easy, language: .english)
                == "New record in Minesweeper (Beginner) on Asobiba!\nBest time 1:23 · 1 clear")
        #expect(RecordFormat.shareMessage(title: "2048", record: PlayRecord(), language: .english) == nil)
    }

    @Test("英語の文言に日本語が残らない（どの記録の組み合わせでも）")
    func englishHasNoJapanese() {
        for record in Self.sampleRecords where record.variantLabel == nil {
            let lines = [
                RecordFormat.hubLine([record], language: .english),
                RecordFormat.hubLine([record], gameID: "runner", language: .english),
                RecordFormat.resultLine(record, language: .english),
                RecordFormat.shareMessage(title: "2048", record: record, language: .english),
            ].compactMap { $0 }
            for line in lines {
                #expect(!LocalizationCatalogTests.containsJapanese(line), "英語に日本語が残っている: \(line)")
            }
        }
    }

    @Test("順位: 日本語は「1位」、英語は序数（1st・2nd・3rd・11th・21st・112th）")
    func ranks() {
        let english = [1: "1st", 2: "2nd", 3: "3rd", 4: "4th", 10: "10th", 11: "11th", 12: "12th", 13: "13th",
                       21: "21st", 22: "22nd", 23: "23rd", 101: "101st", 111: "111th", 112: "112th", 1_002: "1,002nd"]
        for (place, text) in english {
            #expect(RecordFormat.rank(place, language: .english) == text)
        }
        #expect(RecordFormat.rank(1, language: .japanese) == "1位")
        #expect(RecordFormat.rank(1_234, language: .japanese) == "1,234位")
        #expect(RecordFormat.rank(3) == "3位", "swift test の既定は日本語")
    }

    @Test("遊んだ回数（きろく）は英語で単数・複数が分かれ、日本語は変わらない")
    func playCounts() {
        #expect(CoreEngine.tr("%@回", RecordFormat.number(1), language: .english) == "1 play")
        #expect(CoreEngine.tr("%@回", RecordFormat.number(1_500), language: .english) == "1,500 plays")
        #expect(CoreEngine.tr("%@回あそんだ", RecordFormat.number(1), language: .english) == "Played 1 time")
        #expect(CoreEngine.tr("%@回あそんだ", RecordFormat.number(12), language: .english) == "Played 12 times")
        #expect(CoreEngine.tr("%@回", RecordFormat.number(1_500), language: .japanese) == "1,500回")
        #expect(CoreEngine.tr("%@回あそんだ", RecordFormat.number(1), language: .japanese) == "1回あそんだ")
    }

    @Test("複数形は、整数が無ければ整形済みの数（1,234）の文字列で選ぶ")
    func pluralCountFromFormattedNumber() {
        #expect(StringCatalog.pluralCount(["1"]) == 1)
        #expect(StringCatalog.pluralCount(["1,234"]) == 1_234)
        #expect(StringCatalog.pluralCount(["-5"]) == -5)
        #expect(StringCatalog.pluralCount(["1:23"]) == nil, "時刻は数として読まない")
        #expect(StringCatalog.pluralCount(["abc", "2"]) == 2)
        #expect(StringCatalog.pluralCount(["-"]) == nil)
        #expect(StringCatalog.pluralCount(["1:23", 4]) == 4, "整数の引数があればそちらが優先")
    }
}

/// #2168 の前の `RecordFormat`（日本語を文字列補間でつなげて組んでいた版）の写し。
/// 日本語の表示が 1 文字も変わっていないことを突き合わせるためだけに持つ。**直さないこと**。
private enum LegacyJapaneseRecordFormat {
    static func hubLine(_ records: [PlayRecord], gameID: String? = nil) -> String? {
        let played = records.filter(\.hasAnyRecord)
        guard let metric = played.first?.metric else { return nil }
        switch metric {
        case .shortestTime:
            guard let best = played.compactMap({ r in r.bestSeconds.map { ($0, r.variantLabel) } })
                .min(by: { $0.0 < $1.0 }) else { return nil }
            let label = best.1.map { "（\($0)）" } ?? ""
            return "最短 \(RecordFormat.time(best.0))\(label)"
        case .points:
            if let base = played.first(where: { $0.variantLabel == nil }), let points = base.bestPoints {
                if gameID == "runner" { return runnerStageLine(clearedStage: points) }
                return "ベスト \(RecordFormat.number(points))"
            }
            guard let best = played.compactMap(\.bestPoints).max() else { return nil }
            return "ベスト \(RecordFormat.number(best))"
        case .fewestMoves:
            guard let best = played.compactMap(\.fewestMoves).min() else { return nil }
            return "最少 \(RecordFormat.number(best))手"
        case .winLoss:
            let streak = played.map(\.currentStreak).max() ?? 0
            let base = winLossText(played)
            return streak >= 2 ? "\(base)・\(streak)連勝中" : base
        }
    }

    static func runnerStageLine(clearedStage: Int) -> String {
        let cleared = max(0, clearedStage)
        guard cleared < 42 else { return "全 42 面クリア" }
        let reached = cleared + 1
        let world = (reached - 1) / 6 + 1
        let index = (reached - 1) % 6 + 1
        return "\(world)-\(index) まで到達"
    }

    static func winLossText(_ records: [PlayRecord]) -> String {
        let wins = records.reduce(0) { $0 + $1.wins }
        let losses = records.reduce(0) { $0 + $1.losses }
        let draws = records.reduce(0) { $0 + $1.draws }
        let base = "\(wins)勝\(losses)敗"
        return draws > 0 ? "\(base)\(draws)分" : base
    }

    static func resultLine(_ record: PlayRecord) -> String? {
        guard record.hasAnyRecord else { return nil }
        switch record.metric {
        case .shortestTime:
            guard let best = record.bestSeconds else {
                return "クリア記録なし（\(record.plays)回挑戦）"
            }
            return "最短タイム \(RecordFormat.time(best))・\(record.wins)回クリア"
        case .points:
            guard let best = record.bestPoints else { return nil }
            if let highest = record.highestValue {
                return "自己ベスト \(RecordFormat.number(best))（最大 \(RecordFormat.number(highest))）"
            }
            return "自己ベスト \(RecordFormat.number(best))"
        case .fewestMoves:
            guard let best = record.fewestMoves else { return nil }
            return "最少手数 \(RecordFormat.number(best))手"
        case .winLoss:
            let base = "通算 \(winLossText([record]))"
            return record.bestStreak >= 2 ? "\(base)・最高\(record.bestStreak)連勝" : base
        }
    }

    static func shareMessage(title: String, record: PlayRecord) -> String? {
        guard let line = resultLine(record) else { return nil }
        let label = record.variantLabel.map { "（\($0)）" } ?? ""
        return "あそびばの「\(title)」\(label)で記録更新！\n\(line)"
    }
}
