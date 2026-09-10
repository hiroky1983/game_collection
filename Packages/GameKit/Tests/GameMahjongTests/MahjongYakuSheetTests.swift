import Testing
import Foundation
import SwiftUI
import Core
import MahjongTiles
@testable import GameMahjong

/// 役早見表（#501）の受け入れ条件。
///
/// 早見表と役判定は `MahjongYaku` という 1 つの定義source を共有する設計なので、
/// **その前提が崩れていないこと**をここで縛る。文言だけを見るテストにすると、
/// 判定側だけ直したときに表が嘘になったことを検出できない。
@Suite("麻雀: 役の早見表")
struct MahjongYakuSheetTests {

    // MARK: - 表が全役を載せているか

    @Test("早見表の並びは実装済みの全役を1回ずつ載せている")
    func displayOrderCoversEveryYaku() {
        #expect(Set(MahjongYaku.displayOrder) == Set(MahjongYaku.allCases))
        #expect(
            MahjongYaku.displayOrder.count == MahjongYaku.allCases.count,
            "同じ役が2回並んでいる: \(MahjongYaku.displayOrder.map(\.rawValue))"
        )
    }

    @Test("セクションに振り分けても1つも落ちない")
    func sectionsPartitionEveryYaku() {
        let grouped = MahjongYaku.Section.allCases.flatMap { MahjongYaku.yaku(in: $0) }
        #expect(Set(grouped) == Set(MahjongYaku.allCases))
        #expect(grouped.count == MahjongYaku.allCases.count)
        // 並びは `displayOrder` のまま（セクションごとに切っても順序が入れ替わらない）。
        #expect(grouped == MahjongYaku.displayOrder)
    }

    @Test("表に載っている役は、すべて役判定が実際に付けている役である")
    func everyRowIsImplemented() throws {
        let source = try Self.scoringSource()
        for yaku in MahjongYaku.allCases {
            #expect(
                source.contains(".\(yaku.rawValue)"),
                "早見表にあるのに MahjongScoring が付けていない役: \(yaku.name)(.\(yaku.rawValue))"
            )
        }
    }

    @Test("役名を判定側に文字列で直書きしていない（表とズレる余地を消す）")
    func scoringHasNoHardcodedYakuNames() throws {
        let source = try Self.scoringSource()
        #expect(
            !source.contains("MahjongYakuEntry(name:"),
            "MahjongYakuEntry を名前から作っている箇所が残っている（早見表に載らない役が生まれる）"
        )
    }

    // MARK: - 表の中身

    @Test("すべての役に名前・読み・成立条件・飜数の表記がある")
    func everyYakuHasMetadata() {
        for yaku in MahjongYaku.allCases {
            #expect(!yaku.name.isEmpty, "\(yaku.rawValue) の名前が空")
            #expect(!yaku.reading.isEmpty, "\(yaku.rawValue) の読みが空")
            #expect(!yaku.requirement.isEmpty, "\(yaku.rawValue) の成立条件が空")
            #expect(!yaku.hanText.isEmpty, "\(yaku.rawValue) の飜数表記が空")
        }
        let names = MahjongYaku.allCases.map(\.name)
        #expect(Set(names).count == names.count, "役名が重複している: \(names)")
    }

    @Test("飜数は門前が鳴きを下回らず、役満は13飜で固定")
    func hanValuesAreConsistent() {
        for yaku in MahjongYaku.allCases {
            if let open = yaku.openHan {
                #expect(open <= yaku.closedHan, "\(yaku.name) は鳴くと飜が上がっている")
                #expect(open >= 1, "\(yaku.name) の鳴き飜が 0 以下")
            }
            if yaku.isYakuman {
                #expect(yaku.closedHan == 13)
                #expect(yaku.han(isConcealed: false) == 13, "\(yaku.name) は鳴いても役満のはず")
            }
            #expect(yaku.han(isConcealed: true) == yaku.closedHan)
        }
    }

    @Test("門前限定の役は表に「門前のみ」と出る")
    func concealedOnlyYakuAreMarked() {
        let concealedOnly = MahjongYaku.allCases.filter(\.isConcealedOnly)
        #expect(
            Set(concealedOnly) == [
                .riichi, .ippatsu, .menzenTsumo, .pinfu, .iipeikou, .ryanpeikou, .chiitoitsu,
            ],
            "門前限定の役が判定側と食い違っている: \(concealedOnly.map(\.name))"
        )
        for yaku in concealedOnly {
            #expect(yaku.hanText.contains("門前のみ"), "\(yaku.name) の表記: \(yaku.hanText)")
        }
    }

    @Test("食い下がりのある役は表に「鳴きN飜」と出る")
    func openHanIsShown() {
        for yaku in MahjongYaku.allCases {
            guard let open = yaku.openHan, open != yaku.closedHan else { continue }
            #expect(
                yaku.hanText == "\(yaku.closedHan)飜（鳴き\(open)飜）",
                "\(yaku.name) の表記: \(yaku.hanText)"
            )
        }
        #expect(MahjongYaku.chinitsu.hanText == "6飜（鳴き5飜）")
        #expect(MahjongYaku.tanyao.hanText == "1飜")
        #expect(MahjongYaku.kokushi.hanText == "役満")
        #expect(MahjongYaku.dora.hanText == "1枚 1飜")
    }

    // MARK: - 牌例

    @Test("牌例の牌はすべて実在し、同じ牌を5枚以上並べていない")
    func examplesAreLegalTiles() {
        for yaku in MahjongYaku.allCases {
            var counts: [MahjongTile: Int] = [:]
            for group in yaku.example {
                // 面子は 2〜4 枚。国士無双だけは面子で作らないので 1 枚の組（重なる 1 枚）を許す。
                #expect(
                    (1...4).contains(group.count),
                    "\(yaku.name) の牌例に \(group.count) 枚の組がある"
                )
                for tile in group {
                    #expect(tile.isValid, "\(yaku.name) の牌例に値域外の牌がある: \(tile)")
                    counts[tile, default: 0] += 1
                }
            }
            for (tile, count) in counts {
                #expect(count <= 4, "\(yaku.name) の牌例で \(tile.displayName) が \(count) 枚")
            }
        }
    }

    @Test("牌の形で決まらない役（立直・ドラなど）は牌例を持たない")
    func situationalYakuHaveNoExample() {
        let withoutExample = MahjongYaku.allCases.filter { $0.example.isEmpty }
        #expect(
            Set(withoutExample) == [
                .riichi, .ippatsu, .menzenTsumo, .haitei, .houtei, .rinshan, .chankan,
                .dora, .uraDora,
            ],
            "牌例が無い役: \(withoutExample.map(\.name))"
        )
    }

    @Test("牌例の折り返しは面子を割らず、1行の枚数が上限に収まる")
    func exampleLinesKeepMeldsIntact() {
        for yaku in MahjongYaku.allCases {
            let lines = MahjongYakuSheet.exampleLines(yaku.example)
            #expect(lines.flatMap { $0 } == yaku.example, "\(yaku.name) で面子の並びが変わった")
            for line in lines {
                let tiles = line.reduce(0) { $0 + $1.count }
                // 1 つの面子だけで上限を超える形は無い（最大 4 枚）ので、必ず収まる。
                #expect(
                    tiles <= MahjongYakuSheet.maxTilesPerLine,
                    "\(yaku.name) の1行が \(tiles) 枚"
                )
            }
        }
        // 16 枚の四槓子はきちんと折り返る（1 行に詰め込んで見切れない）。
        #expect(MahjongYakuSheet.exampleLines(MahjongYaku.suukantsu.example).count == 2)
    }

    // MARK: - 判定が返す役と表の対応

    @Test("役判定が返す役は、必ず早見表に載っていて飜数も表と一致する")
    func scoredYakuMatchTheTable() {
        for (label, score) in Self.sampleScores() {
            guard let score else {
                Issue.record("\(label): 和了形として点数が付かなかった（牌姿が誤っている）")
                continue
            }
            #expect(!score.yaku.isEmpty, "\(label): 役が付いていない")
            for entry in score.yaku {
                #expect(
                    MahjongYaku.displayOrder.contains(entry.yaku),
                    "\(label): \(entry.name) が早見表に無い"
                )
                if entry.yaku.isDora {
                    #expect(entry.han >= 1, "\(label): \(entry.name) の飜数が \(entry.han)")
                } else {
                    #expect(
                        entry.han == entry.yaku.closedHan || entry.han == entry.yaku.openHan,
                        "\(label): \(entry.name) の飜数 \(entry.han) が表（\(entry.yaku.hanText)）に無い値"
                    )
                }
                #expect(entry.isYakuman == entry.yaku.isYakuman)
                // 役牌だけは牌の名前を足すので、表の名前で始まる形になる。
                #expect(
                    entry.name == entry.yaku.name || entry.name.hasPrefix(entry.yaku.name),
                    "\(label): 表の名前と食い違う: \(entry.name) / \(entry.yaku.name)"
                )
            }
        }
    }

    @Test("食い下がりの飜数は表の値と一致する（三色同順・混一色）")
    func openHanMatchesTheTable() {
        // 鳴いた三色同順（234m を上家からチー）。
        let open = MahjongScoring.score(
            hand: MahjongNotation.hand("234p234s567s99m"),
            calls: [MahjongCall(kind: .chi, tile: .characters(2), from: 3)],
            context: MahjongWinContext(winningTile: .bamboos(7), isTsumo: false, seatWind: 1)
        )
        let entry = open?.yaku.first { $0.yaku == .sanshokuDoujun }
        #expect(entry?.han == MahjongYaku.sanshokuDoujun.openHan)
        #expect(MahjongYaku.sanshokuDoujun.openHan == 1)
    }

    // MARK: - 開閉しても対局が壊れないこと

    @Test("早見表は対局のモデルを一切参照しない（開いても状態を動かしようがない）")
    func sheetDoesNotTouchTheModel() throws {
        // コメントには「モデルに触らない」という説明そのものが書いてあるので、コードだけを見る。
        let source = try Self.strippingComments(Self.sheetSource())
        for forbidden in ["MahjongModel", "GameServices", "snapshots", "services"] {
            #expect(
                !source.contains(forbidden),
                "早見表が \(forbidden) を参照している（対局の状態に触れる経路ができている）"
            )
        }
        // 引数を取らない = モデルを渡しようがないことをコンパイル時に固定する。
        _ = MahjongYakuSheet()
    }

    @Test("早見表を描画しても中断データと局面は 1 ビットも変わらない")
    @MainActor
    func renderingTheSheetLeavesTheGameUntouched() {
        let store = YakuSheetMemorySnapshotStore()
        let model = MahjongModel(
            services: GameServices(snapshots: store, ads: NoopAdService()),
            cpuDelay: .zero,
            seed: 11
        )
        model.startGame()
        model.discard(model.playerHand.tiles[0])
        let before = store.rawData(for: "mahjong4")
        let phase = model.phase
        let turnCount = model.turnCount
        let hand = model.playerHand
        #expect(before != nil, "前提: 対局中はスナップショットが残る")

        // シートを開く = この View が描画されること。モデルに触れないので何も動かない。
        let renderer = ImageRenderer(content: MahjongYakuSheet().frame(width: 390, height: 700))
        _ = renderer.cgImage

        #expect(store.rawData(for: "mahjong4") == before, "中断データが変わった")
        #expect(model.phase == phase)
        #expect(model.turnCount == turnCount)
        #expect(model.playerHand == hand)
    }

    @Test("対局画面は早見表を 1 タップで開くボタンを持っている")
    func viewWiresUpTheSheet() throws {
        let source = try Self.viewSource()
        #expect(
            source.contains(".sheet(isPresented: $showYakuSheet) { MahjongYakuSheet() }"),
            "早見表のシートが結線されていない"
        )
        #expect(
            source.contains("ToolbarItem(placement: .primaryAction)"),
            "ツールバーに早見表のボタンが無い"
        )
        #expect(source.contains("showYakuSheet = true"), "ボタンから開く経路が無い")
        // 開始シートと同時に出ると両方壊れるので、撮影用の経路は必ず開始シートを閉じてから開く。
        #expect(
            source.contains("-mahjongShowYaku"),
            "撮影用の DEBUG 経路が無い（シミュレータではタップを自動化できない）"
        )
    }

    // MARK: - ヘルパー

    /// 役が広く立つ牌姿をひととおり。判定 → 表の対応を実際の出力で確かめるために使う。
    private static func sampleScores() -> [(String, MahjongScore?)] {
        func ctx(
            _ win: String, tsumo: Bool = false, riichi: Bool = false, ippatsu: Bool = false,
            lastTile: Bool = false, seatWind: Int = 1, dora: [String] = [], ura: [String] = []
        ) -> MahjongWinContext {
            MahjongWinContext(
                winningTile: MahjongNotation.tile(win), isTsumo: tsumo, isRiichi: riichi,
                isIppatsu: ippatsu, isLastTile: lastTile, seatWind: seatWind, roundWind: 0,
                doraIndicators: dora.map(MahjongNotation.tile),
                uraIndicators: ura.map(MahjongNotation.tile)
            )
        }
        func s(_ hand: String, _ context: MahjongWinContext) -> MahjongScore? {
            MahjongScoring.score(hand: MahjongNotation.hand(hand), context: context)
        }
        return [
            ("立直・一発・ツモ・平和・断幺九",
             s("234m345p678s234s55p", ctx("2m", tsumo: true, riichi: true, ippatsu: true))),
            ("一盃口・三色同順",
             s("234m234m234p234s55s", ctx("4m"))),
            ("一気通貫・ドラ",
             s("123456789m345p11s", ctx("9m", dora: ["2m"]))),
            // 3m のロンで 1 つが明刻になるので、四暗刻ではなく三暗刻になる形。
            ("対々和・三暗刻・役牌",
             s("333m777p222s777z11s", ctx("3m"))),
            ("七対子・ドラ・裏ドラ",
             s("1144m7799p3366s11z", ctx("1z", riichi: true, dora: ["9m"], ura: ["2s"]))),
            ("国士無双",
             s("19m19p19s1234567z1m", ctx("1m"))),
            ("清一色",
             s("123456789p234p55p", ctx("5p"))),
            // 東（1z）のロンで 1 つが明刻になり、四暗刻に化けない。
            ("混一色・混老頭・対々和",
             s("111m999m111z555z77z", ctx("1z"))),
            ("海底摸月",
             s("234m345p678s234s55p", ctx("2m", tsumo: true, lastTile: true))),
            ("大三元",
             s("555z666z777z234m11p", ctx("1p"))),
            ("四暗刻",
             s("333m777p222s111z55s", ctx("5s", tsumo: true))),
        ]
    }

    /// 行コメント（`//` 以降）を落とす。文言の説明とコードを混同しないため。
    private static func strippingComments(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let range = line.range(of: "//") else { return line }
                return line[line.startIndex..<range.lowerBound]
            }
            .joined(separator: "\n")
    }

    private static func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GameMahjongTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private static func scoringSource() throws -> String {
        try source("Sources/GameMahjong/MahjongScoring.swift")
    }

    private static func sheetSource() throws -> String {
        try source("Sources/GameMahjong/MahjongYakuSheet.swift")
    }

    private static func viewSource() throws -> String {
        try source("Sources/GameMahjong/MahjongView.swift")
    }
}

/// 早見表の契約テスト専用のインメモリ保存先（生 JSON をそのまま比較したいので独自に持つ）。
private final class YakuSheetMemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        storage[gameID] = try JSONEncoder().encode(snapshot)
    }

    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = storage[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func clear(for gameID: String) { storage[gameID] = nil }

    func exists(for gameID: String) -> Bool { storage[gameID] != nil }

    func rawData(for gameID: String) -> Data? { storage[gameID] }
}
