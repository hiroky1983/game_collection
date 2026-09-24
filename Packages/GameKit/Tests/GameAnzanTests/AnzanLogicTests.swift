import Testing
import Foundation
import Core
@testable import GameAnzan

@Suite("ぱっと暗算の出題ロジック")
struct AnzanLogicTests {

    @Test("桁数ごとに範囲内の数だけを、指定の個数ぶん作る")
    func numbersFollowSettings() {
        for digits in AnzanDigits.allCases {
            for count in AnzanCount.allCases {
                var generator = SplitMix64(seed: UInt64(digits.rawValue * 100 + count.rawValue))
                let settings = AnzanSettings(digits: digits, count: count, speed: .normal)
                let numbers = AnzanLogic.makeNumbers(settings, using: &generator)
                #expect(numbers.count == count.rawValue)
                #expect(numbers.allSatisfy { digits.range.contains($0) }, "\(digits) \(numbers)")
            }
        }
    }

    @Test("同じ種なら同じ問題、種が違えば違う問題")
    func seededDeterminism() {
        var a = SplitMix64(seed: 7)
        var b = SplitMix64(seed: 7)
        var c = SplitMix64(seed: 8)
        let settings = AnzanSettings(digits: .two, count: .ten, speed: .fast)
        let first = AnzanLogic.makeNumbers(settings, using: &a)
        #expect(first == AnzanLogic.makeNumbers(settings, using: &b))
        #expect(first != AnzanLogic.makeNumbers(settings, using: &c))
    }

    @Test("3 桁は 100〜999 を実際に端まで使う（0 始まりの数は出ない）")
    func threeDigitRangeIsFullyUsed() {
        var generator = SplitMix64(seed: 3)
        let settings = AnzanSettings(digits: .three, count: .fifteen, speed: .slow)
        var seen: Set<Int> = []
        for _ in 0..<200 {
            seen.formUnion(AnzanLogic.makeNumbers(settings, using: &generator))
        }
        #expect(seen.min()! >= 100)
        #expect(seen.max()! <= 999)
        #expect(seen.min()! < 150, "下端の近くが出ていない")
        #expect(seen.max()! > 950, "上端の近くが出ていない")
        #expect(!seen.contains(where: { $0 < 100 }))
    }

    @Test("合計と式")
    func sumAndExpression() {
        #expect(AnzanLogic.sum([3, 8, 5]) == 16)
        #expect(AnzanLogic.sum([]) == 0)
        #expect(AnzanLogic.expression([3, 8, 5]) == "3 + 8 + 5 = 16")
        #expect(AnzanLogic.expression([]) == "")
    }

    @Test("表示の並びは よーい → 数と空白の交互 → 最後も空白")
    func stepsSequence() {
        let steps = AnzanLogic.steps(count: 3)
        #expect(steps == [.ready, .number(0), .blank, .number(1), .blank, .number(2), .blank])
        #expect(AnzanLogic.steps(count: 0) == [.ready])
        #expect(AnzanLogic.steps(count: -1) == [.ready])
    }

    @Test("数と空白の時間を足すと間隔ちょうどになり、速さごとに変わる")
    func stepDurations() {
        for speed in AnzanSpeed.allCases {
            let number = AnzanLogic.milliseconds(of: .number(0), speed: speed)
            let blank = AnzanLogic.milliseconds(of: .blank, speed: speed)
            #expect(number + blank == speed.intervalMilliseconds, "\(speed)")
            #expect(number > blank, "数のほうを長く見せる: \(speed)")
            #expect(blank >= 150, "空白が短すぎると同じ数が続いたとき切れ目が分からない: \(speed)")
            #expect(AnzanLogic.milliseconds(of: .ready, speed: speed) == AnzanLogic.readyMilliseconds)
        }
        #expect(AnzanSpeed.slow.intervalMilliseconds > AnzanSpeed.normal.intervalMilliseconds)
        #expect(AnzanSpeed.normal.intervalMilliseconds > AnzanSpeed.fast.intervalMilliseconds)
    }

    @Test("入力できる桁数は取りうる最大の合計の桁数")
    func maxInputDigits() {
        #expect(AnzanLogic.maxInputDigits(AnzanSettings(digits: .one, count: .five, speed: .slow)) == 2)      // 45
        #expect(AnzanLogic.maxInputDigits(AnzanSettings(digits: .two, count: .ten, speed: .slow)) == 3)      // 990
        #expect(AnzanLogic.maxInputDigits(AnzanSettings(digits: .three, count: .fifteen, speed: .slow)) == 5) // 14985
        #expect(AnzanLogic.maxInputDigits(AnzanSettings(digits: .one, count: .fifteen, speed: .slow)) == 3)  // 135
    }
}

