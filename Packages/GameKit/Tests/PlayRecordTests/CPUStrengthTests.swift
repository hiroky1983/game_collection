import Foundation
import Testing
import Core

/// CPU 対戦の 5 段階（#1174）の並びと番号。
///
/// **既存 3 段階の番号（0/1/2）を動かさないこと**がこの型の一番の約束で、
/// 動かすと中断データからの再開が 1 段ずれ、段階ごとの強さを固定している各ゲームの
/// テストの意味まで変わる。両端に足した「入門」「ガチ」は -1 と 3 に置いてある。
@Suite("CPU の強さ 5 段階")
struct CPUStrengthTests {

    @Test("呼び名はやさしい順に 入門・簡単・ふつう・むずかしい・ガチ")
    func labelsAreOrderedFromEasiest() {
        #expect(CPUStrength.labels == ["入門", "簡単", "ふつう", "むずかしい", "ガチ"])
        #expect(CPUStrength.allCases.map(\.label) == CPUStrength.labels)
    }

    @Test("既存3段階の番号は 0/1/2 のまま、両端は -1 と 3")
    func rawValuesKeepTheExistingNumbering() {
        #expect(CPUStrength.easy.rawValue == 0)
        #expect(CPUStrength.normal.rawValue == 1)
        #expect(CPUStrength.hard.rawValue == 2)
        #expect(CPUStrength.novice.rawValue == -1)
        #expect(CPUStrength.serious.rawValue == 3)
        // 既定は「ふつう」。各ゲームの `newGame(aiLevel:)` の既定値と揃っている。
        #expect(CPUStrength.standard == .normal)
    }

    @Test("段の並びは番号の大小と一致する（強い順に数が大きい）")
    func orderMatchesRawValue() {
        let raw = CPUStrength.allCases.map(\.rawValue)
        #expect(raw == raw.sorted())
    }

    @Test("階段の位置は 0 始まりで、番号と往復できる")
    func ladderIndexRoundTrips() {
        #expect(CPUStrength.allCases.map(\.ladderIndex) == [0, 1, 2, 3, 4])
        for strength in CPUStrength.allCases {
            #expect(CPUStrength.ladderIndex(forLevel: strength.rawValue) == strength.ladderIndex)
            #expect(CPUStrength.level(atLadderIndex: strength.ladderIndex) == strength.rawValue)
        }
    }

    @Test("知らない番号・範囲外は既定（ふつう）に倒す")
    func unknownLevelsFallBackToDefault() {
        #expect(CPUStrength.strength(for: 99) == .normal)
        #expect(CPUStrength.strength(for: -99) == .normal)
        #expect(CPUStrength.level(atLadderIndex: 5) == CPUStrength.normal.rawValue)
        #expect(CPUStrength.level(atLadderIndex: -1) == CPUStrength.normal.rawValue)
    }

    /// 階段（#722）は「今の段の 1 つ上」を勧める。5 段になっても最上段では勧めない。
    @Test("階段は入門からガチまで 1 段ずつ上がり、ガチでは勧めない")
    func ladderClimbsThroughAllFiveSteps() {
        let record = PlayRecord(plays: DifficultyLadder.streakThreshold,
                                wins: DifficultyLadder.streakThreshold,
                                currentStreak: DifficultyLadder.streakThreshold)
        let result = RecordResult(record: record, update: RecordUpdate())
        for strength in CPUStrength.allCases {
            let offer = DifficultyLadder.offer(
                for: result,
                currentLevel: CPUStrength.ladderIndex(forLevel: strength.rawValue),
                levelLabels: CPUStrength.labels
            )
            if strength == .serious {
                #expect(offer == nil, "最上段（ガチ）では勧めない")
            } else {
                let next = try? #require(offer)
                #expect(next?.nextLevelLabel
                        == CPUStrength.allCases[strength.ladderIndex + 1].label)
                #expect(CPUStrength.level(atLadderIndex: next?.nextLevel ?? -1)
                        == CPUStrength.allCases[strength.ladderIndex + 1].rawValue)
            }
        }
    }
}
