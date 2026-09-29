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
    /// 画面に固定して走者より手前に出す演出（ゴールの紙吹雪・激突の土煙）。以前はシーン直下に
    /// z = 6 で置いていたが、層に z が入った（#942）あとは遠景（100）より奥になって見えなかった（#1069）。
    let effectLayer = SKNode()
    /// 走者の絵（#701）。`player` の唯一の子で、コマはテクスチャの差し替えで切り替える
    /// （`applyRiderFrame`）。落下・激突の演出（`playFallAnimation`）と無敵の点滅は親の
    /// `player` に掛けるので、ここには `SKAction` を掛けない。
    private let riderSprite = SKSpriteNode()
    /// 走者のコマのテクスチャ（起動時に 1 回だけ作る。`makeRiderTextures`）。
    private let riderTextures = RunnerScene.makeRiderTextures()
    /// たこ焼き（#956）のテクスチャ。走者と同じく起動時に 1 回だけ作り、面ごとの `addTakoyaki` は
    /// これを貼るだけ（毎面 `CGImage` を起こさない）。
    let takoyakiTexture = RunnerScene.makeTexture(RunnerPixelArt.takoyaki(), name: "たこ焼き")
    /// ゴールに浮かべる宝くじ（#1092）のテクスチャ。全ステージで同じ 1 枚。
    let lotteryTicketTexture = RunnerScene.makeTexture(RunnerPixelArt.lotteryTicket(), name: "宝くじ")
    /// 犬・イノシシの歩きのコマのテクスチャ（#975）。色が世界ごと（`RunnerWorld.creatures`）で、
    /// 港町では絵ごと猫・フォークリフトに着せ替わる（`RunnerWorld.Dressing`・#1009）ので、
    /// 全世界（5 つ）× 2 コマを起動時に 1 回だけ作り、面ごとの `addDog` / `addBoar` はいまの世界の 2 枚を
    /// 貼るだけ（毎面 `CGImage` を起こさない）。
    let dogTextures = RunnerScene.makeWalkTextures(name: "犬") { RunnerPixelArt.walker($0, world: $1) }
    let boarTextures = RunnerScene.makeWalkTextures(name: "イノシシ") { RunnerPixelArt.charger($0, world: $1) }
    /// 岩の枠の着せ替え（切り株・ロープの束・ドラム缶・#1009）のテクスチャ。色は世界によらないので
    /// 1 枚ずつ起動時に作る。岩塊（`makeRock`）は図形のままなのでテクスチャは無い。
    let blockTextures: [RunnerWorld.Dressing.Block: SKTexture] = [
        .stump: RunnerScene.makeTexture(RunnerPixelArt.stump(), name: "切り株"),
        .ropeCoil: RunnerScene.makeTexture(RunnerPixelArt.ropeCoil(), name: "ロープの束"),
        .drum: RunnerScene.makeTexture(RunnerPixelArt.drum(), name: "ドラム缶"),
    ]
    /// 突き上げ（#1010 竹の子・波しぶき）と、その予告（土の塚・泡）のテクスチャ。
    ///
    /// **起動時には作らず、その世界に入って最初に使うときに作ってキャッシュする**
    /// （#1010 の受け入れ条件）。突き上げが出るのは 19 面以降なので、1〜18 面しか遊ばない人の
    /// ぶんは 1 枚も起こさない。面ごとの `addShoot` は 2 回目以降キャッシュを貼るだけ。
    private var shootTextureCache: [RunnerWorld.Dressing.Shoot: SKTexture] = [:]
    private var shootCueTextureCache: [RunnerWorld.Dressing.Shoot: SKTexture] = [:]

    /// 伸び切った突き上げの絵。初回だけ作る。**絵の選び方は持たない**
    /// ——`RunnerPixelArt.shootArt(for:)` に着せ替えをそのまま渡すだけ。
    func shootTexture(_ style: RunnerWorld.Dressing.Shoot) -> SKTexture {
        if let cached = shootTextureCache[style] { return cached }
        let texture = Self.makeTexture(RunnerPixelArt.shootArt(for: style), name: "突き上げ \(style)")
        shootTextureCache[style] = texture
        return texture
    }

    /// 突き上げの予告（土の塚・泡）の絵。初回だけ作る。
    func shootCueTexture(_ style: RunnerWorld.Dressing.Shoot) -> SKTexture {
        if let cached = shootCueTextureCache[style] { return cached }
        let texture = Self.makeTexture(RunnerPixelArt.shootCueArt(for: style), name: "突き上げの予告 \(style)")
        shootCueTextureCache[style] = texture
        return texture
    }

    /// テスト用: いま作ってキャッシュしてある突き上げのテクスチャの種類
    /// （`RunnerWorldSceneTests` が「その世界のぶんしか作らない」を確かめる）。
    var cachedShootStyles: Set<RunnerWorld.Dressing.Shoot> {
        Set(shootTextureCache.keys).union(shootCueTextureCache.keys)
    }

    /// 高い塀（#1091 石垣・積まれたコンテナ）のテクスチャ。突き上げとまったく同じ扱いで、
    /// **起動時には作らず、その世界で最初に使うときに作ってキャッシュする**（決裁の受け入れ条件
    /// 「その世界に入ったときに作ってキャッシュする」「描画中に毎フレーム画像を作り直さない」）。
    /// 塀が出るのは 19 面以降なので、1〜18 面しか遊ばない人のぶんは 1 枚も起こさない。
    private var wallTextureCache: [RunnerWorld.Dressing.Wall: SKTexture] = [:]

    /// 高い塀の絵。初回だけ作る。**絵の選び方は持たない**
    /// ——`RunnerPixelArt.wallArt(for:)` に着せ替えをそのまま渡すだけ。
    func wallTexture(_ style: RunnerWorld.Dressing.Wall) -> SKTexture {
        if let cached = wallTextureCache[style] { return cached }
        let texture = Self.makeTexture(RunnerPixelArt.wallArt(for: style), name: "高い塀 \(style)")
        wallTextureCache[style] = texture
        return texture
    }

    /// テスト用: いま作ってキャッシュしてある高い塀のテクスチャの種類。
    var cachedWallStyles: Set<RunnerWorld.Dressing.Wall> { Set(wallTextureCache.keys) }
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
    /// エンドレス（#1086）では使わない（動く障害も `endless` の部品として使い回す）。
    var movingHazards: [MovingHazardView] = []
    /// ゴールに浮かべた宝くじ（#1092）。`rebuildCourse` で作り直し、ゴールに着いたら
    /// `syncGoalChase` が飛ばしていく。エンドレス（ゴールが無い）では nil のまま。
    var goalTicket: SKSpriteNode?
    /// 宝くじを置いた場所（揺れ・飛ばす動きの基準）。演出は `SKAction` ではなく
    /// `RunnerModel.goalChaseProgress` からここを基準に置き直す（撮影で止められるように）。
    var goalTicketBase: CGPoint = .zero

    /// いま「視差効果を減らす」が有効か（#210・#1092）。既定は OS の設定をそのつど読む。
    ///
    /// **テストは `reduceMotionOverride` にこのシーンぶんだけ与えること。**
    /// `Motion.override` はプロセス全体に効くグローバルな状態で、Swift Testing が
    /// スイートを並行実行するため、**別のスイートが立てた値をこちらが拾って揺れる**
    /// （実際に CI のフルスイートで「宝くじが飛ばない」と誤検知した。#828 と同型）。
    var reducesMotion: Bool { reduceMotionOverride ?? Motion.isReduceMotionEnabled }
    /// 上記の注入口。製品コードからは触らない（nil = OS の設定に従う）。
    var reduceMotionOverride: Bool?
    /// 崩れる足場（#1090）のノード。鍵は `stage.platforms` の添字で、`RunnerField.crumbleElapsed`
    /// と同じ引き方をする。`rebuildCourse` で作り直し、`sync` が崩れの進みを毎フレーム写す。
    /// エンドレス（#1086）には置かないので常に空。
    var crumblingPlatformNodes: [Int: CrumblingPlatformView] = [:]
    /// コース層（`courseLayer`）の x = 0 が指すワールド x（#1086）。
    ///
    /// エンドレスは距離が数百万単位まで伸びる。ノードをワールド座標のまま置くと、SpriteKit の
    /// 描画に使う単精度（Float・有効桁 7 桁弱）では 1 単位の 1/10 すら表せなくなり、長く走るほど
    /// 絵がガタつく。そこでノードは「ワールド x − この値」に置き、走者が
    /// `EndlessRenderer.rebaseSpan` 進むごとにこの値を区画の左端へ動かして、ノードを
    /// 同じだけ左へ戻す（`applyRenderOrigin`）。画面上の位置は
    /// `courseLayer.position.x + ノードの x = playerX − distance + ワールド x` で、この値に依らない。
    /// ステージ制は常に 0（従来どおりワールド座標そのまま）。
    var renderOrigin: Double = 0
    /// エンドレスの描画（部品の使い回しと、いま描いている区画・#1086）。ステージ制では nil のまま。
    var endless: EndlessRenderer?
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
        static let effects: CGFloat = 500
        /// 奥から手前の順。
        static let ordered: [CGFloat] = [clouds, backdrop, hills, course, player, effects]
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
        effectLayer.zPosition = LayerZ.effects
        addChild(cloudLayer)
        addChild(backdropLayer)
        addChild(hillLayer)
        addChild(courseLayer)
        buildPlayer()
        addChild(player)
        addChild(effectLayer)
        rebuildCourse()
        sync()
    }

    /// 1 フレーム描き終えたことを画面側へ知らせる（#1386）。**一度も描かないうちに止めると
    /// コースが出ないまま暗い矩形になる**ので、止める側はこれを待つ。止まったあとはこのフックも
    /// 来なくなり、再開の判断は画面側の局面の変化が担う。
    var onFrameRendered: (() -> Void)?

    override func didFinishUpdate() {
        onFrameRendered?()
    }

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdate = currentTime }
        // 初回フレームは経過時間が測れないので進めない。
        guard let last = lastUpdate, currentTime > last else { return }
        let dt = currentTime - last
        // 描画ループを止めていたあいだ（`RunnerView` の `onFrameRendered`・#1386）も `currentTime` は進み続ける。
        // 再開の 1 フレーム目は計時の穴とみなしてモデルは進めず、時計だけ合わせ直す（描画は写す）。
        guard dt <= RunnerRules.staleFrameThreshold else {
            sync()
            return
        }
        model.tick(dt: dt)
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

    /// 犬・イノシシの歩きのコマを、世界ごと（`RunnerWorld.allCases`）に `RunnerPixelArt.WalkFrame` の
    /// `rawValue` 順で作る。`sprite` にコマと世界を渡すと、その世界の着せ替えと色の絵が返る
    /// （`RunnerPixelArt.walker` / `charger`。朝・夕方・夜は従来どおり `dog` / `boar` の色違い）。
    private static func makeWalkTextures(
        name: String, sprite: (RunnerPixelArt.WalkFrame, RunnerWorld) -> PixelSprite
    ) -> [RunnerWorld: [SKTexture]] {
        var textures: [RunnerWorld: [SKTexture]] = [:]
        for world in RunnerWorld.allCases {
            textures[world] = RunnerPixelArt.WalkFrame.allCases.map { frame in
                makeTexture(sprite(frame, world), name: "\(name)のコマ \(frame)（\(world)）")
            }
        }
        return textures
    }

    /// ドット絵 1 枚を等倍のテクスチャにする。走者・たこ焼き・犬・イノシシ（今後の背景・障害物も）共通で、
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
