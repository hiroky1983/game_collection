import Testing
import Foundation
import Core
import GameKitTestSupport
import GameShogi
import GameMinesweeper
import GamePoker
import GameMahjong
import GameSudoku
import GameSolitaire
import GameRunner
import GameHanafuda
import GameSpider
@testable import GameShiritori
@testable import GameConcentration
@testable import GameMahjongSolitaire
import GameAnzan
@testable import GameAkariKeshi
@testable import GameTsunagi
import GameHanoi
import GameOjisanPuzzle
import GameSpeed
import GameCatPuzzle

/// 区分（`recordVariant`）を持つゲームが、全部 `RecordVariantLabels` の表に載っていること（#2240）。
///
/// 表に載っていない区分は、英語表示でも保存済みの日本語の区分名にフォールバックしてしまう
/// （将棋の駒落ちが #2227 と #2228 の行き違いでこれになった）。
/// 区分を足し忘れても、`RecordVariantLabels` の表にゲームを足した時点で `tableGamesAreAllScanned` が落ちる（#2287）。
@Suite("記録の区分名の表の網羅")
struct RecordVariantLabelCoverageTests {
    /// 区分を持つゲームの (gameID, 区分キー) の全部。nil（既定の保存先）は区分名を引かないので含めない。
    static var allVariants: [(gameID: String, variant: String)] {
        var result: [(String, String)] = []
        func add(_ gameID: String, _ variant: String?) { if let variant { result.append((gameID, variant)) } }
        for handicap in ShogiHandicap.allCases {
            for dropper in ShogiHandicapDropper.allCases {
                add("shogi", ShogiMatchSetting(handicap: handicap, dropper: dropper).recordVariant)
            }
        }
        add("poker", PokerModel.recordVariant)
        for length in MahjongGameLength.allCases { add("mahjong4", length.recordVariant) }
        for mode in RunnerMode.allCases { add("runner", mode.recordVariant) }
        for mode in SolitaireDrawMode.allCases { add("solitaire", mode.recordVariant) }
        for count in SpiderSuitCount.allCases { add("spider", count.recordVariant) }
        for level in SudokuDifficulty.allCases { add("sudoku", level.rawValue) }
        for rounds in HanafudaOptions.allowedRounds {
            for sake in [true, false] {
                for level in HanafudaDifficulty.allCases {
                    add("hanafuda", HanafudaOptions(sakeYakuEnabled: sake, rounds: rounds, difficulty: level).recordVariant)
                }
            }
        }
        for preset in ["9x9-10", "16x16-40", "20x20-82"] { add("minesweeper", preset) }
        for mode in ShiritoriMode.allCases { for quota in ShiritoriQuota.allCases { add("shiritori", mode.scoreVariant(quota: quota)?.key) } }
        for level in ConcentrationCPULevel.allCases { add("concentration", level.recordVariantKey) }
        for layout in MahjongSolitaireLayout.all { add("mahjong", layout.id) }
        for level in SpeedLevel.allCases { add("speed", level.rawValue) }
        for mode in OjisanPuzzleMode.allCases { add("ojisanpuzzle", mode.recordVariant) }
        for digits in AnzanDigits.allCases {
            for count in AnzanCount.allCases {
                for speed in AnzanSpeed.allCases {
                    add("anzan", AnzanSettings(digits: digits, count: count, speed: speed).variant)
                }
            }
        }
        for level in AkariKeshiDifficulty.allCases { add("akarikeshi", level.rawValue) }
        for size in TsunagiSize.allCases { add("tsunagi", size.recordVariant) }
        for disks in HanoiLogic.diskRange { add("hanoi", "\(disks)disks") }
        for size in CatPuzzleSize.allCases { add("catpuzzle", size.rawValue) }
        // 大富豪・いろリレーは CPU の強さ別（#2604）。「ふつう」は区分なし（従来の保存先）。
        for strength in CPUStrength.allCases where strength != .standard {
            add("daifugo", strength.recordVariantKey)
            add("colorrelay", strength.recordVariantKey)
            // チェス・囲碁・五目並べ・オセロも CPU の強さ別（#2617）。
            for game in ["chess", "go", "gomoku", "othello", "hearts", "oldmaid"] { add(game, strength.recordVariantKey) }
        }
        // いろリレーは相手の人数別（#2866）。相手 3 人は上の強さ別のキー、1・2 人は `cpu<人数>[-<強さ>]`。
        for opponents in 1...2 {
            for strength in CPUStrength.allCases {
                add("colorrelay", strength == .standard ? "cpu\(opponents)" : "cpu\(opponents)-\(strength.recordVariantKey)")
            }
        }
        return result
    }

