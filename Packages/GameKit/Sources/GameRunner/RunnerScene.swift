import Core
import Foundation
import SpriteKit

/// チャリンコおじさんの描画とゲームループ（#494）。
///
/// **ここにゲームのルールは無い**。毎フレーム `RunnerModel.tick(dt:)` を呼び、結果として
/// 決まった `RunnerField` の状態をノードへ写すだけの層で、当たり判定も進行も知らない
/// （アクション枠の基盤規約）。
///
/// シーンの座標系はコースの抽象単位そのまま（`RunnerField.Metrics.width` × `.height`）で、
/// `scaleMode = .aspectFit` により表示サイズへ一括で拡大される。
/// **呼び出し側は SpriteView の枠を必ず同じ縦横比にすること**。
@MainActor
final class RunnerScene: SKScene {
    typealias Metrics = RunnerField.Metrics

    let model: RunnerModel
    private var lastUpdate: TimeInterval?
    /// コースのノードを作り直した時点の `RunnerModel.runGeneration`。
    var renderedGeneration = -1
    /// 直前の `sync()` で見た `phase`。`.falling` に入った最初のフレームだけ落下演出を
    /// 発火させるための「前回反映した世代」パターン（`renderedGeneration` と同じ考え方）。
    var lastSyncedPhase: RunnerPhase = .ready
    /// いま描いている世界（#703）。空・雲・丘・地面・岩の色と遠景の飾りはここから引く。
    var world: RunnerWorld
    /// 雲・丘・遠景を組み立てた時点の世界。`rebuildCourse` がステージの世界と比べ、
    /// 変わったときだけ背景を作り直す（6 面に 1 度。毎ステージ作り直さないのは従来どおり）。
    var renderedWorld: RunnerWorld?

    /// コース（地面・障害物・ゴール）。走者は動かさず、こちらを左へ流す。
    let courseLayer = SKNode()
    let player = SKNode()
    /// 走者の絵（#701）。`player` の唯一の子で、コマはテクスチャの差し替えで切り替える
    /// （`applyRiderFrame`）。落下・激突の演出（`playFallAnimation`）と無敵の点滅は親の
    /// `player` に掛けるので、ここには `SKAction` を掛けない。
    private let riderSprite = SKSpriteNode()
    /// 走者のコマのテクスチャ（起動時に 1 回だけ作る。`makeRiderTextures`）。
    private let riderTextures = RunnerScene.makeRiderTextures()
    /// たこ焼き（#956）のテクスチャ。走者と同じく起動時に 1 回だけ作り、面ごとの `addTakoyaki` は
    /// これを貼るだけ（毎面 `CGImage` を起こさない）。
    let takoyakiTexture = RunnerScene.makeTexture(RunnerPixelArt.takoyaki(), name: "たこ焼き")
    /// いま貼っているコマ。`applyRiderFrame` が同じコマの貼り直しを省くための控え。
    private var renderedRiderFrame: OjisanPixel.RiderFrame?
    /// クランクの位相。接地して進んだぶんだけ回す（空中では止まる）。半回転ごとに漕ぐコマが
    /// 入れ替わる（`RunnerRider.pedalFrame`）。
    var pedalPhase: Double = 0
    /// 前のフレームの `distance`（進んだぶんを出すため）。
    var lastRenderedDistance: Double?
    /// 空の雲。何も障害が無い区間が静止画に見える、というQAを受けて追加（会長QA）。
    /// コースより遅い速度で流す（視差）ので、コースとは別レイヤーに持つ。
    let cloudLayer = SKNode()
    /// 雲を並べる間隔（ワールド単位）。地面を作り直しても雲は作り直さないので、
    /// ステージが変わっても同じ雲がそのまま流れ続ける（世界が変わるときだけ作り直す）。
    static let cloudSpacing: Double = 46
    /// 動かない遠景（夕方の地平線の帯）。雲より手前・丘より奥に置く。
    /// 画面幅いっぱいの 1 枚なので流さない（流すと端が見える）。
    let backdropLayer = SKNode()
    /// コースに対する雲の流れる速さの比率（視差）。1 未満で遠くに見える。
    static let cloudParallax: Double = 0.3
    /// このコースのスピードアップアイテムのノード（`stage.pickups` と同じ並び）。
    /// `rebuildCourse` で作り直し、`sync` が `field.collectedPickupIndices` を見て消す。
    var pickupNodes: [SKNode] = []
    /// すでに消したピックアップの添字（`pickupNodes` の並び）。
    ///
    /// **件数ではなく添字で持つ**（#733）。チェックポイントから再開すると手前のアイテムは
    /// 取らないまま残るので、「取得数 = 先頭からの件数」とみなすと、先のアイテムを取った
    /// ときに手前（未取得）のノードを消してしまう。
    var removedPickupIndices: Set<Int> = []
    /// 動く障害（#796 飛び立つ鳥・#800 犬・#801 イノシシ）のノード。`rebuildCourse` で作り直し、
    /// `sync` が毎フレーム `RunnerHazard.frame(atRunnerDistance:)` の位置へ置き直す。
    var movingHazards: [MovingHazardView] = []
    /// すでに土煙を出したジャスト着地の数（#673）。`field.justLandingCount` が増えた
    /// フレームだけ演出を出すための控え。`rebuildCourse` で 0 に戻す。
    var renderedJustLandingCount = 0
    /// 走者に無敵の点滅（#797）を掛けているか。`field.isInvincible` と食い違ったフレームで
    /// 掛ける／外す（`syncInvincibility`）。`rebuildCourse` と落下演出の頭で false に戻す。
    var isBlinkingInvincible = false
    /// 無敵の点滅の `SKAction` のキー。落下演出（`playFallAnimation`）は `removeAllActions` で
    /// まとめて消すが、無敵が切れたときはこのキーの action だけを外す。
    static let invincibleBlinkKey = "invincibleBlink"

