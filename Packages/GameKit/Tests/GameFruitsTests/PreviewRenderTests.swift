import Core
import CoreGraphics
import Foundation
import ImageIO
import SpriteKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import GameFruits
import CoreTestSupport

/// 盆栽の見た目の確認画像を書き出す（#2388）。
///
/// 環境変数 `BONSAI_PREVIEW_DIR` にディレクトリを入れて走らせたときだけ、
/// - `tiers.png`: 11 段を盤の上と同じ倍率で並べた一覧（当たり判定の円つき）
/// - `overlap.png`: 大きい盆栽の上に小さい盆栽が載った場面（SpriteKit の面をそのまま描く。描けない環境では
///   同じ重なり順で SwiftUI に組んだもの）
/// を書き出す。無いときは何もせず通る（CI では走らない）。
///
///     BONSAI_PREVIEW_DIR=/tmp/bonsai swift test --package-path Packages/GameKit --filter PreviewRenderTests
@Suite("盆栽の確認画像（#2388）")
@MainActor
struct PreviewRenderTests {
    /// 盤の抽象単位 1 を何 px で描くか（盤の幅 400pt・3x 相当）。
    private static let unit: CGFloat = 12

    private var outputDirectory: URL? {
        guard let path = ProcessInfo.processInfo.environment["BONSAI_PREVIEW_DIR"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    @Test("11 段の一覧")
    func tiers() throws {
        guard let dir = outputDirectory else { return }
        let unit = Self.unit
        let view = HStack(alignment: .bottom, spacing: 16) {
            ForEach(FruitKind.allCases, id: \.self) { kind in
                let size = BonsaiArt.spriteSize(for: kind)
                VStack(spacing: 6) {
                    ZStack(alignment: .bottom) {
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 1.5)
                            .frame(width: kind.radius * 2 * unit, height: kind.radius * 2 * unit)
                        BonsaiIcon(kind)
                            .frame(width: size.width * unit, height: size.height * unit)
                    }
                    Text(verbatim: "\(kind.rawValue + 1) \(kind.name)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.black)
                }
            }
        }
        .padding(24)
        .background(Color(hex: FruitsPalette.box))
        let image = try #require(Self.render(view))
        try Self.write(image, to: dir.appendingPathComponent("tiers.png"))
    }

    @Test("重なった場面")
    func overlap() throws {
        guard let dir = outputDirectory else { return }
        // 大きい盆栽の上に小さい盆栽が載った盤。年齢を進めておき、生まれた直後の「膨らむ」演出に入らないようにする。
        var fruits: [Fruit] = []
        func place(_ kind: FruitKind, x: Double, y: Double) {
            fruits.append(Fruit(id: fruits.count + 1, kind: kind, x: x, y: y, age: 30, hasTouched: true))
        }
        place(.kuromatsu, x: 26, y: FruitKind.kuromatsu.radius)
        place(.kinmatsu, x: 72, y: FruitKind.kinmatsu.radius)
        place(.sakura, x: 20, y: FruitKind.kuromatsu.radius * 2 + FruitKind.sakura.radius - 1)
        place(.tsubaki, x: 32, y: FruitKind.kuromatsu.radius * 2 + FruitKind.tsubaki.radius - 1)
        place(.ume, x: 50, y: 34)
        place(.mikan, x: 72, y: FruitKind.kinmatsu.radius * 2 + FruitKind.mikan.radius - 1)
        place(.fuji, x: 88, y: FruitKind.kinmatsu.radius * 2 + FruitKind.fuji.radius + 2)
        place(.shinpaku, x: 50, y: 34 + FruitKind.ume.radius + FruitKind.shinpaku.radius - 2)
        place(.nanten, x: 8, y: FruitKind.kuromatsu.radius * 2 + 20)
        let snapshot = FruitsSnapshot(
            fruits: fruits, cursorX: 50, score: 0, heldKind: .sakura, nextKind: .ume,
            continueUsed: false, seed: 1, drawCount: 0, dropCount: 9, hasMadeKinmatsu: true
        )
        let store = MemorySnapshotStore()
        try store.save(snapshot, for: FruitsModel.gameID)
        let model = FruitsModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.field.fruits.count == fruits.count, "盤が復元されていない")

        // 盤と同じ倍率の静止画（SwiftUI。重なり順は面と同じ `FruitsScene.zPosition`）。
        let composed = try #require(Self.render(Self.composedOverlap(fruits: model.field.fruits)))
        try Self.write(composed, to: dir.appendingPathComponent("overlap.png"))

        // SpriteKit の面そのもの（面の大きさ = 盤の抽象単位なので小さい。重なり順の裏取り用）。
        let scene = FruitsScene(model: model)
        let size = CGSize(width: FruitField.Metrics.width * Self.unit, height: FruitField.Metrics.height * Self.unit)
        let skView = SKView(frame: CGRect(origin: .zero, size: size))
        skView.presentScene(scene)
        if let texture = skView.texture(from: scene) {
            try Self.write(texture.cgImage(), to: dir.appendingPathComponent("overlap-spritekit.png"))
        }
    }

    /// 盤と同じ重なり順（`FruitsScene.zPosition`）で SwiftUI に組んだ静止画。
    private static func composedOverlap(fruits: [Fruit]) -> some View {
        let unit = Self.unit
        let ordered = fruits.sorted {
            FruitsScene.zPosition(for: $0.kind, bottomY: $0.y - $0.radius)
                < FruitsScene.zPosition(for: $1.kind, bottomY: $1.y - $1.radius)
        }
        return ZStack(alignment: .bottomLeading) {
            Color(hex: FruitsPalette.box)
            ForEach(ordered, id: \.id) { fruit in
                let frame = BonsaiArt.spriteFrame(for: fruit.kind, x: fruit.x, y: fruit.y)
                BonsaiIcon(fruit.kind)
                    .frame(width: frame.width * unit, height: frame.height * unit)
                    .offset(x: frame.minX * unit, y: -frame.minY * unit)
            }
        }
        .frame(width: FruitField.Metrics.width * unit, height: FruitField.Metrics.height * unit, alignment: .bottomLeading)
    }

    private static func render(_ view: some View) -> CGImage? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 1
        return renderer.cgImage
    }

    private static func write(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination), "\(url.path) に書けない")
    }
}