    /// `RecordVariantLabels.label` の `switch` が持つゲーム ID（表のソースから読む）。
    static var tableGameIDs: Set<String> {
        let whole = (try? SourceScan.packageSource("Sources/CoreEngine/RecordVariantLabels.swift")) ?? ""
        // 組み立て用の補助関数にも同じ字下げの case があるので、`label` の範囲（`stored` の手前まで）だけ読む。
        let source = whole.components(separatedBy: "public static func stored").first ?? ""
        let pattern = try! NSRegularExpression(pattern: #"^        case "([a-z0-9]+)":"#, options: .anchorsMatchLines)
        let range = NSRange(source.startIndex..., in: source)
        return Set(pattern.matches(in: source, range: range).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        })
    }

    @Test("区分名の表にあるゲームは、全部この走査の対象に入っている（足し忘れで落ちる）")
    func tableGamesAreAllScanned() {
        let table = Self.tableGameIDs
        #expect(table.count >= 17, "表のゲームを読めていない: \(table)")
        let scanned = Set(Self.allVariants.map(\.gameID))
        #expect(table.subtracting(scanned).isEmpty, "走査の対象に無いゲーム: \(table.subtracting(scanned).sorted())")
        #expect(scanned.subtracting(table).isEmpty, "表に無いゲーム: \(scanned.subtracting(table).sorted())")
    }

    @Test("区分を持つ全ゲームの全区分が、英語の表示名を引ける（日本語が混ざらない）")
    func everyVariantHasEnglishLabel() {
        #expect(Self.allVariants.count >= 20)
        for (gameID, variant) in Self.allVariants {
            let key = "\(gameID)#\(variant)"
            let english = RecordVariantLabels.label(recordKey: key, language: .english)
            #expect(english != nil, "\(key) が RecordVariantLabels に無い")
            #expect(!Self.containsJapanese(english ?? ""), "\(key) の英語に日本語が混ざる: \(english ?? "nil")")
            #expect(RecordVariantLabels.label(recordKey: key, language: .japanese) != nil, "\(key) の日本語が引けない")
        }
    }

    @Test("将棋の駒落ちの 4 区分は、日本語では従来の保存名と一致し、英語では日本語を含まない")
    func shogiHandicapLabels() {
        let expected: [(String, String, String)] = [
            ("rook-player", "飛車落ち・自分が落とす", "Rook handicap · I drop it"),
            ("rook-cpu", "飛車落ち・CPUが落とす", "Rook handicap · CPU drops it"),
            ("bishop-player", "角落ち・自分が落とす", "Bishop handicap · I drop it"),
            ("bishop-cpu", "角落ち・CPUが落とす", "Bishop handicap · CPU drops it"),
        ]
        for (variant, ja, en) in expected {
            #expect(RecordVariantLabels.label(recordKey: "shogi#\(variant)", language: .japanese) == ja)
            #expect(RecordVariantLabels.label(recordKey: "shogi#\(variant)", language: .english) == en)
        }
        #expect(RecordVariantLabels.label(recordKey: "shogi#rook", language: .english) == nil)
        #expect(RecordVariantLabels.label(recordKey: "shogi#queen-cpu", language: .english) == nil)
    }

    @Test("将棋の保存名は表と同じ綴りで、共有文はいまの表示言語の区分名になる")
    func shogiShareMessageFollowsDisplayLanguage() {
        for handicap in [ShogiHandicap.rook, .bishop] {
            for dropper in ShogiHandicapDropper.allCases {
                let setting = ShogiMatchSetting(handicap: handicap, dropper: dropper)
                let key = "shogi#\(setting.recordVariant ?? "")"
                #expect(setting.recordVariantLabel == RecordVariantLabels.label(recordKey: key, language: .japanese))
                for saved in [setting.recordVariantLabel ?? "", RecordVariantLabels.label(recordKey: key, language: .english) ?? ""] {
                    let record = PlayRecord(metric: .winLoss, variantLabel: saved, recordKey: key, plays: 3, wins: 2)
                    let english = RecordFormat.shareMessage(title: "Shogi", record: record, language: .english) ?? ""
                    let english2 = RecordVariantLabels.label(recordKey: key, language: .english) ?? "?"
                    #expect(english.contains(english2), "保存=\(saved): \(english)")
                    #expect(!Self.containsJapanese(english), "保存=\(saved): \(english)")
                    let japanese = RecordFormat.shareMessage(title: "将棋", record: record, language: .japanese) ?? ""
                    #expect(japanese.contains(setting.recordVariantLabel ?? "?"), "保存=\(saved): \(japanese)")
                }
            }
        }
        #expect(ShogiMatchSetting(handicap: .even, dropper: .player).recordVariantLabel == nil)
    }

    private static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
    }
}
