import Core
import Foundation
import SpriteKit
import SwiftUI

// MARK: - 世界の帯の背景（#2730）

/// ステージセレクト（`RunnerWorldMap`・C 案）の「世界の帯」に敷く、その世界の背景の絵。
///
/// **新しい絵は描かない**（会長決裁 2026-10-24）。走行画面と同じ `RunnerScene` を画面に出さずに組み
/// （`RunnerWorldSceneTests` と同じ作法）、空・雲・遠景・丘（`applyWorld`）と道路（`addGround`）を
/// そのまま 1 枚のビットマップに写す（`SKView.texture(from:crop:)`）。走者・障害は入れない——帯は
/// 「どの世界か」を見せる絵で、コースの中身ではない。
///
/// 1 世界につき 1 回だけ作り、プロセスのあいだ持つ（`cache`）。1 枚 1204×344px（約 1.6MB）で、
/// 画面に出た帯・つまみのぶんだけ `image(for:)` で起こす。
@MainActor
enum RunnerWorldBandArt {
    typealias Metrics = RunnerField.Metrics

    /// 帯の縦横比（幅 ÷ 高さ）。iPhone SE（中身の幅 343pt）で高さ 98pt、iPhone 17（370pt）で 106pt。
    /// モック（`docs/design/runner-60-stages/select-ui/`）の SE は 104pt だが、SE でモードの節の下に
    /// 6 面と記録の 1 行まで収めるため少し薄くした。
    static let aspectRatio: Double = 3.5

    /// 写す範囲の縦（シーンの座標・ワールド単位）。路肩の下（地盤）を少し含む 12 から、
    /// 丘の稜線（地面 34 + 34 = 68）と遠景の飾りを越えて、雲の帯の下端（93）までの 86。
    static let cropY: ClosedRange<Double> = 12...98

    /// 1 単位あたりの画素数。帯は iPhone 17 で 370pt（@3x で 1110px）に伸ばすので、幅 301 単位 × 4 で足りる。
    static let pixelsPerUnit: Double = 4

    /// 写す範囲（シーンの座標）。横は縦から縦横比で決め、画面（0…`Metrics.width`）が中央に来るように置く。
    /// 丘・雲のタイルは距離 0 で `[−2 間隔, 全幅 − 2 間隔)` を覆い（`RunnerParallax`）、道路は `roadSpan` に
    /// 敷くので、この範囲の左右に切れ目は出ない（`RunnerStageSelectUITests` が固定）。
    static var cropRect: CGRect {
        let height = cropY.upperBound - cropY.lowerBound
        let width = (height * aspectRatio).rounded()
        return CGRect(x: -(width - Metrics.width) / 2, y: cropY.lowerBound, width: width, height: height)
    }

    private static var cache: [RunnerWorld: CGImage] = [:]

    /// 帯に敷く道路の範囲（シーンの座標）。写す範囲（`cropRect`）より左右に広く、切れ目を見せない。
    static let roadSpan: ClosedRange<Double> = (-2 * Metrics.width)...(3 * Metrics.width)

    /// 世界の帯の絵。初回だけ組んで描き、以後は控えを返す。描けなかったときは nil（呼び出し側は空の色で埋める）。
    static func image(for world: RunnerWorld) -> CGImage? {
        if let cached = cache[world] { return cached }
        guard let image = render(world) else { return nil }
        cache[world] = image
        return image
    }

    /// 背景を組むためのシーン。**1 つを使い回す**——`RunnerScene` は起動時に走者・犬・イノシシ等の
    /// テクスチャを全世界ぶん起こすので、世界ごとに作ると 10 回ぶん払う。
    /// 空・雲・遠景・丘は `applyWorld` が世界ごとに作り直し、道路は `addGround` で別に敷く（コースの中身は使わない）。
    private static var scene: RunnerScene?

    /// その世界の背景（空・雲・遠景・丘・道路）だけを拡大した入れ物に移して 1 枚に写す。
    private static func render(_ world: RunnerWorld) -> CGImage? {
        let scene = scene ?? {
            let scene = RunnerScene(model: RunnerModel(startingAt: 1))
            // 先に 1 面のコースを組んで世代を合わせておく。合わせないと下の `sync()` が `rebuildCourse` を呼び、
            // 1 面の世界（朝）へ `applyWorld` し直して、最初に写す世界の丘・道路が朝になる。
            scene.rebuildCourse()
            self.scene = scene
            return scene
        }()
        scene.applyWorld(world)
        // 雲・丘のタイルを距離 0 の折り返し位置（`RunnerParallax`。画面の左にもタイルが来る）に置く。
        scene.sync()
        let road = SKNode()
        scene.addGround(from: roadSpan.lowerBound, to: roadSpan.upperBound, into: road)
        let layers: [(node: SKNode, z: CGFloat)] = [
            (scene.cloudLayer, RunnerScene.LayerZ.clouds),
            (scene.backdropLayer, RunnerScene.LayerZ.backdrop),
            (scene.hillLayer, RunnerScene.LayerZ.hills),
            (road, RunnerScene.LayerZ.course),
        ]
        return render(layers: layers, sky: world.palette.sky)
    }

    private static func render(layers: [(node: SKNode, z: CGFloat)], sky: UInt32) -> CGImage? {
        let crop = cropRect
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        // `texture(from:)` は画面の倍率（@3x）を掛けて描く（`contentScaleFactor` を 1 にしても効かない）。
        // 掛かると 1 枚が 3 倍角（約 15MB）になるので、倍率で割って画素数を `pixelsPerUnit` に合わせる。
        #if canImport(UIKit)
        let displayScale = Double(max(view.traitCollection.displayScale, 1))
        #else
        let displayScale = 1.0
        #endif
        let scale = pixelsPerUnit / displayScale
        // `scaled` に層を入れて拡大し、無変換の `root` を写す。`texture(from:crop:)` の範囲は
        // 写すノードの座標系なので、`root` を使えば「拡大後の点」で範囲を指定できる。
        let root = SKNode()
        let scaled = SKNode()
        scaled.setScale(scale)
        // 空はシーンの `backgroundColor`（ノードではない）なので、同じ色の面を一番奥に敷く。
        let skyNode = SKSpriteNode(color: RunnerPalette.color(sky), size: crop.size)
        skyNode.anchorPoint = .zero
        skyNode.position = crop.origin
        skyNode.zPosition = -1
        scaled.addChild(skyNode)
        for layer in layers {
            layer.node.removeFromParent()
            layer.node.zPosition = layer.z
            scaled.addChild(layer.node)
        }
        root.addChild(scaled)
        let pixelCrop = CGRect(
            x: crop.minX * scale, y: crop.minY * scale,
            width: crop.width * scale, height: crop.height * scale
        )
        return view.texture(from: root, crop: pixelCrop)?.cgImage()
    }
}