    /// 遠景の丘（奥・手前の2層）。`RunnerField.Metrics.groundY` から上端
    /// （`RunnerField.Metrics.height`）までの空が広く空くので、
    /// 何も無い帯にせず地平線側を丘の稜線で埋める（2026-09-10 会長QA「縦を活かす」対応）。
    /// 雲と同じく無限スクロールにするので、コースとは別レイヤーに持つ。
    let hillLayer = SKNode()
    /// 丘の稜線を並べる間隔（ワールド単位）。家並み（`RunnerWorld.townHouses`）の位置はこの幅の中で決まる。
    static let hillSpacing: Double = RunnerWorld.sceneryTileWidth
    /// コースに対する丘の流れる速さの比率（視差）。雲より近い＝雲より速いが、
    /// コースそのもの（1.0）よりは遅い。
    static let hillParallax: Double = 0.55

    init(model: RunnerModel) {
        self.model = model
        self.world = model.field.stage.number == 0 ? .morning : RunnerWorld.world(forStage: model.field.stage.number)
        super.init(size: CGSize(
            width: RunnerField.Metrics.width,
            height: RunnerField.Metrics.height
        ))
        scaleMode = .aspectFit
        backgroundColor = RunnerPalette.color(world.palette.sky)
        anchorPoint = .zero
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("RunnerScene はコードからのみ生成する")
    }

    /// 層の `zPosition`（#942）。SpriteKit は木全体で `zPosition` を合算して並べ、同値のときだけ
    /// 追加順になる。層が全部 0 だと、丘の中の家の屋根（子の z = 1・#929）が走者の車輪（0 / −1）や
    /// チェックポイントの旗の棒（0）より**前**に描かれ、跳んで屋根の高さに達したとき・旗が家と
    /// 重なるときに屋根が手前へ出た（会長 QA 2026-09-15）。層ごとに部品の相対 z（最大 7）より
    /// 十分離れた値を持たせ、層をまたいだ逆転を起こさない（`SceneLayerTests` が間隔を固定）。
    enum LayerZ {
        static let clouds: CGFloat = 0
        static let backdrop: CGFloat = 100
        static let hills: CGFloat = 200
        static let course: CGFloat = 300
        static let player: CGFloat = 400
        /// 奥から手前の順。
        static let ordered: [CGFloat] = [clouds, backdrop, hills, course, player]
        /// 部品（車輪・屋根・煙など）が層の中で使う相対 z の上限。これより層の間隔を広くとる。
        static let partMax: CGFloat = 10
    }

    /// 家並みの部品の相対 z（`hillLayer` の中）。丘の山は 0 なので、壁から先はその前。
    enum HouseZ {
        static let wall: CGFloat = 2
        static let roof: CGFloat = 3
        static let fixtures: CGFloat = 4
    }

