import Foundation
import Testing
import Core

/// リザルトの「階段」（#722）の提示条件。
///
/// 判定は決着を記録した結果（`RecordResult`）だけで決まり、保存する状態を持たない。
/// 実際の決着の積み上げ（`PlayRecord.applying`）を通して、連勝の数え方ごと固定する。
@Suite("難易度の階段")
struct DifficultyLadderTests {
    private static let labels = ["弱", "普通", "強"]
    private static let n = DifficultyLadder.streakThreshold

    /// 勝敗を順に記録した直後の結果。
    private func result(after outcomes: [GameOutcome]) -> RecordResult? {
        var previous: PlayRecord?
        var last: RecordResult?
        for outcome in outcomes {
            let applied = PlayRecord.applying(outcome: outcome, score: GameScore(), to: previous)
            previous = applied.record
            last = applied
        }
        return last
    }

    private func wins(_ count: Int) -> [GameOutcome] { Array(repeating: .win, count: count) }

    @Test("しきい値ちょうどの連勝で、一段上を勧める")
    func offersNextLevelAtThreshold() throws {
        let offer = try #require(DifficultyLadder.offer(
            for: result(after: wins(Self.n)), currentLevel: 0, levelLabels: Self.labels))
        #expect(offer.streak == Self.n)
        #expect(offer.nextLevel == 1)
        #expect(offer.nextLevelLabel == "普通")
        #expect(offer.title == "つぎは「普通」にしてみる？")
        #expect(offer.caption == "\(Self.n)連勝中！")
    }

    @Test("しきい値に届かない連勝では勧めない")
    func noOfferBelowThreshold() {
        for count in 0..<Self.n {
            #expect(DifficultyLadder.offer(
                for: result(after: [.loss] + wins(count)), currentLevel: 0, levelLabels: Self.labels) == nil,
                    "\(count) 連勝で出てしまう")
        }
    }

    /// 勧めを使わずに同じ段で遊び続けた（= 断った）人に、次の勝ちで即座に出し直さない。
    @Test("断ったあとは次の勝ちで出さず、さらに同じだけ勝ったら出す")
    func respectsIntervalAfterDecline() {
        for count in (Self.n + 1)..<(Self.n * 2) {
            #expect(DifficultyLadder.offer(
                for: result(after: wins(count)), currentLevel: 0, levelLabels: Self.labels) == nil,
                    "\(count) 連勝で出し直してしまう")
        }
        #expect(DifficultyLadder.offer(
            for: result(after: wins(Self.n * 2)), currentLevel: 0, levelLabels: Self.labels)?.streak == Self.n * 2)
    }

    @Test("負け・引き分けで途切れたら数え直す")
    func streakBreakResets() {
        #expect(DifficultyLadder.offer(
            for: result(after: wins(Self.n) + [.loss]), currentLevel: 0, levelLabels: Self.labels) == nil)
        #expect(DifficultyLadder.offer(
            for: result(after: wins(Self.n - 1) + [.draw] + wins(Self.n - 1)),
            currentLevel: 0, levelLabels: Self.labels) == nil)
        #expect(DifficultyLadder.offer(
            for: result(after: wins(Self.n) + [.loss] + wins(Self.n)),
            currentLevel: 0, levelLabels: Self.labels) != nil)
    }

    @Test("最上級では勧めない")
    func noOfferAtTopLevel() {
        let streak = result(after: wins(Self.n))
        #expect(DifficultyLadder.offer(for: streak, currentLevel: 1, levelLabels: Self.labels)?.nextLevelLabel == "強")
        #expect(DifficultyLadder.offer(for: streak, currentLevel: 2, levelLabels: Self.labels) == nil)
        #expect(DifficultyLadder.offer(for: streak, currentLevel: 5, levelLabels: Self.labels) == nil)
        #expect(DifficultyLadder.offer(for: streak, currentLevel: -1, levelLabels: Self.labels) == nil)
    }

    @Test("記録が無い・段が分からないときは勧めない")
    func noOfferWithoutRecordOrLevel() {
        #expect(DifficultyLadder.offer(for: nil, currentLevel: 0, levelLabels: Self.labels) == nil)
        #expect(DifficultyLadder.offer(
            for: result(after: wins(Self.n)), currentLevel: nil, levelLabels: Self.labels) == nil)
    }

    /// ×で閉じた提案は `RecommendationSlot` が値で覚える。別の決着の提案が同じ値になると、
    /// 次に同じ連勝数へ届いたときにも閉じたままになる。
    @Test("同じ連勝数でも、別の決着の提案は別物として扱う")
    func offersFromDifferentFinishesDiffer() {
        let first = DifficultyLadder.offer(
            for: result(after: wins(Self.n)), currentLevel: 0, levelLabels: Self.labels)
        let later = DifficultyLadder.offer(
            for: result(after: wins(Self.n) + [.loss] + wins(Self.n)), currentLevel: 0, levelLabels: Self.labels)
        #expect(first != nil && later != nil)
        #expect(first != later)
    }

    @Test("押したら勧めた段で始め直す")
    @MainActor
    func promptClimbsToOfferedLevel() throws {
        var started: [Int] = []
        let prompt = try #require(DifficultyLadderPrompt(
            result: result(after: wins(Self.n)), currentLevel: 1, levelLabels: Self.labels
        ) { started.append($0) })
        prompt.climb()
        #expect(started == [2])
        #expect(DifficultyLadderPrompt(
            result: result(after: wins(Self.n)), currentLevel: 2, levelLabels: Self.labels
        ) { started.append($0) } == nil)
    }

    // MARK: - 連敗で一段下を勧める（#2614）

    private func losses(_ count: Int) -> [GameOutcome] { Array(repeating: .loss, count: count) }

    @Test("しきい値ちょうどの連敗で、一段下を勧める")
    func offersLowerLevelAtLossThreshold() throws {
        let offer = try #require(DifficultyLadder.offer(
            for: result(after: losses(Self.n)), currentLevel: 2, levelLabels: Self.labels))
        #expect(offer.direction == .down)
        #expect(offer.streak == Self.n)
        #expect(offer.nextLevel == 1)
        #expect(offer.nextLevelLabel == "普通")
        #expect(offer.caption == "\(Self.n)連敗中…")
        #expect(offer.title == "つぎは「普通」にしてみる？")
    }

    @Test("最下段では一段下を勧めない")
    func noDownOfferAtBottomLevel() {
        let lost = result(after: losses(Self.n))
        #expect(DifficultyLadder.offer(for: lost, currentLevel: 0, levelLabels: Self.labels) == nil)
        #expect(DifficultyLadder.offer(for: lost, currentLevel: 1, levelLabels: Self.labels)?.nextLevel == 0)
        #expect(DifficultyLadder.offer(for: lost, currentLevel: -1, levelLabels: Self.labels) == nil)
        #expect(DifficultyLadder.offer(for: lost, currentLevel: 5, levelLabels: Self.labels) == nil)
        #expect(DifficultyLadder.offer(for: lost, currentLevel: nil, levelLabels: Self.labels) == nil)
    }

    @Test("連敗が届かない・勝ちか引き分けで途切れたら勧めない")
    func lossStreakBreakResets() {
        for count in 0..<Self.n {
            #expect(DifficultyLadder.offer(
                for: result(after: [.win] + losses(count)), currentLevel: 2, levelLabels: Self.labels) == nil,
                    "\(count) 連敗で出てしまう")
        }
        for breaker in [GameOutcome.win, .draw] {
            #expect(DifficultyLadder.offer(
                for: result(after: losses(Self.n) + [breaker]), currentLevel: 2, levelLabels: Self.labels) == nil)
            #expect(DifficultyLadder.offer(
                for: result(after: losses(Self.n - 1) + [breaker] + losses(Self.n - 1)),
                currentLevel: 2, levelLabels: Self.labels) == nil)
        }
    }

    @Test("断ったあとは次の負けで出さず、さらに同じだけ負けたら出す")
    func respectsIntervalAfterDeclineOfDownOffer() {
        for count in (Self.n + 1)..<(Self.n * 2) {
            #expect(DifficultyLadder.offer(
                for: result(after: losses(count)), currentLevel: 2, levelLabels: Self.labels) == nil,
                    "\(count) 連敗で出し直してしまう")
        }
        #expect(DifficultyLadder.offer(
            for: result(after: losses(Self.n * 2)), currentLevel: 2, levelLabels: Self.labels)?.streak == Self.n * 2)
    }

    @Test("連勝と連敗は同時に出ない。向きが違えば別の提案")
    func upAndDownAreExclusive() throws {
        for outcomes in [wins(Self.n), losses(Self.n), wins(Self.n) + [.loss], losses(Self.n) + [.win]] {
            let offer = DifficultyLadder.offer(for: result(after: outcomes), currentLevel: 1, levelLabels: Self.labels)
            #expect(offer == nil || [DifficultyLadderOffer.Direction.up, .down].contains(offer!.direction))
        }
        let up = try #require(DifficultyLadder.offer(
            for: result(after: wins(Self.n)), currentLevel: 1, levelLabels: Self.labels))
        let down = try #require(DifficultyLadder.offer(
            for: result(after: losses(Self.n)), currentLevel: 1, levelLabels: Self.labels))
        #expect(up.direction == .up && up.nextLevel == 2)
        #expect(down.direction == .down && down.nextLevel == 0)
        #expect(up != down)
    }

    @Test("連敗の数え方: 負けで +1、勝ち・引き分けで 0。旧データ（項目なし）も読める")
    func lossStreakCountingAndLegacyDecode() throws {
        #expect(result(after: losses(2))?.record.lossStreak == 2)
        #expect(result(after: losses(2) + [.win])?.record.lossStreak == 0)
        #expect(result(after: losses(2) + [.draw])?.record.lossStreak == 0)
        #expect(result(after: wins(2))?.record.currentLossStreak == nil)

        let legacy = Data(#"{"metric":"winLoss","plays":1,"wins":0,"losses":1,"draws":0,"currentStreak":0,"bestStreak":0}"#.utf8)
        let decoded = try JSONDecoder().decode(PlayRecord.self, from: legacy)
        #expect(decoded.lossStreak == 0)
        let roundTrip = try JSONDecoder().decode(PlayRecord.self, from: JSONEncoder().encode(
            try #require(result(after: losses(3))?.record)))
        #expect(roundTrip.lossStreak == 3)
    }

    @Test("押したら勧めた一段下で始め直す")
    @MainActor
    func promptDescendsToOfferedLevel() throws {
        var started: [Int] = []
        let prompt = try #require(DifficultyLadderPrompt(
            result: result(after: losses(Self.n)), currentLevel: 2, levelLabels: Self.labels
        ) { started.append($0) })
        prompt.climb()
        #expect(started == [1])
    }
}
