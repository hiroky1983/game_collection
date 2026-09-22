import Foundation
import Testing
import Core

/// CPU 対戦の強さの並びと番号（#1174）。
///
/// **既存 3 段階の番号（0/1/2）を動かさないこと**がこの型の一番の約束で、
/// 動かすと中断データからの再開が 1 段ずれ、段階ごとの強さを固定している各ゲームの
/// テストの意味まで変わる。下に足した「入門」は -1 に置いてある。
/// 「ガチ」（3）は v1.1.6 で一旦見送り（会長指摘・2026-09-22。`CPUStrength.swift` 参照）。
@Suite("CPU の強さ")
struct CPUStrengthTests {

    @Test("呼び名はやさしい順に 入門・簡単・ふつう・むずかしい")
    func labelsAreOrderedFromEasiest() {
        #expect(CPUStrength.labels == ["入門", "簡単", "ふつう", "むずかしい"])
        #expect(CPUStrength.allCases.map(\.label) == CPUStrength.labels)
    }

    @Test("既存3段階の番号は 0/1/2 のまま、下に -1 を足してある")
    func rawValuesKeepTheExistingNumbering() {
        #expect(CPUStrength.easy.rawValue == 0)
        #expect(CPUStrength.normal.rawValue == 1)
        #expect(CPUStrength.hard.rawValue == 2)
        #expect(CPUStrength.novice.rawValue == -1)
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
        #expect(CPUStrength.allCases.map(\.ladderIndex) == [0, 1, 2, 3])
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

    /// 見送り前の「ガチ」の番号（3）が中断データに残っていても、既定（ふつう）に丸めて壊れないこと。
    @Test("廃止した「ガチ」の番号（3）は既定に倒す")
    func removedSeriousLevelFallsBackToDefault() {
        #expect(CPUStrength.strength(for: 3) == .normal)
    }

    /// 階段（#722）は「今の段の 1 つ上」を勧める。最上段では勧めない。
    @Test("階段は入門からむずかしいまで 1 段ずつ上がり、最上段では勧めない")
    func ladderClimbsThroughAllSteps() {
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
            if strength == .hard {
                #expect(offer == nil, "最上段（むずかしい）では勧めない")
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