    override func didMove(to view: SKView) {
        guard courseLayer.parent == nil else { return }
        // 奥から順に。雲・遠景・丘の中身は `rebuildCourse` が世界に合わせて組む（`applyWorld`）。
        cloudLayer.zPosition = LayerZ.clouds
        backdropLayer.zPosition = LayerZ.backdrop
        hillLayer.zPosition = LayerZ.hills
        courseLayer.zPosition = LayerZ.course
        player.zPosition = LayerZ.player
        addChild(cloudLayer)
        addChild(backdropLayer)
        addChild(hillLayer)
        addChild(courseLayer)
        buildPlayer()
        addChild(player)
        rebuildCourse()
        sync()
    }

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdate = currentTime }
        // 初回フレームは経過時間が測れないので進めない。
        guard let last = lastUpdate, currentTime > last else { return }
        model.tick(dt: currentTime - last)
        sync()
    }

    // MARK: - 組み立て

    /// 自転車に乗ったおじさん（#701）。`Core` の `OjisanPixel` のドット絵（40×36 ドット・右向き）を
    /// 1 枚のスプライトに貼り、コマ（漕ぐ 2 枚・跳ぶ・コケる・目を回す）はテクスチャの差し替えで
    /// 切り替える（`applyRiderFrame`）。**絵の寸法はここに書かない**——1 ドットの大きさと原点は
    /// `RunnerRider.placement` が基準のコマから決める（不透明部分の高さ = 図形時代の帽子の天辺、
    /// 原点 = 両輪の接地点の中央・車輪の底）。当たり判定（`Metrics.playerWidth` / `.playerHeight`）と
    /// ジャンプ物理は変えていない（絵は当たり判定より少し大きい。図形の頃と同じ）。
    private func buildPlayer() {
        let placement = Self.riderPlacement
        let sprite = OjisanPixel.rider(.ride0)
        riderSprite.anchorPoint = CGPoint(x: placement.anchorX, y: placement.anchorY)
        riderSprite.size = CGSize(
            width: Double(sprite.width) * placement.unit,
            height: Double(sprite.height) * placement.unit
        )
        applyRiderFrame(.ride0)
        player.addChild(riderSprite)
        player.position = CGPoint(x: Metrics.playerX, y: Metrics.groundY)
    }

    /// 走者の絵の置き方（`RunnerRider.placement` を参照）。全コマ共通。
    static let riderPlacement = RunnerRider.placement(for: OjisanPixel.rider(.ride0))

    /// 走者のコマのテクスチャ。**起動時に 5 枚を 1 回だけ作る**（`sync` は差し替えるだけで、
    /// 毎フレーム `CGImage` を起こさない）。等倍のビットマップを `SKSpriteNode.size` で拡大するので、
    /// にじまないよう `.nearest` にする（`PixelSprite` の注記）。
    private static func makeRiderTextures() -> [OjisanPixel.RiderFrame: SKTexture] {
        var textures: [OjisanPixel.RiderFrame: SKTexture] = [:]
        for frame in OjisanPixel.RiderFrame.allCases {
            textures[frame] = makeTexture(OjisanPixel.rider(frame), name: "走者のコマ \(frame)")
        }
        return textures
    }

    /// ドット絵 1 枚を等倍のテクスチャにする。走者・たこ焼き（今後の背景・障害物も）共通で、
    /// 呼ぶのは起動時の 1 回だけ。`name` は作れなかったときの表示用。
    private static func makeTexture(_ sprite: PixelSprite, name: String) -> SKTexture {
        guard let image = sprite.cgImage(scale: 1) else {
            preconditionFailure("\(name) のビットマップが作れない")
        }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return texture
    }

    /// 走者のコマを差し替える。同じコマなら何もしない。
    func applyRiderFrame(_ frame: OjisanPixel.RiderFrame) {
        guard frame != renderedRiderFrame else { return }
        renderedRiderFrame = frame
        riderSprite.texture = riderTextures[frame]
    }

    /// 雲ノードそのもの（`cloudBaseX` と対で、`sync` が毎フレーム位置を計算し直す）。
    var clouds: [SKNode] = []
    /// 雲の基準 x（`0, spacing, 2*spacing, …`）。`cloudLayer` は動かさず、
    /// 各雲を「距離に応じて `cloudSpacing * clouds.count` 幅でループする」座標に置き直すことで、
    /// ステージがどれだけ長くても雲を作り直さずに無限スクロールへ流せる。
    var cloudBaseX: [Double] = []

    /// 丘のタイルそのもの（`hillBaseX` と対で、`sync` が毎フレーム位置を計算し直す）。
    var hillTiles: [SKNode] = []
    /// 丘タイルの基準 x（雲と同じ「距離に応じて全タイル幅でループする」座標の仕組み）。
    var hillBaseX: [Double] = []
}
