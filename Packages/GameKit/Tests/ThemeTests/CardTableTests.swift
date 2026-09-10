import Testing
import Foundation
import CoreGraphics
import Observation
import Core

/// 「札を場に並べて動かす」共通基盤（#524）を固定する。
///
/// ソリティア（#397）とフリーセル（#492）が同じ実装を共有するので、ここが崩れると
/// 2 つのゲームの盤が一度に壊れる。**位置合わせの算術**・**指の位置の共有**・
/// **ドロップ枠の集約規則**を数値で残し、加えて
/// **①追従表示だけが指の位置を読むこと**（#521 の性能対策が基盤側に残っていること）と
/// **②両ゲームが実際にこの基盤を使っていること**（受け入れ条件「フリーセルが再利用できる
/// API 境界」）をソースから見る。
@Suite("カードテーブル共通基盤")
@MainActor
struct CardTableTests {

    // MARK: - 追従表示の位置合わせ

    @Test("持ち上げた札の左上は、指の位置からつかんだ点のずれを引いた場所")
    func originSubtractsTheGrabOffset() {
        let origin = CardDragLayout.origin(
            location: CGPoint(x: 100, y: 200),
            grab: CGSize(width: 38, height: 36)
        )
        #expect(origin == CGPoint(x: 62, y: 164))
    }

    @Test("つかんだ点のずれが無ければ、指の位置がそのまま左上になる")
    func originWithoutGrabIsTheFingerPosition() {
        let origin = CardDragLayout.origin(location: CGPoint(x: 7, y: 9), grab: .zero)
        #expect(origin == CGPoint(x: 7, y: 9))
    }

    // MARK: - 指の位置

    @Test("位置の更新は購読しているビューに届く")
    func locationUpdateNotifiesObservers() async {
        let location = CardDragLocation()
        // 「point を読んだビューが無効化される」= 持ち上げた札が指について来る、の最小形。
        await confirmation("位置を読んだ購読者が起きる") { observed in
            withObservationTracking {
                _ = location.point
            } onChange: {
                observed()
            }

            location.point = CGPoint(x: 120, y: 240)
        }
    }

    @Test("参照型なので、渡した先から見ても同じ位置になる")
    func locationIsSharedByReference() {
        let location = CardDragLocation(point: CGPoint(x: 1, y: 2))
        let handedToDragLayer = location

        location.point = CGPoint(x: 30, y: 40)

        #expect(handedToDragLayer.point == CGPoint(x: 30, y: 40))
    }