@Suite("ぱっと暗算の難易度")
struct AnzanSettingsTests {

    @Test("記録の区分キーは 3 軸の組ごとに一意で、表示名は 3 軸を並べる")
    func variantKeys() {
        var keys: Set<String> = []
        for digits in AnzanDigits.allCases {
            for count in AnzanCount.allCases {
                for speed in AnzanSpeed.allCases {
                    let settings = AnzanSettings(digits: digits, count: count, speed: speed)
                    keys.insert(settings.variant)
                    #expect(settings.variantLabel == "\(digits.label)・\(count.label)・\(speed.label)")
                }
            }
        }
        #expect(keys.count == 27)
        #expect(AnzanSettings.standard.variant == "d1-n5-slow")
        #expect(AnzanSettings.standard.variantLabel == "1桁・5個・ゆっくり")
    }

    @Test("解析の level は段の和を 4 段階へ丸め、単調に上がる")
    func analyticsLevel() {
        #expect(AnzanSettings.standard.rank == 0)
        #expect(AnzanSettings.standard.analyticsLevel == .beginner)
        #expect(AnzanSettings(digits: .two, count: .five, speed: .slow).analyticsLevel == .beginner)
        #expect(AnzanSettings(digits: .two, count: .ten, speed: .slow).analyticsLevel == .normal)
        #expect(AnzanSettings(digits: .two, count: .ten, speed: .normal).analyticsLevel == .normal)
        #expect(AnzanSettings(digits: .three, count: .ten, speed: .normal).analyticsLevel == .hard)
        #expect(AnzanSettings(digits: .three, count: .fifteen, speed: .normal).analyticsLevel == .hard)
        #expect(AnzanSettings(digits: .three, count: .fifteen, speed: .fast).rank == 6)
        #expect(AnzanSettings(digits: .three, count: .fifteen, speed: .fast).analyticsLevel == .expert)
        // 段が上がって level が下がる組は無い。
        let order: [AnalyticsLevel] = [.beginner, .normal, .hard, .expert]
        for digits in AnzanDigits.allCases {
            for count in AnzanCount.allCases {
                for speed in AnzanSpeed.allCases {
                    let settings = AnzanSettings(digits: digits, count: count, speed: speed)
                    let index = order.firstIndex(of: settings.analyticsLevel)!
                    let expected = min(3, settings.rank / 2)
                    #expect(index == expected, "\(settings.variant): rank \(settings.rank)")
                }
            }
        }
    }

    @Test("中断データは JSON で往復し、桁数・個数・速さを失わない")
    func snapshotRoundTrip() throws {
        let snapshot = AnzanSnapshot(settings: AnzanSettings(digits: .three, count: .fifteen, speed: .fast))
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AnzanSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }

    @Test("読み上げ文")
    func accessibility() {
        #expect(AnzanAccessibility.keyLabel(.digit(7)) == "7")
        #expect(AnzanAccessibility.keyLabel(.backspace) == "1文字消す")
        #expect(AnzanAccessibility.keyLabel(.submit) == "決定")
        #expect(AnzanAccessibility.stageLabel(phase: .flashing, step: .ready, displayedNumber: nil,
                                              input: "", sum: 16, answer: nil, isCorrect: false) == "よーい")
        #expect(AnzanAccessibility.stageLabel(phase: .flashing, step: .number(0), displayedNumber: 47,
                                              input: "", sum: 16, answer: nil, isCorrect: false) == "47")
        #expect(AnzanAccessibility.stageLabel(phase: .flashing, step: .blank, displayedNumber: nil,
                                              input: "", sum: 16, answer: nil, isCorrect: false) == "次の数を待っています")
        #expect(AnzanAccessibility.stageLabel(phase: .answering, step: nil, displayedNumber: nil,
                                              input: "12", sum: 16, answer: nil, isCorrect: false) == "いまの入力は12")
        #expect(AnzanAccessibility.stageLabel(phase: .result, step: nil, displayedNumber: nil,
                                              input: "16", sum: 16, answer: 16, isCorrect: true) == "せいかい。合計は16")
        #expect(AnzanAccessibility.stageLabel(phase: .result, step: nil, displayedNumber: nil,
                                              input: "15", sum: 16, answer: 15, isCorrect: false)
                == "ざんねん。正解は16、あなたの答えは15")
    }
}
