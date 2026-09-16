import Foundation
import SwiftUI
import Testing
import Core
import GameKitTestSupport

/// 自己ベスト更新のリザルトに添える共有ボタン（#1043）。
///
/// `RecordLabel` は多くのゲームで「決着で行を増やさない」1 行の帯に同居している（#139・#148）ので、
/// ボタンを出す条件と、出しても行の高さが伸びないことを描画の寸法で固定する。
@Suite("記録の共有ボタン（#1043）")
@MainActor
struct RecordShareButtonTests {
    private static let context = RecordShareContext(
        gameTitle: "2048", url: URL(string: "https://apps.apple.com/jp/app/id6781719499")!, didTap: {}
    )

    /// 描いた寸法（pt）。何も描かないときは 0。
    private func size(_ view: some View) throws -> (width: Int, height: Int) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 1
        let image = try #require(renderer.cgImage, "描画できなかった")
        return (image.width, image.height)
    }

    private func result(isNewBest: Bool) -> RecordResult {
        RecordResult(
            record: PlayRecord(metric: .points, plays: 3, bestPoints: 12_340),
            update: RecordUpdate(points: isNewBest)
        )
    }

    @Test("自己ベストを更新した回だけ、配られた情報があればボタンが増える")
    func buttonAppearsOnlyOnNewBestWithContext() throws {
        let plain = try size(RecordLabel(result(isNewBest: true)))
        let shared = try size(RecordLabel(result(isNewBest: true)).environment(\.recordShare, Self.context))
        #expect(shared.width > plain.width, "更新した回に共有ボタンが出ていない")

        // 更新していない回は、配られていても出ない。
        let notBest = try size(RecordLabel(result(isNewBest: false)))
        let notBestShared = try size(
            RecordLabel(result(isNewBest: false)).environment(\.recordShare, Self.context)
        )
        #expect(notBestShared.width == notBest.width, "更新していない回に共有ボタンが出ている")
    }

    @Test("ボタンを足しても記録の行の高さは「自己ベスト更新！」バッジの行から伸びない（#139・#148）")
    func buttonDoesNotGrowTheRow() throws {
        let plain = try size(RecordLabel(result(isNewBest: true)))
        let shared = try size(RecordLabel(result(isNewBest: true)).environment(\.recordShare, Self.context))
        // 当たり判定の 44pt はボタンの外の負の余白で打ち消す。消し忘れると 44pt の行になる。
        #expect(shared.height <= plain.height, "共有ボタンで行が伸びた: \(plain.height) → \(shared.height)")
    }

    @Test("読み上げの結合の外に置き、共有ボタンとして読める")
    func buttonIsOutsideTheCombinedLabel() throws {
        let source = try SourceScan.packageSource("Sources/Core/RecordLabel.swift")
        let combine = try #require(source.range(of: ".accessibilityElement(children: .combine)"))
        let button = try #require(source.range(of: "RecordShareButton(message:"))
        #expect(combine.lowerBound < button.lowerBound, "共有ボタンが結合した読み上げ要素の中に入っている")
        #expect(source.contains(#".accessibilityLabel("記録をシェア")"#))
    }
}

/// 共有ボタンの結線（#1043）。配り口は App ターゲット（`HubView`）にあり GameKit のテストから
/// import できないため、`GameOpenWiringTests` と同じく `App/` 一式を走査して固定する。
@Suite("記録の共有の結線（#1043）")
struct RecordShareWiringTests {
    private static func count(_ needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    @Test("ハブがゲーム画面を作る 1 か所から配り、押したら share_tap へつなぐ")
    func hubProvidesContextFromTheDestination() throws {
        let source = try SourceScan.appSources()
        #expect(Self.count("gameDidTapShare(", in: source) == 1, "share_tap の発火点が1か所ではない")
        #expect(Self.count(".environment(\\.recordShare", in: source) == 1, "共有の情報の配り口が1か所ではない")
        #expect(
            source.range(
                of: #"module\.makeView\(services: services\)\s*\.environment\(\\\.recordShare, RecordShareContext\("#,
                options: .regularExpression
            ) != nil,
            "navigationDestination で作るゲーム画面に配っていない"
        )
    }
}