    @Test("追従表示は指の位置を読む（読まなければ札が指について来ない）")
    func theDragLayerReadsTheFingerPosition() throws {
        let source = Self.strippingComments(try Self.baseSource())
        let layer = try #require(Self.declaration(of: "public struct CardDragLayer", in: source))

        #expect(
            layer.contains("location.point"),
            "追従表示が位置を読んでいない = 持ち上げた札が指について来ない"
        )
    }

    // MARK: - ドロップ枠の集約

    @Test("枠がまだ 1 つも報告されていなければ空")
    func dropFramesStartEmpty() {
        #expect(CardDropFramesKey<TestTarget>.defaultValue.isEmpty)
    }

    @Test("別々の子ビューが報告した枠は 1 つの辞書にまとまる")
    func dropFramesMergeAcrossChildren() {
        var value: [TestTarget: CGRect] = [.pile(0): CGRect(x: 0, y: 0, width: 10, height: 20)]
        CardDropFramesKey<TestTarget>.reduce(value: &value) {
            [.pile(1): CGRect(x: 30, y: 0, width: 10, height: 20)]
        }

        #expect(value.count == 2)
        #expect(value[.pile(1)] == CGRect(x: 30, y: 0, width: 10, height: 20))
    }

    @Test("同じ枠が二度報告されたら後から来たほうを採る（レイアウトが動いたあとの値が正）")
    func dropFramesPreferTheLatestReport() {
        var value: [TestTarget: CGRect] = [.pile(0): CGRect(x: 0, y: 0, width: 10, height: 20)]
        CardDropFramesKey<TestTarget>.reduce(value: &value) {
            [.pile(0): CGRect(x: 0, y: 44, width: 10, height: 20)]
        }

        #expect(value[.pile(0)] == CGRect(x: 0, y: 44, width: 10, height: 20))
    }

    private enum TestTarget: Hashable {
        case pile(Int)
    }

    // MARK: - 移動の補間の鍵

    @Test("同じ配札の同じ札は同じ鍵になる（移動が補間される）")
    func motionIDMatchesWithinADeal() {
        #expect(CardMotionID(deal: 3, card: 17) == CardMotionID(deal: 3, card: 17))
    }

    @Test("配り直しをまたぐと別の鍵になる（前の配札の居場所から飛んでこない）")
    func motionIDDiffersAcrossDeals() {
        #expect(CardMotionID(deal: 3, card: 17) != CardMotionID(deal: 4, card: 17))
    }

    // MARK: - 受け入れ条件: 2 つのゲームが同じ基盤を使っている

    // 読むのは**ゲームのソース一式**で、View のファイル 1 本ではない（#525）。
    // ソリティアは画面を盤面・救済オーバーレイ・操作エリアに割ったので、1 本を名指しすると
    // 「使っている」の検査は移した先を見失い、「戻っていない」の検査は空振りで素通りする。
    @Test("ソリティアとフリーセルが共通基盤を経由している", arguments: [
        "Sources/GameSolitaire",
        "Sources/GameFreeCell",
    ])
    func bothGamesGoThroughTheSharedBase(path: String) throws {
        let source = Self.strippingComments(try Self.readDirectory(path))

        for symbol in ["CardSlot(", "cardDropTarget(", "CardDragLayer(", "CardDealtView(",
                       "CardMotionID(", "CardDragLocation("] {
            #expect(source.contains(symbol), "\(path) が \(symbol) を使っていない")
        }
        // 写した実装が戻っていないこと（戻ると 2 か所で別々に育ち始める）。
        #expect(
            !source.contains(": PreferenceKey"),
            "\(path) にドロップ枠の PreferenceKey が再び定義されている"
        )
        #expect(
            !source.contains("strokeBorder"),
            "\(path) に空き枠の描画が再び直書きされている"
        )
    }

    // MARK: - ヘルパー

    private static func baseSource() throws -> String {
        try read("Sources/Core/CardTable.swift")
    }

    private static func read(_ path: String) throws -> String {
        try String(contentsOf: url(path), encoding: .utf8)
    }

    /// ディレクトリ直下の Swift ソースを名前順に連結する。
    /// パスを間違えて 0 件になると検査がまるごと素通りするので、件数も確かめる。
    private static func readDirectory(_ path: String) throws -> String {
        let base = url(path)
        let names = try FileManager.default
            .contentsOfDirectory(atPath: base.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        #expect(names.count >= 3, "\(path) のソースが読めていない")
        return try names
            .map { try String(contentsOf: base.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
    }

    private static func url(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ThemeTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent(path)
    }

    /// `header` で始まる宣言の本体（対応する閉じ括弧まで）を取り出す。
    private static func declaration(of header: String, in source: String) -> String? {
        guard let start = source.range(of: header) else { return nil }
        guard let open = source[start.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        while index < source.endIndex {
            if source[index] == "{" { depth += 1 }
            if source[index] == "}" {
                depth -= 1
                if depth == 0 { return String(source[open...index]) }
            }
            index = source.index(after: index)
        }
        return nil
    }

    /// 行コメント（`//` 以降）を落とす。URL の `://` は落とさない。
    /// 説明の文中に書かれた型名を「使っている」と数えないための前処理。
    private static func strippingComments(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
            var search = line.startIndex
            while let slashes = line.range(of: "//", range: search..<line.endIndex) {
                let precedesURL = slashes.lowerBound > line.startIndex
                    && line[line.index(before: slashes.lowerBound)] == ":"
                if !precedesURL { return line[line.startIndex..<slashes.lowerBound] }
                search = slashes.upperBound
            }
            return line[...]
        }.joined(separator: "\n")
    }
}
