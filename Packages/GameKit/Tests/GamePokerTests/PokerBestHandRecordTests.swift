import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GamePoker

/// 「いちばん強い役」を歴代の自己ベストとして残す（#2591）。`PlayRecord.highestValue` に `PokerHandRank` の序数を入れる。
@Suite("ポーカー: 歴代のいちばん強い役")
@MainActor
struct PokerBestHandRecordTests {

    @Test("Core 側の役名の表は PokerHandRank の序数・表記と一致する（全 10 役・日英）")
    func rankNamesMatchCore() {
        let ranks: [(PokerHandRank, String)] = [
            (.highCard, "ハイカード"), (.onePair, "ワンペア"), (.twoPair, "ツーペア"), (.threeOfAKind, "スリーカード"),
            (.straight, "ストレート"), (.flush, "フラッシュ"), (.fullHouse, "フルハウス"), (.fourOfAKind, "フォーカード"),
            (.straightFlush, "ストレートフラッシュ"), (.royalFlush, "ロイヤルフラッシュ"),
        ]
        #expect(ranks.map(\.0.rawValue) == Array(0..<10))
        for (rank, key) in ranks {
            for language in [AppLanguage.japanese, .english] {
                let record = PlayRecord(metric: .points, recordKey: "poker#round10", plays: 1, bestPoints: 5, highestValue: rank.rawValue)
                let line = RecordFormat.resultLine(record, language: language)
                #expect(line?.contains(tr(key, language: language)) == true, "\(rank) \(language)")
            }
        }
    }

    @Test("10 回勝負が終わると、その勝負でいちばん強かった役が highestValue に残り、リザルトとハブに役名が出る")
    func bestHandIsRecorded() {
        let log = makePokerPlayLog()
        let model = makePokerModel(
            pokerSnapshot(round: 10, player: PokerHands.fullHouse, cpu: PokerHands.straight, playerPoints: 10, cpuPoints: 20),
            playLog: log
        )
        model.showdown()
        let result = model.recordResult
        #expect(result?.record.highestValue == PokerHandRank.fullHouse.rawValue)
        #expect(result?.update.highestValue == true, "初めての記録でも 0 より大きければ更新")
        #expect(RecordFormat.resultLine(result!.record, language: .japanese) == "自己ベスト 28（フルハウス）")
        #expect(log.summaryLine(gameID: "poker") == "ベスト 28・フルハウス")
    }

    @Test("歴代より弱い役の勝負では highestValue は更新されず、強い役を出せば更新される")
    func onlyStrongerHandUpdates() {
        let log = makePokerPlayLog()
        _ = log.recordResult(gameID: "poker", outcome: .win,
                             score: GameScore(metric: .points, points: 100, highestValue: PokerHandRank.flush.rawValue,
                                              variant: PokerModel.recordVariant))
        let weaker = makePokerModel(
            pokerSnapshot(round: 10, player: PokerHands.straight, cpu: PokerHands.highCard, playerPoints: 0, cpuPoints: 20),
            playLog: log
        )
        weaker.showdown()
        #expect(weaker.recordResult?.update.highestValue == false)
        #expect(weaker.recordResult?.update.isNewBest == false, "点も役も更新していない回は『自己ベスト更新！』を出さない")
        #expect(weaker.recordResult?.record.highestValue == PokerHandRank.flush.rawValue)

        let stronger = makePokerModel(
            pokerSnapshot(round: 10, player: PokerHands.fullHouse, cpu: PokerHands.highCard, playerPoints: 0, cpuPoints: 20),
            playLog: log
        )
        stronger.showdown()
        #expect(stronger.recordResult?.update.highestValue == true)
        #expect(stronger.recordResult?.record.highestValue == PokerHandRank.fullHouse.rawValue)
    }
}
