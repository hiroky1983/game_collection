import Foundation
import SwiftUI
import Testing
import Core
import CoreTestSupport

/// レコメンドの枠（`RecommendationSlot`）が「出すものが無いときは何も描かない」ことを見る（#917）。
///
/// 以前はレコメンドも階段も無い決着で「ほかのあそび」（ハブへ戻るだけのボタン・#661）を
/// 出していたが、左上の戻ると同じ出口で押す価値が無く取り下げた。枠を使う画面
/// （`GameControlArea` / `RecommendationArea`）はひな形で高さを確保しているので、
/// 何も出なくても周りの寸法は動かない。
@Suite("レコメンドの枠")
@MainActor
struct RecommendationSlotTests {
    /// iPhone SE（第3世代）の内寸に近い幅。
    private static let width: CGFloat = 343

    /// 描いた高さ（pt）。何も描かないときは 0。
    private func height(_ view: some View, _ size: DynamicTypeSize = .large) -> Int {
        let renderer = ImageRenderer(content: view
            .frame(width: Self.width)
            .environment(\.dynamicTypeSize, size))
        renderer.scale = 1
        return renderer.cgImage?.height ?? 0
    }

    private func makeServices() -> GameServices {
        GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
    }

    /// レコメンドの部品（`services.recommendations`）を持たず、階段も渡さない決着。
    /// 通算 20 終局までレコメンドは一度も出ない（`RecommendationPolicy.firstShowThreshold`）ので、
    /// 大半の決着はこの状態になる。
    @Test("レコメンドも階段も無い決着では何も描かない")
    func drawsNothingWhenThereIsNothingToOffer() {
        let services = makeServices()
        #expect(height(RecommendationSlot(services: services, isFinished: false)) == 0)
        #expect(height(RecommendationSlot(services: services, isFinished: true)) == 0)
        #expect(height(RecommendationSlot(services: services, isFinished: true, ladder: nil)) == 0)
    }

    /// 「ほかのあそび」の部品が復活していないことをソースで見る（#917 の取り下げを固定）。
    /// コメントの言及に当たらないよう、コードの行だけを見る。
    @Test("ほかのあそびの部品は枠から消えている")
    func otherGamesCardIsGone() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GameChromeTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources/Core/RecommendationCard.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let code = source.split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        #expect(!code.contains("OtherGamesCard"))
        #expect(!code.contains("showsOtherGames"))
    }
}
