import Foundation
import SpriteKit

/// SpriteKit の描画・配色（#494）。
///
/// **SpriteKit の面は SwiftUI の `Theme` に追従しない**（`SKColor` はライト / ダークの動的色を
/// 持てる形で使えず、シーンの背景も自前で塗る）。盤・駒・牌と同じ「モードによらず固定の面」
/// として扱う（基盤規約 §4。値はブロック崩しの `BlocksPalette` と揃えてある）。
///
/// 空・雲・丘・地面・岩は**世界（`RunnerWorld`）ごとに差し替わる**（#703）。ここにある
/// `sky` 〜 `rockDark` は 13〜18 面の夜の値であり、描画側は `RunnerWorld.palette` を読む。
/// 定数を残してあるのは、ここに書かれた「なぜこの色か」の注記（脚と空の被り・岩の茶系 NG）が
/// 世界ごとの配色を選ぶときの物差しになるため。
enum RunnerPalette {
    /// 空。ブロック崩しの地（`0x1E2233`）より明るくして、屋外の昼に見せる。
    static let sky: UInt32 = 0x2E4066
    /// 地面の上面（草）。
    static let groundTop: UInt32 = 0x22C3BE
    /// 地面の断面（土）。**空と系統の違う暖色にする**。同じ寒色の濃淡で塗ると、
    /// 地面と空の境目も穴の切れ目も見分けが付かない（最初の実機確認で判明）。
    static let groundBody: UInt32 = 0x6B4A32
    /// 障害物（岩）の明るい面（日の当たる頂の面）。**茶系は使えない**。地面の断面
    /// （`groundBody`）と同系になり、実機では遠景の丘（紺）とも地面とも見分けが付かず
    /// 「何なのか分からない」というQAが続いた（会長 2026-09-10「岩のデザインはNG」）。
    /// 空・丘の紺、地表のティール、断面の茶のどれとも系統の違う明るいストーングレー
    /// 3階調にして、輪郭線なしでも岩塊が浮き出るようにする。
    static let rockLight: UInt32 = 0xC2C8D2
    /// 障害物（岩）の本体（中間色）。
    static let rockBody: UInt32 = 0x939AA8
    /// 障害物（岩）の陰（陰の面・接地陰）。
    static let rockDark: UInt32 = 0x565D6B
    /// 自転車の車体。`Theme.Fill.coral` と同じ値。
    static let bike: UInt32 = 0xFF8A7E
    /// 車輪。
    static let wheel: UInt32 = 0xFFF6EC
    /// おじさんの肌。
    static let skin: UInt32 = 0xF3C9A6
    /// 肌の陰（鼻・耳）。輪郭線を引かずに顔の起伏を出すため、肌より一段暗い色で置く。
    static let skinShade: UInt32 = 0xD9A57F
    /// おじさんの服。
    static let shirt: UInt32 = 0xB3A6F0
    /// 服の陰（奥の腕）。手前の胴と同じ色だと、腕が胴に溶けて1つの塊に見える。
    static let shirtShade: UInt32 = 0x8477C9
    /// ズボン（手前の脚）。**空（`sky`）と近い濃い青は使えない**。脚は空を背に描かれるので、
    /// 同系の暗い色にすると漕いでいるのに脚が見えない（最初の実機確認で判明）。
    static let pants: UInt32 = 0xE0B27C
    /// ズボンの陰（奥の脚）。左右の脚が重なる位相でも前後が分かるようにする。
    static let pantsShade: UInt32 = 0xAD8351
    /// 髪・口ひげ。「おじさん」と分かる要素はここだけなので、肌とはっきり差を付ける。
    static let hair: UInt32 = 0x4A3B33
    /// 靴。
    static let shoe: UInt32 = 0x2B2B33
    /// 金具（サドル・クランク・握り）。**空より明るい灰色**にする。暗い灰色にすると
    /// サドルだけが黒い塊として浮き、自転車の一部に見えない。
    static let metal: UInt32 = 0x8A93A6
    /// ゴールの旗。
    static let goal: UInt32 = 0xFF8FB1
    /// ゴールの旗の陰（奥側の 1 枚）。チェックポイントの旗と同じ厚みの出し方（#703）。
    static let goalShade: UInt32 = 0xD9678F
    /// ゴールの旗の文字。チェックポイントの旗（`checkpointText`）と同じく、旗より十分暗い色で
    /// コントラストを取る（白抜きは実機で読めなかった教訓）。
    static let goalText: UInt32 = 0x4A1730
    /// 夕方の川（`RunnerWorld.Scenery.riverside`）の水面。丘の紫より暗い群青にして、
    /// 走者の下半身（サーモンの車体・黄土の脚）がこの上でいちばん映えるようにする。
    static let riverWater: UInt32 = 0x3E3E7E
    /// 川面の照り返し（細い帯）。夕日の色を水面に落として「川」だと読めるようにする。
    static let riverGlint: UInt32 = 0xF2B08A
    /// 夕方の地平線の帯。空の桃色（`RunnerWorld.evening`）に対して橙を足し、
    /// 「橙〜桃色の空」を 2 色で作る。丘の後ろに置くので走者とは重ならない。
    static let sunsetGlow: UInt32 = 0xF0955C
    /// 夜のビルの影（`RunnerWorld.Scenery.cityLights`）。近景の丘（`hillNear`）よりさらに暗い紺。
    static let building: UInt32 = 0x16223A
    /// ビルの窓の灯り。暖色の小さな矩形で、夜の空と影に対して唯一の明るい点になる。
    static let buildingWindow: UInt32 = 0xFFD98A
    /// 朝の下町の家（`RunnerWorld.Scenery.townHouses`）。壁はクリーム、屋根は瓦の赤茶、窓は空より濃い水色。
    static let houseWall: UInt32 = 0xFFF1DC
    static let houseRoof: UInt32 = 0xC9624A
    static let houseWindow: UInt32 = 0x5FA8D6
    /// 穴の縁の警告帯。地面と同系色だと縁が分からず、落ちるかどうかの判断がつかない
    /// というQAを受けて追加（会長QA）。工事の柵らしく黒（`pitEdgeDark`）と交互に塗る。
    static let pitEdge: UInt32 = 0xFFD447
    static let pitEdgeDark: UInt32 = 0x2B2B33
    /// 穴の中身（奈落）。縁の帯だけでは「穴の中はただの空」に見え、幅の実感が湧かない
    /// というQAを受けて追加（会長QA）。地面の断面よりさらに暗い色で、地面と穴を塗り分ける。
    static let pitVoid: UInt32 = 0x141824
    /// 雲。空より明るい半透明の白。
    static let cloud: UInt32 = 0xFFFFFF
    /// 遠景の丘（奥）。空より一段暗い寒色で、空との境目が分かる程度の差に留める。
    static let hillFar: UInt32 = 0x263A5C
    /// 近景の丘（手前）。奥の丘よりさらに暗く、地面（`groundBody`）との重なりでも
    /// 手前にあると分かるようにする。
    static let hillNear: UInt32 = 0x1F2F4C
    /// チェックポイントの旗。ゴール（`goal`）と見分けられる別の色にする。
    static let checkpoint: UInt32 = 0x5FA8FF
    /// チェックポイントの旗の陰（奥側）。ゴールの旗と同じ厚みの出し方を踏襲する。
    static let checkpointShade: UInt32 = 0x3D7BD9
    /// チェックポイントの旗の文字。白抜き（`wheel`）は旗の水色に対して薄く、実機で
    /// 読めなかった（会長QA「旗の文字もいまだに見えない」）。旗より十分暗い紺で
    /// コントラストを取る。
    static let checkpointText: UInt32 = 0x14284A
    /// 鳥（`RunnerHazardKind.bird`）の胴体。岩の茶系・空の寒色とは別系統の色にして、
    /// 地を這う障害物と空を飛ぶ障害物を見分けられるようにする（会長QA）。
    static let birdBody: UInt32 = 0x4FAE71
    /// 鳥の翼・尾羽の奥の1枚。旧版は胴体より明るい緑だったが、明るい腹・白目と
    /// 差し色が渋滞して面の切れ目が読めなかった。胴体より一段**濃い**緑にして、
    /// 畳んだ翼と尾羽の重なりが遠目でも影として見えるようにする（会長QA 2026-09-10
    /// 「鳥もデザイン改善して欲しい」）。
    static let birdWing: UInt32 = 0x2F7D4E
    /// 鳥のくちばし・畳んだ足。胴体と対比が付く暖色にする（「何の生き物か分からない」対策）。
    static let birdBeak: UInt32 = 0xFFB648
    /// 鳥の奥の翼。手前の翼（`birdWing`）よりさらに暗くして、羽ばたきで手前・奥の
    /// 2枚が重なる瞬間でも別の翼だと分かるようにする（飛行化・2026-09-10 会長QA）。
    static let birdWingFar: UInt32 = 0x1F5C38
    /// 鳥の腹（明るい差し色）。胴体の丸だけだと単色の玉に見えるため、腹だけ明るくして
    /// 立体感と「鳥らしさ」を出す。
    static let birdBelly: UInt32 = 0xE8F5E0
    /// 鳥の目（小さな黒丸）。生き物だと分かる最小限の要素。
    static let birdEye: UInt32 = 0x1F2B22
    /// 犬（#800）の体。柴犬のような明るい茶。岩のグレー・地面の暖色（テラコッタ・砂色）より
    /// 彩度が高く、朝・夕方の路面でも輪郭が読める。
    static let dogBody: UInt32 = 0xD9944A
    /// 犬の耳・鼻・目と、脚の陰。
    static let dogDark: UInt32 = 0x5A3418
    /// 犬の腹・口元の差し色。
    static let dogBelly: UInt32 = 0xF6E7CF
    /// 犬の吠え声（口元の白い吹き出し）。
    static let dogBark: UInt32 = 0xFFFFFF
    /// イノシシ（#801）の体。犬より暗く赤みの少ない焦げ茶。夕方の紫の丘・夜の紺の空のどちらを
    /// 背にしても沈まない明度にしてある。
    static let boarBody: UInt32 = 0x6B4226
    /// イノシシの背中のたてがみ・脚。
    static let boarDark: UInt32 = 0x3E2414
    /// イノシシの鼻先。
    static let boarSnout: UInt32 = 0xB88A6A
    /// イノシシの牙・目の白。
    static let boarTusk: UInt32 = 0xF4EFE6
    /// スピードアップアイテムの後光（丸）。「電気を帯びた玉」に見えるよう寒色にする。
    static let pickupAura: UInt32 = 0x5CE1E6
    /// スピードアップアイテムの稲妻（本体）。後光との対比を出すため明るい暖色にする。
    /// 以前は細い矩形2枚で稲妻を表していたが小さすぎて読めなかった（会長QA
    /// 「何なのかパッと見てわからない」・2026-09-10）ため、太い稲妻の1枚絵に描き直した。
    static let pickupBolt: UInt32 = 0xFFE066
    /// 稲妻の縁取り。後光と同系色の玉の上に置いても輪郭が沈まないようにする。
    static let pickupBoltOutline: UInt32 = 0xB8860B
    /// たこ焼き（#797）の舟皿。経木の薄い生成りで、台座の床板（`platformDeck`）よりやや黄み。
    static let takoyakiTray: UInt32 = 0xF3E2BE
    /// たこ焼きの玉（焼き色）。岩のグレー・地面の茶・鳥の緑のどれとも系統が違う、食べ物の狐色。
    static let takoyakiBall: UInt32 = 0xD98C3F
    /// たこ焼きに掛かったソース。玉の上に載る濃い茶で、玉との明暗差だけで丸みを出す（輪郭線は引かない）。
    static let takoyakiSauce: UInt32 = 0x6E3A16
    /// 青のり（小さな緑の点）。
    static let takoyakiAonori: UInt32 = 0x3F8F4C
    /// 紅しょうが（小さな赤い点）。
    static let takoyakiBenishoga: UInt32 = 0xE9536B
    /// 台座（#674）の上面＝歩く床板。**ここがいちばん明るい**——「乗れる場所」は上面なので、
    /// 画面の中で最初に目に入るのが上面になるよう、コースのどの面よりも明るい色を当てる。
    /// 地表のティール（`groundTop`）・岩のストーングレー・空の紺のどれとも系統が違う
    /// 木肌寄りのクリーム。
    static let platformDeck: UInt32 = 0xF4E3C1
    /// 台座の骨組み（工事の足場の単管）。安全色のオレンジ。自転車の車体（`bike` = サーモン）
    /// より明確に濃く、岩のグレー・地面の茶とも系統が違う。
    static let platformFrame: UInt32 = 0xC2571F
    /// 台座の骨組みの陰（支柱・筋交いの奥側）と、床板の下の影。骨組みより一段暗くして、
    /// 輪郭線を引かずに「床板が骨組みの上に載っている」段差を出す（岩・鳥と同じ作法）。
    static let platformShade: UInt32 = 0x7A3310

    /// スピードアップ床の路面（#672）。ふつうの地表（`groundTop` のティール）と
    /// **一目で違う区間だ**と分かる必要があるので、アイテムの後光（`pickupAura`）と
    /// 同じ寒色系にして「この色＝速さ」で揃える。地表より明るくして、走者の足元でも沈まない。
    static let boostFloorTop: UInt32 = 0x2FC4E6
    /// スピードアップ床の縁取り（路面より暗い青）。帯の上下に引いて「路面に貼られた加速帯」に見せる。
    static let boostFloorEdge: UInt32 = 0x1B7FA3
    /// スピードアップ床の矢印。路面より明るい暖色にして、床の色に埋もれないようにする。
    /// 進行方向（右）を向いた三角を並べ、「乗ると前へ押される区間」だと色以外でも伝える
    /// （色だけに頼らない・基盤規約のアクセシビリティ要件）。
    static let boostFloorArrow: UInt32 = 0xFFE066

    static func color(_ hex: UInt32) -> SKColor {
        SKColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

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
    private typealias Metrics = RunnerField.Metrics

    private let model: RunnerModel
    private var lastUpdate: TimeInterval?
    /// コースのノードを作り直した時点の `RunnerModel.runGeneration`。
    private var renderedGeneration = -1
    /// 直前の `sync()` で見た `phase`。`.falling` に入った最初のフレームだけ落下演出を
    /// 発火させるための「前回反映した世代」パターン（`renderedGeneration` と同じ考え方）。
    private var lastSyncedPhase: RunnerPhase = .ready
    /// いま描いている世界（#703）。空・雲・丘・地面・岩の色と遠景の飾りはここから引く。
    private var world: RunnerWorld
    /// 雲・丘・遠景を組み立てた時点の世界。`rebuildCourse` がステージの世界と比べ、
    /// 変わったときだけ背景を作り直す（6 面に 1 度。毎ステージ作り直さないのは従来どおり）。
    private var renderedWorld: RunnerWorld?

    /// コース（地面・障害物・ゴール）。走者は動かさず、こちらを左へ流す。
    private let courseLayer = SKNode()
    private let player = SKNode()
    private let frontWheel = SKShapeNode(circleOfRadius: 2.6)
    private let rearWheel = SKShapeNode(circleOfRadius: 2.6)
    /// 漕ぐ脚（奥・手前）と、それに合わせて回るクランクの腕（#569）。
    /// 形は毎フレーム `RunnerRider` が返す座標で置き直す（寸法をここに書かない）。
    private let farThigh = SKSpriteNode()
    private let farShin = SKSpriteNode()
    private let farKnee = SKShapeNode(circleOfRadius: 0.55)
    private let farShoe = SKSpriteNode()
    private let nearThigh = SKSpriteNode()
    private let nearShin = SKSpriteNode()
    private let nearKnee = SKShapeNode(circleOfRadius: 0.55)
    private let nearShoe = SKSpriteNode()
    private let crankArm = SKSpriteNode()
    /// クランクの位相。接地して進んだぶんだけ回す（空中では止まる）。
    private var pedalPhase: Double = 0
    /// 前のフレームの `distance`（進んだぶんを出すため）。
    private var lastRenderedDistance: Double?
    /// 空の雲。何も障害が無い区間が静止画に見える、というQAを受けて追加（会長QA）。
    /// コースより遅い速度で流す（視差）ので、コースとは別レイヤーに持つ。
    private let cloudLayer = SKNode()
    /// 雲を並べる間隔（ワールド単位）。地面を作り直しても雲は作り直さないので、
    /// ステージが変わっても同じ雲がそのまま流れ続ける（世界が変わるときだけ作り直す）。
    private static let cloudSpacing: Double = 46
    /// 動かない遠景（夕方の地平線の帯）。雲より手前・丘より奥に置く。
    /// 画面幅いっぱいの 1 枚なので流さない（流すと端が見える）。
    private let backdropLayer = SKNode()
    /// コースに対する雲の流れる速さの比率（視差）。1 未満で遠くに見える。
    private static let cloudParallax: Double = 0.3
    /// このコースのスピードアップアイテムのノード（`stage.pickups` と同じ並び）。
    /// `rebuildCourse` で作り直し、`sync` が `field.collectedPickupIndices` を見て消す。
    private var pickupNodes: [SKNode] = []
    /// すでに消したピックアップの添字（`pickupNodes` の並び）。
    ///
    /// **件数ではなく添字で持つ**（#733）。チェックポイントから再開すると手前のアイテムは
    /// 取らないまま残るので、「取得数 = 先頭からの件数」とみなすと、先のアイテムを取った
    /// ときに手前（未取得）のノードを消してしまう。
    private var removedPickupIndices: Set<Int> = []
    /// 動く障害（#796 飛び立つ鳥・#800 犬・#801 イノシシ）のノード。`rebuildCourse` で作り直し、
    /// `sync` が毎フレーム `RunnerHazard.frame(atRunnerDistance:)` の位置へ置き直す。
    private var movingHazards: [MovingHazardView] = []
    /// すでに土煙を出したジャスト着地の数（#673）。`field.justLandingCount` が増えた
    /// フレームだけ演出を出すための控え。`rebuildCourse` で 0 に戻す。
    private var renderedJustLandingCount = 0
    /// 走者に無敵の点滅（#797）を掛けているか。`field.isInvincible` と食い違ったフレームで
    /// 掛ける／外す（`syncInvincibility`）。`rebuildCourse` と落下演出の頭で false に戻す。
    private var isBlinkingInvincible = false
    /// 無敵の点滅の `SKAction` のキー。落下演出（`playFallAnimation`）は `removeAllActions` で
    /// まとめて消すが、無敵が切れたときはこのキーの action だけを外す。
    private static let invincibleBlinkKey = "invincibleBlink"

    /// 遠景の丘（奥・手前の2層）。`RunnerField.Metrics.groundY` から上端
    /// （`RunnerField.Metrics.height`）までの空が広く空くので、
    /// 何も無い帯にせず地平線側を丘の稜線で埋める（2026-09-10 会長QA「縦を活かす」対応）。
    /// 雲と同じく無限スクロールにするので、コースとは別レイヤーに持つ。
    private let hillLayer = SKNode()
    /// 丘の稜線を並べる間隔（ワールド単位）。
    private static let hillSpacing: Double = 60
    /// コースに対する丘の流れる速さの比率（視差）。雲より近い＝雲より速いが、
    /// コースそのもの（1.0）よりは遅い。
    private static let hillParallax: Double = 0.55

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

    override func didMove(to view: SKView) {
        guard courseLayer.parent == nil else { return }
        // 奥から順に。雲・遠景・丘の中身は `rebuildCourse` が世界に合わせて組む（`applyWorld`）。
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

    /// 自転車に乗ったおじさん。**既存作品の意匠には寄せず**、丸と長方形だけで組む（#494 の権利チェック）。
    ///
    /// 「棒人間レベル」というQAを受けた底上げ（#569 決裁A）。**輪郭線は引かず**、色の差だけで
    /// 面を分ける（1 単位が数 pt にしか描かれないので、線を足すと潰れて滲む）。増やしたのは
    /// ①漕ぐ脚 ②ハンドルを握る腕 ③顔（目・鼻・口ひげ）とつばのある帽子 ④スポーク——
    /// いずれも当たり判定には関わらない見た目だけの追加で、走者の占める寸法
    /// （`Metrics.playerWidth` / `.playerHeight`）は変えていない。
    private func buildPlayer() {
        buildBike()
        buildLegs()
        buildRiderBody()
        buildFace()
        player.position = CGPoint(x: Metrics.playerX, y: Metrics.groundY)
    }

    /// 自転車（車輪・スポーク・車体・サドル・クランク）。
    private func buildBike() {
        for wheel in [frontWheel, rearWheel] {
            wheel.fillColor = .clear
            wheel.strokeColor = RunnerPalette.color(RunnerPalette.wheel)
            wheel.lineWidth = 0.7
            // スポーク。無地の円は回しても回転が見えず、止まっているように見えていた。
            // 車輪の子にしておけば `zRotation` にそのまま追従する。
            for i in 0..<3 {
                let spoke = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.wheel),
                                         size: CGSize(width: 5.0, height: 0.35))
                spoke.zRotation = CGFloat(Double(i) * .pi / 3)
                wheel.addChild(spoke)
            }
            player.addChild(wheel)
        }
        frontWheel.position = CGPoint(x: 2.6, y: 2.6)
        rearWheel.position = CGPoint(x: -2.6, y: 2.6)

        // 車体。**太い1本の棒ではなく細い管を組む**。棒1枚だとクランクとペダルが棒に
        // 埋まって漕いでいるのが見えず、自転車の形にも見えなかった（最初の実機確認で判明）。
        addTube(from: RunnerRider.rearHub, to: RunnerRider.crank)     // チェーンステー
        addTube(from: RunnerRider.crank, to: RunnerRider.seatBase)    // シートチューブ
        addTube(from: RunnerRider.seatBase, to: RunnerRider.rearHub)  // シートステー
        addTube(from: RunnerRider.crank, to: RunnerRider.headTop)     // ダウンチューブ
        addTube(from: RunnerRider.seatBase, to: RunnerRider.headTop)  // トップチューブ
        addTube(from: RunnerRider.headTop, to: RunnerRider.frontHub)  // フォーク
        addTube(from: RunnerRider.headTop, to: RunnerRider.grip)      // ステム

        // 握りとサドル。手と腰の行き先を絵の上でも示す（腕と脚の付け根が浮かないようにする）。
        let grip = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.metal),
                                size: CGSize(width: 1.4, height: 0.5))
        grip.position = CGPoint(x: RunnerRider.grip.x, y: RunnerRider.grip.y)
        let saddle = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.metal),
                                  size: CGSize(width: 2.2, height: 0.6))
        saddle.position = CGPoint(x: RunnerRider.seatBase.x, y: RunnerRider.seatBase.y + 0.3)
        for node in [grip, saddle] { player.addChild(node) }

        // クランク（ペダルの回転中心と、回る腕）。
        let chainring = SKShapeNode(circleOfRadius: 0.8)
        chainring.fillColor = .clear
        chainring.strokeColor = RunnerPalette.color(RunnerPalette.metal)
        chainring.lineWidth = 0.4
        chainring.position = CGPoint(x: RunnerRider.crank.x, y: RunnerRider.crank.y)
        player.addChild(chainring)

        crankArm.color = RunnerPalette.color(RunnerPalette.metal)
        crankArm.size = CGSize(width: RunnerRider.crankRadius, height: 0.45)
        crankArm.anchorPoint = CGPoint(x: 0, y: 0.5)
        crankArm.position = CGPoint(x: RunnerRider.crank.x, y: RunnerRider.crank.y)
        crankArm.zPosition = 1
        player.addChild(crankArm)
    }

    /// 車体の管を1本。2点を結ぶ細い矩形を、始点で回して置く。
    private func addTube(from start: RunnerPoint, to end: RunnerPoint) {
        let dx = end.x - start.x, dy = end.y - start.y
        let tube = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.bike),
            size: CGSize(width: (dx * dx + dy * dy).squareRoot(), height: 0.55)
        )
        tube.anchorPoint = CGPoint(x: 0, y: 0.5)
        tube.position = CGPoint(x: start.x, y: start.y)
        tube.zRotation = CGFloat(atan2(dy, dx))
        player.addChild(tube)
    }

    /// 漕ぐ脚。奥の脚は車体より後ろ、手前の脚は胴より前に置く（重なる位相でも前後が分かる）。
    private func buildLegs() {
        configureLeg(thigh: farThigh, shin: farShin, knee: farKnee, shoe: farShoe,
                     color: RunnerPalette.pantsShade, z: -1)
        configureLeg(thigh: nearThigh, shin: nearShin, knee: nearKnee, shoe: nearShoe,
                     color: RunnerPalette.pants, z: 3)
    }

    private func configureLeg(
        thigh: SKSpriteNode, shin: SKSpriteNode, knee: SKShapeNode, shoe: SKSpriteNode,
        color: UInt32, z: CGFloat
    ) {
        thigh.color = RunnerPalette.color(color)
        thigh.size = CGSize(width: RunnerRider.thigh, height: 1.15)
        shin.color = RunnerPalette.color(color)
        shin.size = CGSize(width: RunnerRider.shin, height: 0.9)
        for segment in [thigh, shin] {
            // 関節を軸に回すので、左端の中央を基準にする。
            segment.anchorPoint = CGPoint(x: 0, y: 0.5)
            segment.zPosition = z
            player.addChild(segment)
        }
        knee.fillColor = RunnerPalette.color(color)
        knee.strokeColor = .clear
        knee.zPosition = z
        player.addChild(knee)
        // 付け根。腿が胴からいきなり生えて見えるのを防ぐ（動かないので子ノードで置くだけ）。
        let joint = SKShapeNode(circleOfRadius: 0.7)
        joint.fillColor = RunnerPalette.color(color)
        joint.strokeColor = .clear
        joint.position = CGPoint(x: RunnerRider.hip.x, y: RunnerRider.hip.y)
        joint.zPosition = z
        player.addChild(joint)
        shoe.color = RunnerPalette.color(RunnerPalette.shoe)
        shoe.size = CGSize(width: 1.2, height: 0.5)
        shoe.zPosition = z
        player.addChild(shoe)
    }

    /// おじさんの胴・腹・腕・首。
    private func buildRiderBody() {
        // 前かがみの胴。楕円1枚を傾けて置く（矩形だと肩と腰の丸みが出ない）。
        let torso = SKShapeNode(ellipseOf: CGSize(width: 4.2, height: 3.4))
        torso.fillColor = RunnerPalette.color(RunnerPalette.shirt)
        torso.strokeColor = .clear
        torso.zRotation = 0.72
        torso.position = CGPoint(x: -0.3, y: 7.4)
        torso.zPosition = 2
        player.addChild(torso)

        // 腹。「おじさん」の体型はこの丸みだけで伝える（顔だけでは年齢が読めない）。
        let belly = SKShapeNode(circleOfRadius: 1.45)
        belly.fillColor = RunnerPalette.color(RunnerPalette.shirt)
        belly.strokeColor = .clear
        belly.position = CGPoint(x: 0.85, y: 6.9)
        belly.zPosition = 2
        player.addChild(belly)

        // ハンドルへ伸びる腕（肩から握りまで1本の棒）と手。
        let arm = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.shirtShade),
                               size: CGSize(width: armLength, height: 0.95))
        arm.anchorPoint = CGPoint(x: 0, y: 0.5)
        arm.position = CGPoint(x: RunnerRider.shoulder.x, y: RunnerRider.shoulder.y)
        arm.zRotation = CGFloat(atan2(
            RunnerRider.grip.y - RunnerRider.shoulder.y,
            RunnerRider.grip.x - RunnerRider.shoulder.x
        ))
        arm.zPosition = 4
        player.addChild(arm)

        let hand = SKShapeNode(circleOfRadius: 0.55)
        hand.fillColor = RunnerPalette.color(RunnerPalette.skin)
        hand.strokeColor = .clear
        hand.position = CGPoint(x: RunnerRider.grip.x, y: RunnerRider.grip.y + 0.3)
        hand.zPosition = 4
        player.addChild(hand)
    }

    /// 肩から握りまでの長さ。
    private var armLength: Double {
        let dx = RunnerRider.grip.x - RunnerRider.shoulder.x
        let dy = RunnerRider.grip.y - RunnerRider.shoulder.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// 顔と帽子。**「おじさん」と分かるのはここだけ**なので、目・鼻・口ひげを省かない。
    private func buildFace() {
        let head = SKShapeNode(circleOfRadius: 1.5)
        head.fillColor = RunnerPalette.color(RunnerPalette.skin)
        head.strokeColor = .clear
        head.position = CGPoint(x: 1.0, y: 9.9)
        head.zPosition = 5
        player.addChild(head)

        // 後頭部の髪（帽子とうなじの間）。
        let hair = SKShapeNode(circleOfRadius: 0.85)
        hair.fillColor = RunnerPalette.color(RunnerPalette.hair)
        hair.strokeColor = .clear
        hair.position = CGPoint(x: -0.1, y: 9.6)
        hair.zPosition = 5
        player.addChild(hair)

        // 帽子（山とつば）。つばを前に出すことで、向いている方向が一目で分かる。
        let crown = SKShapeNode(ellipseOf: CGSize(width: 3.2, height: 1.8))
        crown.fillColor = RunnerPalette.color(RunnerPalette.bike)
        crown.strokeColor = .clear
        crown.position = CGPoint(x: 0.9, y: 11.0)
        crown.zPosition = 6
        player.addChild(crown)

        let brim = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.bike),
                                size: CGSize(width: 1.9, height: 0.45))
        brim.position = CGPoint(x: 2.7, y: 10.7)
        brim.zPosition = 6
        player.addChild(brim)

        let eye = SKShapeNode(circleOfRadius: 0.3)
        eye.fillColor = RunnerPalette.color(RunnerPalette.hair)
        eye.strokeColor = .clear
        eye.position = CGPoint(x: 1.85, y: 10.15)
        eye.zPosition = 7
        player.addChild(eye)

        let nose = SKShapeNode(circleOfRadius: 0.45)
        nose.fillColor = RunnerPalette.color(RunnerPalette.skinShade)
        nose.strokeColor = .clear
        nose.position = CGPoint(x: 2.4, y: 9.7)
        nose.zPosition = 7
        player.addChild(nose)

        let mustache = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.hair),
                                    size: CGSize(width: 1.3, height: 0.45))
        mustache.position = CGPoint(x: 1.95, y: 9.2)
        mustache.zPosition = 7
        player.addChild(mustache)
    }

    /// 雲ノードそのもの（`cloudBaseX` と対で、`sync` が毎フレーム位置を計算し直す）。
    private var clouds: [SKNode] = []
    /// 雲の基準 x（`0, spacing, 2*spacing, …`）。`cloudLayer` は動かさず、
    /// 各雲を「距離に応じて `cloudSpacing * clouds.count` 幅でループする」座標に置き直すことで、
    /// ステージがどれだけ長くても雲を作り直さずに無限スクロールへ流せる。
    private var cloudBaseX: [Double] = []

    /// 世界が変わったときに、空の色と雲・遠景・丘を作り直す（#703）。
    ///
    /// 呼ぶのは `rebuildCourse` だけ。ステージごとには呼ばれない（同じ世界のあいだは
    /// 雲も丘も同じものが流れ続ける——従来の「ステージをまたいでも作り直さない」を保つ）。
    private func applyWorld(_ next: RunnerWorld) {
        world = next
        renderedWorld = next
        backgroundColor = RunnerPalette.color(next.palette.sky)
        cloudLayer.removeAllChildren()
        clouds.removeAll()
        cloudBaseX.removeAll()
        backdropLayer.removeAllChildren()
        hillLayer.removeAllChildren()
        hillTiles.removeAll()
        hillBaseX.removeAll()
        buildClouds()
        buildBackdrop()
        buildHills()
    }

    /// 空を流れる雲。ステージをまたいでも作り直さない（`rebuildCourse` の対象外。
    /// 世界が変わるときだけ `applyWorld` が作り直す）。
    private func buildClouds() {
        let count = 8
        for i in 0..<count {
            let cloud = SKNode()
            let puffs: [(dx: Double, dy: Double, r: Double)] = [
                (0, 0, 3.4), (-3.2, -0.6, 2.4), (3.0, -0.4, 2.6), (0.6, 1.2, 2.2),
            ]
            for puff in puffs {
                let shape = SKShapeNode(circleOfRadius: puff.r)
                shape.fillColor = RunnerPalette.color(world.palette.cloud)
                shape.alpha = world.palette.cloudAlpha
                shape.strokeColor = .clear
                shape.position = CGPoint(x: puff.dx, y: puff.dy)
                cloud.addChild(shape)
            }
            // 高さを雲ごとに変えて、横一列に並んで見えないようにする。丘の稜線
            // （`buildHills`、最も高いもので地面+34=68）より確実に上、画面の上端付近に収める
            // ——`Metrics.height` を95に下げた際（#621）、旧来の帯（-52〜-12）のままだと
            // 丘の稜線に一部埋もれるため、丘より上の帯だけに詰めた。`Metrics.height` からの
            // 相対値で置いてあるので、115へ広げた（#636）あとも丘より上に収まる。
            let y = Metrics.height - 4 - Double(i % 4) * 6
            cloud.position = CGPoint(x: Double(i) * Self.cloudSpacing, y: y)
            cloudLayer.addChild(cloud)
            clouds.append(cloud)
            cloudBaseX.append(Double(i) * Self.cloudSpacing)
        }
    }

    /// 丘のタイルそのもの（`hillBaseX` と対で、`sync` が毎フレーム位置を計算し直す）。
    private var hillTiles: [SKNode] = []
    /// 丘タイルの基準 x（雲と同じ「距離に応じて全タイル幅でループする」座標の仕組み）。
    private var hillBaseX: [Double] = []

    /// 地平線側の丘の稜線。地面（`RunnerField.Metrics.groundY`）から上端
    /// （`RunnerField.Metrics.height`）までの帯が広く空くぶん、
    /// 何も無い空の帯にせず奥・手前 2 段の丘で埋める（2026-09-10 会長QA「縦を活かす」対応）。
    /// ステージをまたいでも作り直さない（`rebuildCourse` の対象外）——雲と同じ理由。
    /// 世界ごとの遠景の飾り（川・ビル）も同じタイルに載せて一緒に流す（#703）。
    private func buildHills() {
        let count = 6
        let palette = world.palette
        for i in 0..<count {
            let tile = SKNode()
            // 奥の丘（背が高く、色が薄い＝遠い）。
            addHillBump(to: tile, color: palette.hillFar, width: 42, height: 34, dx: 8)
            addHillBump(to: tile, color: palette.hillFar, width: 36, height: 27, dx: 42)
            // 手前の丘（背が低く、色が濃い＝近い）。奥の丘に重ねて奥行きを出す。
            addHillBump(to: tile, color: palette.hillNear, width: 34, height: 19, dx: 22)
            switch world.scenery {
            case .townHouses: addTownHouses(to: tile)
            case .riverside:  addRiver(to: tile)
            case .cityLights: addCityLights(to: tile)
            }
            tile.position = CGPoint(x: Double(i) * Self.hillSpacing, y: 0)
            hillLayer.addChild(tile)
            hillTiles.append(tile)
            hillBaseX.append(Double(i) * Self.hillSpacing)
        }
    }

    /// 動かない遠景。夕方だけ、地平線に橙の帯を敷いて「橙〜桃色の空」にする。
    /// 丘の後ろ（`backdropLayer`）に置くので、丘の切れ目からだけ覗く。
    private func buildBackdrop() {
        guard world.scenery == .riverside else { return }
        let glow = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.sunsetGlow),
            size: CGSize(width: Metrics.width, height: 30)
        )
        glow.anchorPoint = .zero
        glow.position = CGPoint(x: 0, y: Metrics.groundY)
        backdropLayer.addChild(glow)
        // 帯の上端をぼかす代わりに、半透明の 1 枚を重ねて 2 段にする（テクスチャを使わない）。
        let haze = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.sunsetGlow),
            size: CGSize(width: Metrics.width, height: 14)
        )
        haze.anchorPoint = .zero
        haze.alpha = 0.45
        haze.position = CGPoint(x: 0, y: Metrics.groundY + 30)
        backdropLayer.addChild(haze)
    }

    /// 夕方の川（`RunnerWorld.Scenery.riverside`）。丘の手前・地面のすぐ上に横長の帯を敷く。
    /// 丘と同じタイルに載せるので、丘と同じ視差で流れる（川は道のすぐ向こうにある）。
    /// 走者の下半身はこの帯を背に描かれる——`RunnerPalette.riverWater` の注記を参照。
    private func addRiver(to tile: SKNode) {
        let height = 7.0
        let water = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.riverWater),
            size: CGSize(width: Self.hillSpacing, height: height)
        )
        water.anchorPoint = .zero
        water.position = CGPoint(x: 0, y: Metrics.groundY)
        tile.addChild(water)
        // 照り返し。長さ・位置をずらした細い帯を 3 本置き、タイルの継ぎ目で揃わないようにする。
        for (dx, width, dy) in [(6.0, 14.0, 2.2), (28.0, 9.0, 4.6), (44.0, 11.0, 1.4)] {
            let glint = SKSpriteNode(
                color: RunnerPalette.color(RunnerPalette.riverGlint),
                size: CGSize(width: width, height: 0.6)
            )
            glint.anchorPoint = .zero
            glint.alpha = 0.8
            glint.position = CGPoint(x: dx, y: Metrics.groundY + dy)
            tile.addChild(glint)
        }
    }

    /// 朝の下町の家並み（`RunnerWorld.Scenery.townHouses`）。近景の丘の手前に 3 軒。
    /// 壁は矩形、屋根は三角のパス、窓は小さな矩形（#494 の意匠制約の内側）。丘のループに載せる。
    private func addTownHouses(to tile: SKNode) {
        let houses: [(dx: Double, width: Double, height: Double)] = [
            (2, 10, 7), (27, 8, 6), (44, 11, 8),
        ]
        for house in houses {
            let wall = SKSpriteNode(
                color: RunnerPalette.color(RunnerPalette.houseWall),
                size: CGSize(width: house.width, height: house.height)
            )
            wall.anchorPoint = .zero
            wall.position = CGPoint(x: house.dx, y: Metrics.groundY)
            tile.addChild(wall)
            let roof = CGMutablePath()
            roof.move(to: CGPoint(x: -0.8, y: 0))
            roof.addLine(to: CGPoint(x: house.width / 2, y: house.height * 0.45))
            roof.addLine(to: CGPoint(x: house.width + 0.8, y: 0))
            roof.closeSubpath()
            let roofNode = SKShapeNode(path: roof)
            roofNode.fillColor = RunnerPalette.color(RunnerPalette.houseRoof)
            roofNode.strokeColor = .clear
            roofNode.position = CGPoint(x: house.dx, y: Metrics.groundY + house.height)
            tile.addChild(roofNode)
            let window = SKSpriteNode(
                color: RunnerPalette.color(RunnerPalette.houseWindow),
                size: CGSize(width: 1.8, height: 1.8)
            )
            window.anchorPoint = .zero
            window.position = CGPoint(x: house.dx + house.width * 0.55, y: Metrics.groundY + house.height * 0.45)
            tile.addChild(window)
        }
    }

    /// 夜のビル（`RunnerWorld.Scenery.cityLights`）。近景の丘の手前に影を 3 棟と窓の灯りを置く。
    /// 矩形だけの単純な影（#494 の意匠制約の内側）。1 タイルあたり 3 棟＋窓 12 枚で、
    /// 丘のループに載せるので画面に出るノードは常にこの 6 倍まで。
    private func addCityLights(to tile: SKNode) {
        let buildings: [(dx: Double, width: Double, height: Double)] = [
            (3, 9, 12), (30, 7, 15), (47, 10, 10),
        ]
        for building in buildings {
            let body = SKSpriteNode(
                color: RunnerPalette.color(RunnerPalette.building),
                size: CGSize(width: building.width, height: building.height)
            )
            body.anchorPoint = .zero
            body.position = CGPoint(x: building.dx, y: Metrics.groundY)
            tile.addChild(body)
            // 窓は 2 列 × 2 段。すべて点けるとのっぺりするので、決まった 1 枚だけ消しておく
            // （乱数は使わない。撮影・QAで毎回同じ画になるように）。
            for row in 0..<2 {
                for column in 0..<2 where !(row == 1 && column == 1 && building.width < 8) {
                    let window = SKSpriteNode(
                        color: RunnerPalette.color(RunnerPalette.buildingWindow),
                        size: CGSize(width: 1.3, height: 1.6)
                    )
                    window.anchorPoint = .zero
                    window.position = CGPoint(
                        x: building.dx + 1.6 + Double(column) * (building.width - 4.5),
                        y: Metrics.groundY + 2.4 + Double(row) * 4.2
                    )
                    tile.addChild(window)
                }
            }
        }
    }

    /// 丘の山ひとつ。半分だけ地面から顔を出す楕円（下半分は `courseLayer` の地面に隠れる）。
    private func addHillBump(to tile: SKNode, color: UInt32, width: Double, height: Double, dx: Double) {
        let bump = SKShapeNode(ellipseOf: CGSize(width: width, height: height * 2))
        bump.fillColor = RunnerPalette.color(color)
        bump.strokeColor = .clear
        bump.position = CGPoint(x: dx, y: Metrics.groundY)
        tile.addChild(bump)
    }

    /// 地面・穴・障害物・ゴールをまとめて作り直す。
    private func rebuildCourse() {
        courseLayer.removeAllChildren()
        let stage = model.field.stage
        // 世界はステージ番号で決まる（#703）。変わったときだけ背景を作り直す。
        // エンドレス（#675・`number == 0`）は朝の下町で走る。距離で世界を変える案は第 2 弾（真の無限）と
        // 一緒に扱う（走行中に配色を差し替えると `applyWorld` の組み直しでコマ落ちしうるため、今は固定）。
        let nextWorld = stage.number == 0 ? RunnerWorld.morning : RunnerWorld.world(forStage: stage.number)
        if renderedWorld != nextWorld { applyWorld(nextWorld) }

        // 地面は「穴でないところ」を並べて描く。穴の場所には何も置かないので、
        // そこが空いていることが見た目でも当たり判定でも同じ意味になる。
        // スタートの手前（x < 0）にも道路を敷く。空けたままだと開始時の画面左が崖に見える
        // （会長 QA 2026-09-14「断崖絶壁から走り出す」）。
        var x: Double = -Metrics.width
        for pit in stage.hazards where pit.kind == .pit {
            if pit.start > x { addGround(from: x, to: pit.start) }
            addPitVoid(pit)
            addPitEdgeMarkers(pit)
            x = pit.end
        }
        if x < stage.length { addGround(from: x, to: stage.length + Metrics.width) }

        // スピードアップ床は地面の**上に重ねて**塗る（地面を作り直すのではなく、
        // 同じ路面の色と模様だけを差し替える）。地面より後に足すことで手前に来る。
        for floor in stage.boostFloors { addBoostFloor(floor) }

        movingHazards = []
        for hazard in stage.hazards where hazard.kind != .pit {
            switch hazard.kind {
            case .bird:                    movingHazards.append(addBird(hazard))
            case .dog:                     movingHazards.append(addDog(hazard))
            case .boar:                    movingHazards.append(addBoar(hazard))
            case .lowBlock, .tallBlock:    addRock(hazard)
            case .pit:                     break
            }
        }

        for platform in stage.platforms {
            addPlatform(platform)
        }

        pickupNodes = stage.pickups.map { pickup in
            switch pickup.kind {
            case .speed:      return addPickup(pickup)
            case .invincible: return addTakoyaki(pickup)
            }
        }
        removedPickupIndices = []
        renderedJustLandingCount = 0
        isBlinkingInvincible = false

        // エンドレス（#675）にチェックポイントは無い。`RunnerStage` は中点に計算するが、
        // 再開できない旗を立てると「ここから再開できる」という旗の意味（#494）が嘘になる。
        if model.mode == .stages {
            addCheckpointMarker(at: stage.checkpoint, percent: stage.checkpointPercent)
        }
        addGoalMarker(at: stage.length)
        renderedGeneration = model.runGeneration
        // 新しい走行の頭（もう一度・はじめから等）。前回の落下演出が沈める・フェードして
        // 終わった見た目のままだと、次の挑戦の走者が透けた/縮んだ状態で始まってしまう。
        player.removeAllActions()
        player.alpha = 1
        player.xScale = 1
        player.yScale = 1
    }

    /// 乗れる台座（#674）。工事の足場に架かった歩板——街の中の「高い場所」。
    ///
    /// 意匠は「丸と長方形＋パス」の規約（#494 の権利チェック）の内側で、**上面がいちばん明るく、
    /// 骨組みがその下に沈む**構成にしてある。台座は乗るものなので、遊ぶ人が最初に読み取るべきは
    /// 「どこに足が着くか」——岩（越えるもの）とは逆に、上端の床板を主役にする。
    ///
    /// 左端の面には穴の縁と同じ安全色の帯（`pitEdge`）を立てる。**正面から突っ込めば
    /// 高い障害物と同じくミス**（`RunnerField.isHittingPlatformFace`）で、
    /// このゲームで黄色はすでに「縁に気をつけろ」の意味を持っているので色を増やさずに済む。
    ///
    /// 当たり判定は `RunnerField` が `platform.start`〜`.end`／上面 `platform.top` で見ており、
    /// この見た目とは独立している——床板の上端をちょうど `top` に合わせてあるだけ。
    private func addPlatform(_ platform: RunnerPlatform) {
        let node = SKNode()
        node.position = CGPoint(x: platform.start, y: Metrics.groundY)
        let w = platform.length, top = platform.top

        // 床板（歩く面）。上端を当たり判定の上面にぴったり合わせる。
        let deckHeight = 1.6
        let deck = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.platformDeck),
            size: CGSize(width: w, height: deckHeight)
        )
        deck.anchorPoint = .zero
        deck.position = CGPoint(x: 0, y: top - deckHeight)
        deck.zPosition = 2

        // 床板の下の影。骨組みと床板のあいだに 1 本暗い帯を挟むと、輪郭線なしでも
        // 「板が骨組みの上に載っている」段差に見える。
        let underShadow = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.platformShade),
            size: CGSize(width: w, height: 0.5)
        )
        underShadow.anchorPoint = .zero
        underShadow.position = CGPoint(x: 0, y: top - deckHeight - 0.5)
        underShadow.zPosition = 1

        // 骨組みの高さ（床板と影の下）。
        let frameTop = top - deckHeight - 0.5

        // 横に通す単管（中段の水平材）。
        let rail = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.platformFrame),
            size: CGSize(width: w, height: 0.7)
        )
        rail.anchorPoint = .zero
        rail.position = CGPoint(x: 0, y: frameTop * 0.45)
        node.addChild(rail)

        // 支柱と筋交い。等間隔に立てるだけだと縞模様に見えるので、区間ごとに斜材を 1 本渡す。
        let postSpacing = 12.0
        let postWidth = 1.1
        let posts = max(2, Int((w / postSpacing).rounded()) + 1)
        for i in 0..<posts {
            let x = w * Double(i) / Double(posts - 1) - (i == posts - 1 ? postWidth : 0)
            let post = SKSpriteNode(
                color: RunnerPalette.color(RunnerPalette.platformFrame),
                size: CGSize(width: postWidth, height: frameTop)
            )
            post.anchorPoint = .zero
            post.position = CGPoint(x: x, y: 0)
            node.addChild(post)

            // 筋交い（次の支柱へ渡す斜材）。奥にある材なので骨組みより暗い色にする。
            guard i < posts - 1 else { continue }
            let nextX = w * Double(i + 1) / Double(posts - 1)
            let dx = nextX - x, dy = frameTop
            let brace = SKSpriteNode(
                color: RunnerPalette.color(RunnerPalette.platformShade),
                size: CGSize(width: (dx * dx + dy * dy).squareRoot(), height: 0.5)
            )
            brace.anchorPoint = CGPoint(x: 0, y: 0.5)
            brace.position = CGPoint(x: x, y: 0)
            brace.zRotation = CGFloat(atan2(dy, dx))
            brace.zPosition = -1
            node.addChild(brace)
        }

        node.addChild(underShadow)
        node.addChild(deck)

        // 正面（左端）の警告帯。ここに足元の高さで突っ込むとミスになる面。
        let face = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.pitEdge),
            size: CGSize(width: 0.7, height: top)
        )
        face.anchorPoint = .zero
        face.position = CGPoint(x: 0, y: 0)
        face.zPosition = 3
        node.addChild(face)

        courseLayer.addChild(node)
    }

    /// 障害物（岩）。丸2枚重ね→多角形1枚→矩形の積み石、と直してきたがいずれも
    /// 「何なのか分からない」というQAが続いた（会長 2026-09-10「岩のデザインはNG」）。
    /// 敗因は2つ：(1) 多角形1枚は縦横比の違う `tallBlock` に引き伸ばされて刃物のように潰れ、
    /// 積み石の矩形は角が丸く「石」の硬さが出ない、(2) 茶系の配色が地面の断面・遠景の丘に
    /// 溶けて実機ではシルエット自体が読めない。そこで**縦横比がほぼ正方形の「岩塊
    /// （ボルダー）1個」を描く部品を作り、当たり判定の縦横比から積む個数を導出する**
    /// 方式に変えた——低い障害物（4×5）は1個、高い障害物（4×9）は2個積み。岩塊は常に
    /// 自分の縦横比で描かれるので、どちらでも潰れない。色はストーングレー3階調
    /// （`rockLight`/`rockBody`/`rockDark`）。
    /// 多角形のパスは既存のゴール旗と同じ技法（#494 の権利チェックの要点は特定作品の
    /// 意匠に寄せないことで、パス自体は許容済み）。
    /// 当たり判定は `RunnerField` が `hazard.start`〜`.end`/`.height` の矩形で見ており、
    /// この見た目の変更とは独立している——中に収まる大きさで描いているだけ。
    private func addRock(_ hazard: RunnerHazard) {
        let node = SKNode()
        node.position = CGPoint(x: hazard.start, y: Metrics.groundY)
        let w = hazard.length, h = hazard.height

        // 接地の陰。岩の重みで地面に沈んでいるように、幅いっぱいの平たい楕円を敷く。
        let shadow = SKShapeNode(ellipseOf: CGSize(width: w * 1.05, height: h * 0.14))
        shadow.fillColor = RunnerPalette.color(world.palette.rockDark)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: w / 2, y: 0)
        node.addChild(shadow)

        // 岩塊の個数は当たり判定の縦横比から決める（幅4×高さ5 → 1個、幅4×高さ9 → 2個）。
        // 上下 15% ずつ重ねて積み、全体の頂が当たり判定の高さ h に一致するようにする。
        let count = max(1, Int((h / w).rounded()))
        let overlap = 0.15
        let boulderHeight = h / (1 + Double(count - 1) * (1 - overlap))
        var baseY = 0.0
        for i in 0..<count {
            // 上の岩塊は幅を絞り、少し右へずらして「同じ形の複製」に見せない。
            // 左右反転で変化を付ける案は、光の向き（左上）が上下の岩塊で食い違い、
            // 段差に黒い切れ込みのような影が出たので使わない（実機確認で判明）。
            addBoulder(
                to: node,
                centerX: w / 2 + (i == 0 ? 0 : w * 0.05),
                baseY: baseY,
                width: i == 0 ? w : w * 0.78,
                height: boulderHeight
            )
            baseY += boulderHeight * (1 - overlap)
        }

        courseLayer.addChild(node)
    }

    /// 岩の縁取りの太さ（コースの単位）。シーンは幅 `Metrics.width`（100）を画面幅へ
    /// `aspectFit` で広げるので、iPhone（幅 390pt 前後）では 1 単位 ≒ 3.9pt、0.4 単位 ≒ 1.5pt。
    /// 縁取りは輪郭の上に**中心線で**描かれるので、外へはみ出すのはこの半分（≒ 0.75pt）だけ。
    /// 当たり判定（`RunnerField`）は見た目と独立なので、縁取りで判定は変わらない。
    private static let rockOutlineWidth: CGFloat = 0.4

    /// 岩塊（ボルダー）1個。底が平らで頂がやや左に寄った角ばった多角形に、
    /// 日の当たる頂の面（明）と足元の陰の面（暗）を重ね、最後に暗い縁取り（`rockDark`）で
    /// 輪郭を締める（#920: 朝の下町など明るい世界では面の色だけだと背景に溶ける）。
    private func addBoulder(
        to node: SKNode, centerX: Double, baseY: Double,
        width: Double, height: Double
    ) {
        let boulder = SKNode()
        boulder.position = CGPoint(x: centerX, y: baseY)

        // 頂点は幅・高さそれぞれの比率で置く。岩塊は count の導出により常にほぼ正方形の
        // 縦横比で描かれるので、この比率が潰れることはない。
        func pt(_ fx: Double, _ fy: Double) -> CGPoint {
            CGPoint(x: fx * width, y: fy * height)
        }

        let bodyPath = CGMutablePath()
        bodyPath.move(to: pt(-0.48, 0))
        bodyPath.addLine(to: pt(-0.5, 0.38))
        bodyPath.addLine(to: pt(-0.28, 0.82))
        bodyPath.addLine(to: pt(-0.02, 1.0))
        bodyPath.addLine(to: pt(0.3, 0.88))
        bodyPath.addLine(to: pt(0.5, 0.42))
        bodyPath.addLine(to: pt(0.46, 0))
        bodyPath.closeSubpath()
        let body = SKShapeNode(path: bodyPath)
        body.fillColor = RunnerPalette.color(world.palette.rockBody)
        body.strokeColor = .clear
        boulder.addChild(body)

        // 日の当たる頂の面。
        let topPath = CGMutablePath()
        topPath.move(to: pt(-0.28, 0.82))
        topPath.addLine(to: pt(-0.02, 1.0))
        topPath.addLine(to: pt(0.3, 0.88))
        topPath.addLine(to: pt(0.06, 0.6))
        topPath.addLine(to: pt(-0.16, 0.56))
        topPath.closeSubpath()
        let top = SKShapeNode(path: topPath)
        top.fillColor = RunnerPalette.color(world.palette.rockLight)
        top.strokeColor = .clear
        boulder.addChild(top)

        // 足元の陰の面（光と反対側）。
        let shadePath = CGMutablePath()
        shadePath.move(to: pt(0.5, 0.42))
        shadePath.addLine(to: pt(0.46, 0))
        shadePath.addLine(to: pt(0.08, 0))
        shadePath.addLine(to: pt(0.2, 0.34))
        shadePath.closeSubpath()
        let shade = SKShapeNode(path: shadePath)
        shade.fillColor = RunnerPalette.color(world.palette.rockDark)
        shade.strokeColor = .clear
        boulder.addChild(shade)

        // 縁取り。本体と同じ輪郭を、塗り無しの線だけで**面の上に**重ねる（本体の `strokeColor` に
        // すると、頂の面・陰の面が線の内側半分を覆って輪郭が途切れる）。
        let outline = SKShapeNode(path: bodyPath)
        outline.fillColor = .clear
        outline.strokeColor = RunnerPalette.color(world.palette.rockDark)
        outline.lineWidth = Self.rockOutlineWidth
        outline.lineJoin = .round
        outline.zPosition = 1
        boulder.addChild(outline)

        node.addChild(boulder)
    }

    /// 動く障害（#796 飛び立つ鳥・#800 犬・#801 イノシシ）のノード一式。
    ///
    /// 位置は毎フレーム `RunnerHazard.frame(atRunnerDistance:)` から写す（`syncMovingHazards`）。
    /// ここには状態遷移のルールは無く、**止まっているか・動いているか**を `frame.advance` と
    /// 距離から読んで、部品のアニメーションを止める・回すだけ。
    private final class MovingHazardView {
        enum State: Equatable {
            /// まだ動き出していない（止まった鳥・立っている犬）。
            case waiting
            /// 飛び立つ前の羽ばたき（鳥だけ）。
            case fluttering
            /// 動いている。
            case moving
            /// 動き終えて止まっている（吠える犬・岩で止まったイノシシ）。
            case stopped
        }

        let hazard: RunnerHazard
        let node: SKNode
        /// 地面に敷く影（鳥）。体が上がっても地面に残すので、`sync` が高さのぶん下げる。
        let shadow: SKNode?
        /// 影の、帯の床から見た y（`RunnerBirdArt.shadowCenter.y`）。
        let shadowBaseY: Double
        /// 動いているあいだだけ回す部品（翼・浮遊・脚）。止まっているあいだは `isPaused`。
        let animated: [SKNode]
        /// 止まっているあいだだけ見せる部品（犬の吠え声）。
        let stoppedOnly: SKNode?
        /// 動いているあいだだけ見せる部品（イノシシの土煙）。
        let movingOnly: SKNode?
        var state: State?
        /// 前のフレームで現れていたか。イノシシは突進が始まるまで nil（現れていない）。
        var wasPresent = false

        init(
            hazard: RunnerHazard, node: SKNode, shadow: SKNode? = nil, shadowBaseY: Double = 0,
            animated: [SKNode], stoppedOnly: SKNode? = nil, movingOnly: SKNode? = nil
        ) {
            self.hazard = hazard
            self.node = node
            self.shadow = shadow
            self.shadowBaseY = shadowBaseY
            self.animated = animated
            self.stoppedOnly = stoppedOnly
            self.movingOnly = movingOnly
        }

        /// 状態に合わせて部品を止める・回す。変わったフレームだけ触る（毎フレーム
        /// `isPaused` を書き直しても壊れはしないが、意図が読めるように）。
        func apply(_ next: State) {
            guard next != state else { return }
            state = next
            for part in animated {
                part.isPaused = next == .waiting || next == .stopped
                // 羽ばたきの予備動作は飛んでいるときより速く小刻みに。
                part.speed = next == .fluttering ? 2.5 : 1
            }
            stoppedOnly?.isHidden = next != .stopped
            movingOnly?.isHidden = next != .moving
        }
    }

    /// 鳥（`RunnerHazardKind.bird`）。「棒と穴しかない」というQAを受けて追加した敵の1つ
    /// （会長QA「鳥とか右から車が来るとか要素はいる」）。丸1つ+矩形2枚 →「とまった小鳥」→
    /// 宙に浮いて飛ぶ鳥（#671）と直してきて、#796 で**地面に止まっていて近づくと飛び立つ鳥**になった。
    /// 絵は #671 の飛ぶ鳥（`RunnerBirdArt`）をそのまま流用し、止まっているあいだは翼と浮遊を
    /// 止め、飛び立つ直前に速く羽ばたく予備動作を入れる（`MovingHazardView.apply`）。
    /// 翼・尾・くちばしのパスは既存のゴール旗（`addGoalMarker`）と同じ技法（#494 の
    /// 権利チェックの要点は特定作品の意匠に寄せないことで、パス自体は許容されている）。
    /// 当たり判定は `RunnerField` が `RunnerHazard.frame(atRunnerDistance:)` の**帯**で見ており、
    /// 絵はその帯の床に合わせて置く（`syncMovingHazards` が毎フレーム帯の位置へ動かす）。
    ///
    /// **横は絵が矩形から導かれ、縦は帯が絵から導かれる**（#609 / #671 会長決裁 2026-09-12）。
    /// かつてはここに座標を直書きしており、「絵は矩形の内側に収まる寸法で組む」と書いていた
    /// にもかかわらず、実際にはくちばし・尾羽・翼が外へ出て**絵の幅が矩形の 1.5 倍**あった。
    /// 今はくちばしの先端・尾羽の先端・翼の振り切った先端が矩形の縁にちょうど一致し、
    /// 帯の床に絵の底、帯の天井に浮遊の上端が一致する。張り出しが 0 であることは
    /// `BirdArtTests` が寸法の計算で確かめるので、パーツを動かすとテストが落ちる。
    ///
    /// **座標・大きさをここに直書きしないこと。** この関数は `art` が持つ値をそのまま
    /// 使うだけにしてあり、直書きしたパーツは `RunnerBirdArt` の測定（= `BirdArtTests`）の
    /// 網から外れる。パーツを増やすときは `RunnerBirdArt` に足し、`discs` / `fixedParts` /
    /// `rotatingParts` のいずれかに登録してから使う。
    private func addBird(_ hazard: RunnerHazard) -> MovingHazardView {
        // 箱は当たり判定の**帯**（#671）。原点を帯の床に置く。影は地面に敷きたいので、
        // 帯が上がるぶんだけ `syncMovingHazards` が影を下げる（`groundDrop` は 0 で組む）。
        //
        // 帯の高さは渡さない——**帯の厚みのほうが絵に合わせて決まる**（会長決裁 2026-09-12。
        // `RunnerHazardKind.birdBandHeight` が `art.bandHeight` から導出する）。
        let art = RunnerBirdArt(width: hazard.length, groundDrop: 0)
        let node = SKNode()
        // 走者は左から近づくので、頭・くちばしは**走者側（-x）**を向かせる。`RunnerBirdArt` は
        // +x 側を頭にして組んであるので、丸ごと左右反転させるだけで済む——ただし `xScale = -1` は
        // 自分のローカル原点を軸に反転するので、そのままだと絵が当たり判定の外（帯の左）へ
        // はみ出す。原点を帯の右端に置いて帳尻を合わせる（`syncMovingHazards` も `frame.end` に置く）。
        node.position = CGPoint(x: hazard.end, y: Metrics.groundY + hazard.bottom)
        node.xScale = -1

        // 地面に落ちる影。体との間に空いたすき間が「飛んでいる」ことの一番の手がかり。
        // 影は浮遊に合わせて動かさない（`bobber` の外に置く）——地面側は止まっている
        // ほうが、上下しているのが鳥のほうだと分かる。
        let shadow = SKShapeNode(ellipseOf: art.shadowSize)
        shadow.fillColor = RunnerPalette.color(RunnerPalette.pitVoid)
        shadow.strokeColor = .clear
        shadow.alpha = 0.4
        shadow.position = art.shadowCenter
        node.addChild(shadow)

        // 浮遊はこの入れ物ごと上下させる（各パーツの座標は静止時のまま書ける）。
        // 振れ幅は `art.bobAmplitude` に織り込み済みで、翼の振り上げを足しても箱をはみ出さない。
        let bobber = SKNode()
        node.addChild(bobber)
        let bob = SKAction.moveBy(x: 0, y: art.bobAmplitude, duration: 0.7)
        bob.timingMode = .easeInEaseOut
        bobber.run(.repeatForever(.sequence([bob, bob.reversed()])))

        // 尾羽（後方＝-x 側）。2枚ずらして重ね、飛行姿勢に合わせて斜め上へ流す。
        // 長いほうの先端が当たり判定の後端にちょうど届く長さ（`RunnerBirdArt` が導出する）。
        for (index, spec) in art.tails.enumerated() {
            let tailPath = CGMutablePath()
            tailPath.addLines(between: spec.points)
            tailPath.closeSubpath()
            let tail = SKShapeNode(path: tailPath)
            tail.fillColor = RunnerPalette.color(
                index == 0 ? RunnerPalette.birdWingFar : RunnerPalette.birdBody
            )
            tail.strokeColor = .clear
            tail.position = spec.anchor
            bobber.addChild(tail)
        }

        // 翼。肩を軸に回すので、パスは肩（原点）から後方へ伸びる形で書く。
        // 手前・奥の2枚を逆位相で大きく振り、横からでも「羽ばたいている」と読めるようにする。
        // 止まっているあいだは `MovingHazardView.apply` が回転を止める（畳んだ姿勢＝振り下ろした端）。
        var wings: [SKNode] = []
        func addWing(
            _ spec: RunnerBirdArt.RotatingPart, color: UInt32, z: CGFloat, startsLow: Bool
        ) {
            let wingPath = CGMutablePath()
            wingPath.addLines(between: spec.points)
            wingPath.closeSubpath()
            let wing = SKShapeNode(path: wingPath)
            wing.fillColor = RunnerPalette.color(color)
            wing.strokeColor = .clear
            wing.position = spec.pivot
            wing.zPosition = z
            // 羽ばたきは `spec.rotation` の両端を往復する。ここを外れる角度で振ると、
            // `RunnerBirdArt` が測った張り出しより絵が外へ出る。手前と奥で始点を
            // 逆の端に取り、2枚が逆位相で振れるようにする。
            let span = spec.rotation.upperBound - spec.rotation.lowerBound
            wing.zRotation = startsLow ? spec.rotation.lowerBound : spec.rotation.upperBound
            let flap = SKAction.rotate(byAngle: startsLow ? span : -span, duration: 0.24)
            flap.timingMode = .easeInEaseOut
            wing.run(.repeatForever(.sequence([flap, flap.reversed()])))
            bobber.addChild(wing)
            wings.append(wing)
        }

        func addDisc(_ disc: RunnerBirdArt.Disc, color: UInt32) {
            let node = SKShapeNode(circleOfRadius: disc.radius)
            node.fillColor = RunnerPalette.color(color)
            node.strokeColor = .clear
            node.position = disc.center
            bobber.addChild(node)
        }

        // 奥の翼（胴の向こう側）。濃色+背面に置き、手前の翼と逆位相で振る。
        addWing(art.farWing, color: RunnerPalette.birdWingFar, z: -1, startsLow: true)

        // 胴体（大きい丸）。頭は別の丸を上前方に重ね、ひとつながりの丸いシルエットにする。
        // 腹は単色の玉に見えないための明るい差し色。
        addDisc(art.bodyDisc, color: RunnerPalette.birdBody)
        addDisc(art.headDisc, color: RunnerPalette.birdBody)
        addDisc(art.belly, color: RunnerPalette.birdBelly)

        // 畳んだ足。飛行中の鳥は足を体へ引き込むので、ぶら下げず腹の後ろ寄りに
        // 小さく畳んで添える（接地時代の「立つ2本足」の置き換え）。
        let foot = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.birdBeak),
                                size: art.footSize)
        foot.position = art.foot.pivot
        foot.zRotation = art.foot.rotation.lowerBound
        foot.zPosition = 1
        bobber.addChild(foot)

        // 手前の翼。奥の翼と逆位相・大振り。
        addWing(art.nearWing, color: RunnerPalette.birdWing, z: 3, startsLow: false)

        // くちばし（進行方向側の三角）。先端が当たり判定の走者側の端にちょうど届く長さ。
        let beakPath = CGMutablePath()
        beakPath.addLines(between: art.beak.points)
        beakPath.closeSubpath()
        let beak = SKShapeNode(path: beakPath)
        beak.fillColor = RunnerPalette.color(RunnerPalette.birdBeak)
        beak.strokeColor = .clear
        beak.position = art.beak.anchor
        bobber.addChild(beak)

        // 目。白目の上に、進行方向（走者側）へ寄せた黒目を重ねる
        // （暗緑に暗色の点では見えない、の教訓）。
        addDisc(art.eyeWhite, color: RunnerPalette.birdBelly)
        addDisc(art.pupil, color: RunnerPalette.birdEye)

        courseLayer.addChild(node)
        return MovingHazardView(
            hazard: hazard, node: node, shadow: shadow, shadowBaseY: Double(art.shadowCenter.y),
            animated: wings + [bobber]
        )
    }

    /// 走る 4 本脚（犬・イノシシ共通）。付け根を軸に前後へ振る。原点は箱の左下、`facing` は
    /// 進行方向（+1 で右・-1 で左）。戻り値は脚のノード（動いているあいだだけ回す）。
    private func addRunningLegs(
        to node: SKNode, xs: [Double], hipY: Double, length: Double, thickness: Double,
        color: UInt32, z: CGFloat
    ) -> [SKNode] {
        var legs: [SKNode] = []
        for (index, x) in xs.enumerated() {
            let leg = SKSpriteNode(color: RunnerPalette.color(color), size: CGSize(width: thickness, height: length))
            // 付け根（上端）を軸に振る。
            leg.anchorPoint = CGPoint(x: 0.5, y: 1)
            leg.position = CGPoint(x: x, y: hipY)
            leg.zPosition = z
            // 前後の脚を逆位相に。
            let phase = index.isMultiple(of: 2) ? 1.0 : -1.0
            leg.zRotation = CGFloat(0.45 * phase)
            let swing = SKAction.rotate(byAngle: CGFloat(-0.9 * phase), duration: 0.14)
            swing.timingMode = .easeInEaseOut
            leg.run(.repeatForever(.sequence([swing, swing.reversed()])))
            node.addChild(leg)
            legs.append(leg)
        }
        return legs
    }

    /// 犬（`RunnerHazardKind.dog`・#800）。おじさんと同じ向き（右）に走り、追いつかれる直前に
    /// 立ち止まって吠える。丸と長方形＋三角のパスだけで組む（#494 の権利チェック）。
    ///
    /// 当たり判定は `RunnerField` が `frame(atRunnerDistance:)` の矩形（1 タイル × 高さ 5）で
    /// 見ており、絵はその箱の中に収まる寸法。原点は箱の左下。吠え声の吹き出しだけは
    /// 箱の外（頭の前）に出るが、見た目だけで当たり判定には関わらない。
    private func addDog(_ hazard: RunnerHazard) -> MovingHazardView {
        let node = SKNode()
        node.position = CGPoint(x: hazard.start, y: Metrics.groundY)
        let w = hazard.length, h = hazard.height

        let shadow = SKShapeNode(ellipseOf: CGSize(width: w * 0.95, height: 0.5))
        shadow.fillColor = RunnerPalette.color(RunnerPalette.pitVoid)
        shadow.strokeColor = .clear
        shadow.alpha = 0.35
        shadow.position = CGPoint(x: w / 2, y: 0.25)
        node.addChild(shadow)

        // 脚（4 本）。体より奥に置く。
        let legs = addRunningLegs(
            to: node, xs: [w * 0.28, w * 0.4, w * 0.62, w * 0.74], hipY: h * 0.5,
            length: h * 0.5, thickness: w * 0.11, color: RunnerPalette.dogDark, z: 0
        )

        // 胴（横長の楕円）と腹の差し色。
        let body = SKShapeNode(ellipseOf: CGSize(width: w * 0.7, height: h * 0.34))
        body.fillColor = RunnerPalette.color(RunnerPalette.dogBody)
        body.strokeColor = .clear
        body.position = CGPoint(x: w * 0.5, y: h * 0.52)
        body.zPosition = 1
        node.addChild(body)
        let belly = SKShapeNode(ellipseOf: CGSize(width: w * 0.42, height: h * 0.14))
        belly.fillColor = RunnerPalette.color(RunnerPalette.dogBelly)
        belly.strokeColor = .clear
        belly.position = CGPoint(x: w * 0.52, y: h * 0.44)
        belly.zPosition = 2
        node.addChild(belly)

        // 尻尾（後ろ上に立てた短い棒）。
        let tail = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.dogBody), size: CGSize(width: w * 0.1, height: h * 0.3))
        tail.anchorPoint = CGPoint(x: 0.5, y: 0)
        tail.position = CGPoint(x: w * 0.16, y: h * 0.56)
        tail.zRotation = -0.6
        tail.zPosition = 1
        node.addChild(tail)

        // 頭（丸）と、立った耳・鼻・目。頭は進行方向（右）の上。
        let head = SKShapeNode(circleOfRadius: w * 0.2)
        head.fillColor = RunnerPalette.color(RunnerPalette.dogBody)
        head.strokeColor = .clear
        head.position = CGPoint(x: w * 0.8, y: h * 0.74)
        head.zPosition = 3
        node.addChild(head)
        let earPath = CGMutablePath()
        earPath.addLines(between: [
            CGPoint(x: -w * 0.16, y: h * 0.08), CGPoint(x: -w * 0.06, y: h * 0.3), CGPoint(x: 0, y: h * 0.1),
        ])
        earPath.closeSubpath()
        let ear = SKShapeNode(path: earPath)
        ear.fillColor = RunnerPalette.color(RunnerPalette.dogDark)
        ear.strokeColor = .clear
        ear.position = head.position
        ear.zPosition = 2
        node.addChild(ear)
        let muzzle = SKShapeNode(ellipseOf: CGSize(width: w * 0.2, height: h * 0.12))
        muzzle.fillColor = RunnerPalette.color(RunnerPalette.dogBelly)
        muzzle.strokeColor = .clear
        muzzle.position = CGPoint(x: w * 0.94, y: h * 0.7)
        muzzle.zPosition = 4
        node.addChild(muzzle)
        let nose = SKShapeNode(circleOfRadius: w * 0.04)
        nose.fillColor = RunnerPalette.color(RunnerPalette.dogDark)
        nose.strokeColor = .clear
        nose.position = CGPoint(x: w * 1.0, y: h * 0.72)
        nose.zPosition = 5
        node.addChild(nose)
        let eye = SKShapeNode(circleOfRadius: w * 0.035)
        eye.fillColor = RunnerPalette.color(RunnerPalette.dogDark)
        eye.strokeColor = .clear
        eye.position = CGPoint(x: w * 0.86, y: h * 0.8)
        eye.zPosition = 5
        node.addChild(eye)

        // 吠え声。頭の前に小さな白い吹き出し（丸 3 つ）を出し、止まっているあいだだけ見せて
        // 脈打たせる。文字は描かない（SpriteKit の中に文字は置かない・基盤規約）。
        let bark = SKNode()
        for (index, spec) in [(0.0, 0.0, 0.42), (0.5, 0.35, 0.3), (0.95, 0.75, 0.2)].enumerated() {
            let puff = SKShapeNode(circleOfRadius: spec.2)
            puff.fillColor = RunnerPalette.color(RunnerPalette.dogBark)
            puff.strokeColor = .clear
            puff.position = CGPoint(x: spec.0, y: spec.1)
            puff.zPosition = CGFloat(6 - index)
            bark.addChild(puff)
        }
        bark.position = CGPoint(x: w * 1.2, y: h * 0.86)
        bark.isHidden = true
        let pulse = SKAction.scale(to: 1.25, duration: 0.18)
        bark.run(.repeatForever(.sequence([pulse, pulse.reversed()])))
        node.addChild(bark)

        courseLayer.addChild(node)
        return MovingHazardView(hazard: hazard, node: node, animated: legs, stoppedOnly: bark)
    }

    /// イノシシ（`RunnerHazardKind.boar`・#801）。右から左へ突進してくるので、頭は左向き。
    /// 丸と長方形＋三角のパスだけで組む（#494 の権利チェック）。原点は箱の左下（頭側）。
    ///
    /// 走っているあいだは後ろ（右）に土煙を引く。岩で止まると脚と土煙が止まり、
    /// 低い岩と同じ置物として岩の右側に並ぶ。
    private func addBoar(_ hazard: RunnerHazard) -> MovingHazardView {
        let node = SKNode()
        node.position = CGPoint(x: hazard.start, y: Metrics.groundY)
        let w = hazard.length, h = hazard.height

        let shadow = SKShapeNode(ellipseOf: CGSize(width: w * 1.0, height: 0.55))
        shadow.fillColor = RunnerPalette.color(RunnerPalette.pitVoid)
        shadow.strokeColor = .clear
        shadow.alpha = 0.35
        shadow.position = CGPoint(x: w / 2, y: 0.25)
        node.addChild(shadow)

        let legs = addRunningLegs(
            to: node, xs: [w * 0.3, w * 0.42, w * 0.66, w * 0.78], hipY: h * 0.46,
            length: h * 0.46, thickness: w * 0.13, color: RunnerPalette.boarDark, z: 0
        )

        // 胴（犬より太い楕円）と、背中のたてがみ（暗い帯）。
        let body = SKShapeNode(ellipseOf: CGSize(width: w * 0.86, height: h * 0.46))
        body.fillColor = RunnerPalette.color(RunnerPalette.boarBody)
        body.strokeColor = .clear
        body.position = CGPoint(x: w * 0.54, y: h * 0.56)
        body.zPosition = 1
        node.addChild(body)
        let mane = SKShapeNode(ellipseOf: CGSize(width: w * 0.6, height: h * 0.14))
        mane.fillColor = RunnerPalette.color(RunnerPalette.boarDark)
        mane.strokeColor = .clear
        mane.position = CGPoint(x: w * 0.5, y: h * 0.76)
        mane.zPosition = 2
        node.addChild(mane)

        // 頭（左）。鼻先を前へ突き出し、牙を白で 1 本。
        let head = SKShapeNode(circleOfRadius: w * 0.22)
        head.fillColor = RunnerPalette.color(RunnerPalette.boarBody)
        head.strokeColor = .clear
        head.position = CGPoint(x: w * 0.2, y: h * 0.58)
        head.zPosition = 3
        node.addChild(head)
        let snout = SKShapeNode(ellipseOf: CGSize(width: w * 0.22, height: h * 0.14))
        snout.fillColor = RunnerPalette.color(RunnerPalette.boarSnout)
        snout.strokeColor = .clear
        snout.position = CGPoint(x: w * 0.06, y: h * 0.52)
        snout.zPosition = 4
        node.addChild(snout)
        let tuskPath = CGMutablePath()
        tuskPath.addLines(between: [
            CGPoint(x: 0, y: 0), CGPoint(x: -w * 0.08, y: h * 0.12), CGPoint(x: w * 0.06, y: h * 0.02),
        ])
        tuskPath.closeSubpath()
        let tusk = SKShapeNode(path: tuskPath)
        tusk.fillColor = RunnerPalette.color(RunnerPalette.boarTusk)
        tusk.strokeColor = .clear
        tusk.position = CGPoint(x: w * 0.1, y: h * 0.42)
        tusk.zPosition = 5
        node.addChild(tusk)
        let earPath = CGMutablePath()
        earPath.addLines(between: [
            CGPoint(x: 0, y: 0), CGPoint(x: w * 0.06, y: h * 0.2), CGPoint(x: w * 0.16, y: h * 0.04),
        ])
        earPath.closeSubpath()
        let ear = SKShapeNode(path: earPath)
        ear.fillColor = RunnerPalette.color(RunnerPalette.boarDark)
        ear.strokeColor = .clear
        ear.position = CGPoint(x: w * 0.22, y: h * 0.72)
        ear.zPosition = 2
        node.addChild(ear)
        let eye = SKShapeNode(circleOfRadius: w * 0.04)
        eye.fillColor = RunnerPalette.color(RunnerPalette.boarTusk)
        eye.strokeColor = .clear
        eye.position = CGPoint(x: w * 0.14, y: h * 0.66)
        eye.zPosition = 5
        node.addChild(eye)

        // 後ろに引く土煙。走っているあいだだけ見せ、膨らんで消えるを繰り返す。
        let dust = SKNode()
        for (index, spec) in [(1.1, 0.5, 0.7), (1.35, 1.1, 0.5)].enumerated() {
            let puff = SKShapeNode(circleOfRadius: spec.2)
            puff.fillColor = RunnerPalette.color(RunnerPalette.cloud)
            puff.strokeColor = .clear
            puff.alpha = 0.6
            puff.position = CGPoint(x: w * spec.0, y: h * spec.1 * 0.3)
            puff.zPosition = -1
            let grow = SKAction.group([.scale(to: 1.6, duration: 0.3), .fadeAlpha(to: 0, duration: 0.3)])
            let reset = SKAction.group([.scale(to: 0.6, duration: 0), .fadeAlpha(to: 0.6, duration: 0)])
            puff.run(.repeatForever(.sequence([.wait(forDuration: 0.1 * Double(index)), grow, reset])))
            dust.addChild(puff)
        }
        dust.isHidden = true
        node.addChild(dust)

        courseLayer.addChild(node)
        return MovingHazardView(hazard: hazard, node: node, animated: legs, movingOnly: dust)
    }

    /// 動く障害を、いまの当たり判定の位置へ置き直し、状態に合わせて部品を止める・回す（#796）。
    ///
    /// **位置はルール層の `frame` をそのまま写す**（描画側で独自に動かさない）。当たり判定と
    /// 絵がズレる余地を作らないため。
    private func syncMovingHazards(_ field: RunnerField) {
        for view in movingHazards {
            let hazard = view.hazard
            guard let frame = hazard.frame(atRunnerDistance: field.distance) else {
                view.node.isHidden = true
                view.wasPresent = false
                continue
            }
            view.node.isHidden = false
            if !view.wasPresent {
                view.wasPresent = true
                // 突進が始まった瞬間（#801）。出現点はまだ画面の外なので、画面の右端に土煙を
                // 立てて「何か来る」を見せる。手応え（ドドド）は Model が同じ瞬間に鳴らす。
                if hazard.kind == .boar, field.distance > hazard.boarChargeStartDistance - 1 {
                    spawnChargeDust(atWorldX: field.distance + Metrics.width - Metrics.playerX - 4)
                }
            }
            switch hazard.kind {
            case .bird:
                // 原点は帯の右端（左右反転しているため）。影は帯が上がっても地面に残す。
                view.node.position = CGPoint(x: frame.end, y: Metrics.groundY + frame.bottom)
                view.shadow?.position.y = CGFloat(view.shadowBaseY - frame.bottom)
                let state: MovingHazardView.State
                if frame.advance > 0 {
                    state = .moving
                } else if field.distance >= hazard.birdTakeoffDistance - RunnerRules.birdFlutterDistance {
                    state = .fluttering
                } else {
                    state = .waiting
                }
                view.apply(state)
            case .dog:
                view.node.position = CGPoint(x: frame.start, y: Metrics.groundY)
                let state: MovingHazardView.State
                if frame.advance > 0 {
                    state = .moving
                } else if field.distance >= hazard.dogStopDistance {
                    state = .stopped
                } else {
                    state = .waiting
                }
                view.apply(state)
            case .boar:
                view.node.position = CGPoint(x: frame.start, y: Metrics.groundY)
                view.apply(frame.advance < 0 ? .moving : .stopped)
            case .pit, .lowBlock, .tallBlock:
                break
            }
        }
    }

    /// イノシシの予告の土煙（#801）。画面の右端の地面に、激突の土煙より大きく長く立てる。
    /// コース側（`courseLayer`）に置くので、走るにつれて左へ流れていく。
    private func spawnChargeDust(atWorldX worldX: Double) {
        spawnDust(
            at: CGPoint(x: worldX, y: Metrics.groundY + 1.5),
            specs: [
                (-2.0, 3.5, 1.6), (1.5, 4.5, 1.3), (-4.5, 2.0, 1.2),
                (3.5, 2.5, 1.0), (0.0, 6.0, 1.1), (-1.0, 1.0, 1.8),
            ],
            duration: 0.8,
            in: courseLayer
        )
    }

    /// スピードアップアイテム。最初の実装は細い矩形2枚で稲妻を表していたが小さすぎて
    /// 「何なのかパッと見てわからない」という再QA（2026-09-10）を受け、後光（丸）の上に
    /// 稲妻を1枚のパスで大きく描き直した。稲妻は速さ・電気を連想させる定番の記号で、
    /// キャラクターが「おじさん」であることに引きずられた案（ビール等）は倫理的に
    /// 採用しないという会長判断も踏まえ、キャラクター性に依存しない記号にしてある。
    /// 取得すると `sync` がフェードアウト＋縮小で消す。戻り値は `sync` が取得済みかどうかを
    /// 追うためのノード参照。
    @discardableResult
    private func addPickup(_ pickup: RunnerPickup) -> SKNode {
        let node = SKNode()
        let radius = 2.6
        node.position = CGPoint(x: pickup.start, y: Metrics.groundY + radius + 1.3)

        // 後光（丸）。
        let aura = SKShapeNode(circleOfRadius: radius)
        aura.fillColor = RunnerPalette.color(RunnerPalette.pickupAura)
        aura.strokeColor = .clear
        node.addChild(aura)

        // 稲妻（1枚の折れ線パス）。ゴール旗（`addGoalMarker`）と同じ「パスで図形を描く」
        // 作り方を踏襲し、輪郭線を付けて後光の上でも沈まないようにする。
        let boltPath = CGMutablePath()
        boltPath.move(to: CGPoint(x: 0.5, y: radius * 0.95))
        boltPath.addLine(to: CGPoint(x: -1.0, y: 0.1))
        boltPath.addLine(to: CGPoint(x: 0.1, y: 0.1))
        boltPath.addLine(to: CGPoint(x: -0.6, y: -radius * 0.95))
        boltPath.addLine(to: CGPoint(x: 1.2, y: 0))
        boltPath.addLine(to: CGPoint(x: 0.1, y: 0))
        boltPath.closeSubpath()
        let bolt = SKShapeNode(path: boltPath)
        bolt.fillColor = RunnerPalette.color(RunnerPalette.pickupBolt)
        bolt.strokeColor = RunnerPalette.color(RunnerPalette.pickupBoltOutline)
        bolt.lineWidth = 0.18
        bolt.zPosition = 1
        node.addChild(bolt)

        // 取得を誘う脈動（見た目だけ。当たり判定は `RunnerField` 側の矩形のまま）。
        let pulse = SKAction.sequence([
            .scale(to: 1.15, duration: 0.45),
            .scale(to: 1.0, duration: 0.45),
        ])
        node.run(.repeatForever(pulse))

        courseLayer.addChild(node)
        return node
    }

    /// たこ焼き（`RunnerPickupKind.invincible`・#797）。舟皿に 3 個、ソースの上に青のりと
    /// 紅しょうがの色点——縁日の屋台で買うあの形で、**特定のキャラクター・作品には寄せない**
    /// （#494 の権利チェック）。岩・鳥と同じく丸と長方形とパスだけで組み、輪郭線は引かない。
    /// スピードアップ（稲妻）は「脈動」、たこ焼きは「上下にふわふわ浮く」で動きも変え、
    /// 色だけに頼らず見分けられるようにする。当たり判定は `RunnerField` 側の横の重なりだけで、
    /// この絵の寸法とは独立している（`addPickup` と同じ）。
    @discardableResult
    private func addTakoyaki(_ pickup: RunnerPickup) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(x: pickup.start, y: Metrics.groundY + 2.4)

        // 舟皿（経木）。上が広く底が狭い台形を 1 枚。
        let trayPath = CGMutablePath()
        trayPath.move(to: CGPoint(x: -3.8, y: 0.5))
        trayPath.addLine(to: CGPoint(x: -3.0, y: -1.0))
        trayPath.addLine(to: CGPoint(x: 3.0, y: -1.0))
        trayPath.addLine(to: CGPoint(x: 3.8, y: 0.5))
        trayPath.closeSubpath()
        let tray = SKShapeNode(path: trayPath)
        tray.fillColor = RunnerPalette.color(RunnerPalette.takoyakiTray)
        tray.strokeColor = .clear
        node.addChild(tray)

        // 玉 3 個。ソースは玉の上半分に被せた小さめの丸で、明暗の差だけで丸みを出す。
        let ballRadius = 1.05
        for (i, x) in [-2.1, 0.0, 2.1].enumerated() {
            let ball = SKShapeNode(circleOfRadius: ballRadius)
            ball.fillColor = RunnerPalette.color(RunnerPalette.takoyakiBall)
            ball.strokeColor = .clear
            ball.position = CGPoint(x: x, y: 0.75)
            ball.zPosition = 1
            node.addChild(ball)

            let sauce = SKShapeNode(ellipseOf: CGSize(width: 1.5, height: 0.8))
            sauce.fillColor = RunnerPalette.color(RunnerPalette.takoyakiSauce)
            sauce.strokeColor = .clear
            sauce.position = CGPoint(x: x, y: 1.05)
            sauce.zPosition = 2
            node.addChild(sauce)

            // 青のり（緑）を各玉に 1 点、紅しょうが（赤）は左右の玉にだけ 1 点。
            // 点の位置は決め打ち（乱数は使わない。撮影・QAで毎回同じ画になるように）。
            let aonori = SKShapeNode(circleOfRadius: 0.17)
            aonori.fillColor = RunnerPalette.color(RunnerPalette.takoyakiAonori)
            aonori.strokeColor = .clear
            aonori.position = CGPoint(x: x - 0.35, y: 1.15)
            aonori.zPosition = 3
            node.addChild(aonori)
            if i != 1 {
                let benishoga = SKShapeNode(circleOfRadius: 0.18)
                benishoga.fillColor = RunnerPalette.color(RunnerPalette.takoyakiBenishoga)
                benishoga.strokeColor = .clear
                benishoga.position = CGPoint(x: x + 0.4, y: 0.95)
                benishoga.zPosition = 3
                node.addChild(benishoga)
            }
        }

        // ふわふわ浮く（見た目だけ。当たり判定は `RunnerField` 側の横の重なりのまま）。
        let rise = SKAction.moveBy(x: 0, y: 0.7, duration: 0.55)
        rise.timingMode = .easeInEaseOut
        let sink = SKAction.moveBy(x: 0, y: -0.7, duration: 0.55)
        sink.timingMode = .easeInEaseOut
        node.run(.repeatForever(.sequence([rise, sink])))

        courseLayer.addChild(node)
        return node
    }

    /// 取得済みのピックアップをフェードアウト＋縮小で消す。
    private func removePickupNode(_ node: SKNode) {
        guard node.parent != nil else { return }
        // 脈動（`repeatForever`）を止めてからでないと、拡大縮小がぶつかって
        // 消える瞬間だけ縮み方が乱れる。
        node.removeAllActions()
        node.run(.sequence([
            .group([.fadeOut(withDuration: 0.25), .scale(to: 0.2, duration: 0.25)]),
            .removeFromParent(),
        ]))
    }

    /// 穴の中身（奈落）。縁の帯だけだと穴の内側が空と同じ色のままで、
    /// 「本当にここが穴なのか・幅はどれくらいか」が伝わらなかった（会長QA）。
    /// 地面と同じ矩形をそのまま塗り替えるだけなので、幅は `pit.start`〜`.end` の実寸そのもの
    /// ——当たり判定（`RunnerField.isPit`）が見ている境界と完全に一致する。
    private func addPitVoid(_ pit: RunnerHazard) {
        let void = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.pitVoid),
            size: CGSize(width: pit.length, height: Metrics.groundY)
        )
        void.anchorPoint = .zero
        void.position = CGPoint(x: pit.start, y: 0)
        courseLayer.addChild(void)
    }

    /// 穴の縁の警告帯。地面と同系色の穴だけでは切れ目が分かりづらいというQAを受けて追加。
    /// 当たり判定には影響しない、純粋な見た目の追加。
    private func addPitEdgeMarkers(_ pit: RunnerHazard) {
        // 黄と黒の 3 段（工事の柵）。道路の穴＝工事中の切れ目、という読みに揃える（会長 QA 2026-09-14）。
        for edgeX in [pit.start, pit.end] {
            for (i, hex) in [RunnerPalette.pitEdge, RunnerPalette.pitEdgeDark, RunnerPalette.pitEdge].enumerated() {
                let strip = SKSpriteNode(
                    color: RunnerPalette.color(hex),
                    size: CGSize(width: 0.8, height: 1.0)
                )
                strip.anchorPoint = CGPoint(x: 0.5, y: 1)
                strip.position = CGPoint(x: edgeX, y: Metrics.groundY - Double(i) * 1.0)
                courseLayer.addChild(strip)
            }
        }
    }

    /// 道路の断面（会長 QA 2026-09-14）。上からアスファルト・白い破線・縁石・路肩・地盤。
    /// 色は `RunnerWorld.road`。高さは物理（`Metrics.groundY`）に合わせ、路面の上端が地面。
    /// 破線は 1 本の `SKShapeNode` にまとめる（エンドレスは 6,400 m あるので、1 本ずつ
    /// ノードにすると数千個になる）。
    private static let roadHeight: Double = 5.0
    private static let curbHeight: Double = 1.0
    private static let shoulderHeight: Double = 4.0

    private func addGround(from start: Double, to end: Double) {
        let road = world.road
        let width = end - start
        func band(_ hex: UInt32, y: Double, height: Double) {
            let node = SKSpriteNode(color: RunnerPalette.color(hex), size: CGSize(width: width, height: height))
            node.anchorPoint = .zero
            node.position = CGPoint(x: start, y: y)
            courseLayer.addChild(node)
        }
        let roadBottom = Metrics.groundY - Self.roadHeight
        let curbBottom = roadBottom - Self.curbHeight
        let shoulderBottom = curbBottom - Self.shoulderHeight
        band(road.subsoil, y: 0, height: shoulderBottom)
        band(road.shoulder, y: shoulderBottom, height: Self.shoulderHeight)
        band(road.curb, y: curbBottom, height: Self.curbHeight)
        band(road.asphalt, y: roadBottom, height: Self.roadHeight)

        // 中央の破線。長さ 4・間隔 4 で、区画の始点（64 の倍数）に位相を揃えて継ぎ目を目立たせない。
        let dashes = CGMutablePath()
        let dashLength = 4.0, dashGap = 4.0, dashHeight = 0.7
        var dx = (start / (dashLength + dashGap)).rounded(.down) * (dashLength + dashGap)
        while dx < end {
            let x0 = max(dx, start), x1 = min(dx + dashLength, end)
            if x1 > x0 {
                dashes.addRect(CGRect(x: x0, y: roadBottom + Self.roadHeight / 2 - dashHeight / 2,
                                      width: x1 - x0, height: dashHeight))
            }
            dx += dashLength + dashGap
        }
        let line = SKShapeNode(path: dashes)
        line.fillColor = RunnerPalette.color(road.line)
        line.strokeColor = .clear
        line.alpha = world == .night ? 0.75 : 0.9
        courseLayer.addChild(line)
    }

    /// スピードアップ床（#672）。**地面の路面だけを塗り替え、その上に進行方向の矢印を並べる**。
    ///
    /// 高さのある置物にしない理由は 2 つ。(1) 床は当たり判定を一切持たない
    /// （`RunnerField.isOnBoostFloor` は中心の x が区間に入っているかだけを見る）ので、
    /// 地面から生えた物として描くと岩・鳥と同じ「当たるもの」に見えてしまう。
    /// (2) 走者は床の上を走るので、走者より手前に物を置くと足元が隠れる。
    ///
    /// 矢印は丸・長方形では向きが出ないので三角のパスで描く（意匠制約 #494 は
    /// 「特定作品に寄せない」ことで、ゴール旗・稲妻と同じくパス自体は許容済み）。
    /// 色だけでなく**形**でも「前へ押される区間」だと伝わるようにしてある。
    private func addBoostFloor(_ floor: RunnerBoostFloor) {
        // 路面全体（アスファルトの厚み）を加速帯の色で塗り替え、上下を暗い青で縁取る。
        // 以前は 2.2 の薄い帯に小さな三角で、走者の足元では気づけなかった（会長 QA 2026-09-14）。
        let height = Self.roadHeight
        let bottom = Metrics.groundY - height
        let surface = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.boostFloorTop),
            size: CGSize(width: floor.length, height: height)
        )
        surface.anchorPoint = .zero
        surface.position = CGPoint(x: floor.start, y: bottom)
        courseLayer.addChild(surface)
        for edgeY in [bottom, Metrics.groundY - 0.6] {
            let edge = SKSpriteNode(
                color: RunnerPalette.color(RunnerPalette.boostFloorEdge),
                size: CGSize(width: floor.length, height: 0.6)
            )
            edge.anchorPoint = .zero
            edge.position = CGPoint(x: floor.start, y: edgeY)
            courseLayer.addChild(edge)
        }

        // 山形の矢印（シェブロン）を路面いっぱいの高さで並べ、右へ流して「前へ押される」ことを
        // 動きでも伝える。矢印はまとめて 1 本のパスにし、帯の内側だけ見えるようマスクで切る。
        let spacing: Double = 6
        let chevronWidth: Double = 3.2
        let inset: Double = 0.9
        let path = CGMutablePath()
        let count = Int(floor.length / spacing) + 2
        for i in 0..<count {
            let x = Double(i) * spacing
            path.move(to: CGPoint(x: x, y: bottom + inset))
            path.addLine(to: CGPoint(x: x + chevronWidth * 0.55, y: bottom + inset))
            path.addLine(to: CGPoint(x: x + chevronWidth, y: bottom + height / 2))
            path.addLine(to: CGPoint(x: x + chevronWidth * 0.55, y: Metrics.groundY - inset))
            path.addLine(to: CGPoint(x: x, y: Metrics.groundY - inset))
            path.addLine(to: CGPoint(x: x + chevronWidth * 0.45, y: bottom + height / 2))
            path.closeSubpath()
        }
        let chevrons = SKShapeNode(path: path)
        chevrons.fillColor = RunnerPalette.color(RunnerPalette.boostFloorArrow)
        chevrons.strokeColor = .clear
        chevrons.position = CGPoint(x: -spacing, y: 0)
        // 1 周期ぶん右へ流して戻す。周期パターンなので継ぎ目なく流れて見える。
        chevrons.run(.repeatForever(.sequence([
            .moveBy(x: spacing, y: 0, duration: 0.35),
            .moveBy(x: -spacing, y: 0, duration: 0),
        ])))
        let crop = SKCropNode()
        let mask = SKSpriteNode(color: .white, size: CGSize(width: floor.length, height: height))
        mask.anchorPoint = .zero
        crop.maskNode = mask
        crop.position = CGPoint(x: floor.start, y: 0)
        // マスクは crop の座標系（x = 0 が床の始点）なので、矢印パスも床の始点基準に置く。
        mask.position = CGPoint(x: 0, y: bottom)
        crop.addChild(chevrons)
        courseLayer.addChild(crop)
    }

    /// チェックポイントの目印。丸いバッジだけでは「これが何なのか分からない」というQAを受け、
    /// マラソンの距離標識のように**そのステージで実際に計算された到達率**を数字で出す板に
    /// 変えた（会長QA「50%と書かれた旗とか」——ただし実際の到達率は `checkpointPercent` の
    /// とおりステージごとに違うので、固定の "50%" ではなくその値をそのまま表示する）。
    /// 板は矩形・柱も矩形で「丸と長方形だけ」の意匠制約（#494）を保ったまま、
    /// ゴールの三角旗（`addGoalMarker`）とは形・色の両方で見分けが付く。
    /// ここより先で失敗すると、広告視聴でここから再開できる（`RunnerModel.canResumeFromCheckpoint`）。
    ///
    /// **数字はこの標識自体の意味そのもの**（盤面の説明の重複ではない）なので、
    /// 「SpriteKit の中に文字は描かない」（`RunnerAccessibility` の方針）はここでは適用しない。
    /// 読み上げは従来どおり `RunnerAccessibility.progressLabel` が進み具合として担う。
    private func addCheckpointMarker(at x: Double, percent: Int) {
        let pole = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.wheel),
            size: CGSize(width: 1.4, height: 19)
        )
        pole.anchorPoint = CGPoint(x: 0.5, y: 0)
        pole.position = CGPoint(x: x, y: Metrics.groundY)
        courseLayer.addChild(pole)

        // 旗（つばめ尾型）。四角い「標識板」は道路標識に見えて「何なのか分からない」
        // という再QA（2026-09-10）を受け、ゴールの旗（`addGoalMarker`）と同じ
        // 「柱に付いた旗」という形の文法に揃えつつ、先端に三角の切れ込みを入れて
        // ゴールの単純な三角旗とは別物と分かるようにした。奥にもう1枚重ねて厚みを出す。
        // 大きさ・文字は2度直している：初版は小さすぎて実機で読めず（会長QA「旗の文字も
        // いまだに見えない」）、1.5倍版も文字が旗の左端からはみ出してポールに重なり、
        // 白抜き×水色でコントラストも足りなかった。旗をさらに広げ（幅17）、文字は
        // 切れ込みのない無地部分（x: 0〜13.5）に収まる位置・大きさで、旗より十分暗い紺
        // （`checkpointText`）に変えた（「%」の字幅が数字より広いことに注意。幅15では
        // 「51%」がまだ両端にはみ出た——実機確認で判明）。
        let flagPath = CGMutablePath()
        flagPath.move(to: CGPoint(x: 0, y: 4.6))
        flagPath.addLine(to: CGPoint(x: 17, y: 4.6))
        flagPath.addLine(to: CGPoint(x: 13.5, y: 0))
        flagPath.addLine(to: CGPoint(x: 17, y: -4.6))
        flagPath.addLine(to: CGPoint(x: 0, y: -4.6))
        flagPath.closeSubpath()

        let flagCenter = CGPoint(x: x, y: Metrics.groundY + 13.8)
        let flagShade = SKShapeNode(path: flagPath)
        flagShade.fillColor = RunnerPalette.color(RunnerPalette.checkpointShade)
        flagShade.strokeColor = .clear
        flagShade.position = CGPoint(x: flagCenter.x + 0.6, y: flagCenter.y - 0.6)
        courseLayer.addChild(flagShade)

        let flag = SKShapeNode(path: flagPath)
        flag.fillColor = RunnerPalette.color(RunnerPalette.checkpoint)
        flag.strokeColor = .clear
        flag.position = flagCenter
        courseLayer.addChild(flag)

        // 到達率。旗の意味そのものなので大きく載せる（会長案「50%と書かれた旗とか」）。
        // 中心は切れ込みを除いた無地部分（x: 0〜13.5）の真ん中。
        let label = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        label.text = "\(percent)%"
        label.fontSize = 5.6
        label.fontColor = RunnerPalette.color(RunnerPalette.checkpointText)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: flagCenter.x + 6.75, y: flagCenter.y)
        label.zPosition = 1
        courseLayer.addChild(label)
    }

    /// ゴールの目印（旗）。細い柱だけでは「何のオブジェクトか分からない」というQAを受け、
    /// 三角の旗を足して一目でゴールと分かる形にした。
    ///
    /// 「着いた感」が薄い（#703 の要素分解）ので、旗をチェックポイントの旗と同じ寸法級まで
    /// 広げ、奥に陰の 1 枚を重ねて厚みを出し、「ゴール」と書く。**文字はこの旗の意味そのもの**
    /// なので、チェックポイントの到達率と同じく「SpriteKit の中に文字は描かない」
    /// （`RunnerAccessibility`）の例外にあたる。先端を尖らせた矢羽根型にしてあるのは、
    /// 先端に切れ込みのあるつばめ尾のチェックポイントと形で見分けるため（文字が三角の
    /// 細い先端に収まらないので、純粋な三角は捨てた）。旗は横にゆっくり伸び縮みさせて、
    /// 風にはためいて見せる（1 ノードの `SKAction` だけで、コースの他のノードには影響しない）。
    /// 到達した瞬間の音・触覚は `RunnerModel` が `feedback.notify(.success)` で鳴らす
    /// （`RunnerFeedbackCue`）。
    private func addGoalMarker(at x: Double) {
        let poleHeight = 21.0
        let pole = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.wheel), size: CGSize(width: 1.4, height: poleHeight))
        pole.anchorPoint = CGPoint(x: 0.5, y: 0)
        pole.position = CGPoint(x: x, y: Metrics.groundY)
        courseLayer.addChild(pole)

        // 矢羽根型の旗。左辺を柱に付け、無地の矩形部分（x: 0〜12）の先を尖らせる。
        let flagHalfHeight = 4.4
        let flagPath = CGMutablePath()
        flagPath.move(to: CGPoint(x: 0, y: flagHalfHeight))
        flagPath.addLine(to: CGPoint(x: 12, y: flagHalfHeight))
        flagPath.addLine(to: CGPoint(x: 15.5, y: 0))
        flagPath.addLine(to: CGPoint(x: 12, y: -flagHalfHeight))
        flagPath.addLine(to: CGPoint(x: 0, y: -flagHalfHeight))
        flagPath.closeSubpath()

        // はためき。柱側（x=0）を軸に横だけ伸縮させる。旗・陰・文字をまとめて動かす。
        let flag = SKNode()
        flag.position = CGPoint(x: x + 0.7, y: Metrics.groundY + poleHeight - flagHalfHeight - 0.6)
        let wave = SKAction.sequence([
            .scaleX(to: 0.9, duration: 0.55),
            .scaleX(to: 1.0, duration: 0.55),
        ])
        wave.timingMode = .easeInEaseOut
        flag.run(.repeatForever(wave))
        courseLayer.addChild(flag)

        let shade = SKShapeNode(path: flagPath)
        shade.fillColor = RunnerPalette.color(RunnerPalette.goalShade)
        shade.strokeColor = .clear
        shade.position = CGPoint(x: 0.6, y: -0.6)
        flag.addChild(shade)

        let cloth = SKShapeNode(path: flagPath)
        cloth.fillColor = RunnerPalette.color(RunnerPalette.goal)
        cloth.strokeColor = .clear
        flag.addChild(cloth)

        // 「ゴール」。無地の矩形部分（x: 0〜12）の真ん中に置く（3 文字 × 3.6 ≒ 10.8 幅）。
        let label = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        label.text = "ゴール"
        label.fontSize = 3.6
        label.fontColor = RunnerPalette.color(RunnerPalette.goalText)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 6, y: 0)
        label.zPosition = 1
        flag.addChild(label)
    }

    // MARK: - 反映

    private func sync() {
        if renderedGeneration != model.runGeneration { rebuildCourse() }
        let field = model.field
        // 雲はコースより遅く流す（視差）。`cloudLayer` 自体は動かさず、
        // 雲1つ1つを「全雲の帯の幅」でラップする座標に置き直す（無限スクロール）。
        let totalWidth = Self.cloudSpacing * Double(clouds.count)
        for (i, cloud) in clouds.enumerated() {
            let raw = (cloudBaseX[i] - field.distance * Self.cloudParallax)
                .truncatingRemainder(dividingBy: totalWidth)
            let wrapped = raw < 0 ? raw + totalWidth : raw
            cloud.position.x = wrapped
        }
        // 丘は雲より近く（速く）、コースより遠く（遅く）流す。仕組みは雲と同じ無限スクロール。
        let hillTotalWidth = Self.hillSpacing * Double(hillTiles.count)
        for (i, tile) in hillTiles.enumerated() {
            let raw = (hillBaseX[i] - field.distance * Self.hillParallax)
                .truncatingRemainder(dividingBy: hillTotalWidth)
            let wrapped = raw < 0 ? raw + hillTotalWidth : raw
            tile.position.x = wrapped
        }
        // 走者の画面上の x は動かさず、コースのほうを左へ流す。
        courseLayer.position = CGPoint(x: Metrics.playerX - field.distance, y: 0)
        if model.phase == .falling {
            // ミスした瞬間に `field` は凍る（`RunnerModel.tick` が `field.step` を呼ばなくなる）ので
            // 値は変わらない。最初のフレームだけ、ミスした瞬間の位置・向きへきっちり合わせてから
            // 演出を始める（以後 `player.position` / `.zRotation` はここでは触らず、演出の
            // `SKAction` に専有させる。毎フレーム上書きすると動きが打ち消される）。
            if lastSyncedPhase != .falling {
                player.position = CGPoint(x: Metrics.playerX, y: field.footY)
                player.zRotation = field.isGrounded ? 0 : CGFloat(max(-0.3, min(0.3, field.vy / 300)))
                // 無敵のまま穴に落ちた（#797）場合、点滅の途中の薄さで落下演出に入らないよう
                // 先に戻す（`playFallAnimation` の `removeAllActions` で点滅そのものは止まる）。
                stopInvincibleBlink()
                playFallAnimation()
            }
        } else {
            player.position = CGPoint(x: Metrics.playerX, y: field.footY)
            // 車輪は進んだ距離ぶんだけ回す（半径 2.6 の円周で 1 回転）。
            let angle = -field.distance / 2.6
            frontWheel.zRotation = CGFloat(angle)
            rearWheel.zRotation = CGFloat(angle)
            syncPedaling(field)
            // 空中では前のめりにする。跳んでいることが動きだけで分かるようにするため。
            player.zRotation = field.isGrounded ? 0 : CGFloat(max(-0.3, min(0.3, field.vy / 300)))
            syncPickups(field)
            syncJustLanding(field)
            syncMovingHazards(field)
            // 無敵の点滅（#797）は走者ノードの alpha だけを触る。動く障害（#796）の同期は
            // 障害側のノードしか動かさないので、順序に依存も干渉もしない。
            syncInvincibility(field)
            // ゴールに着いた最初のフレームだけ紙吹雪を散らす（#703「着いた感」）。
            // `.falling` の落下演出と同じ「前回反映した phase」との比較で 1 回に絞る。
            if model.phase == .cleared || model.phase == .allCleared,
               lastSyncedPhase != .cleared, lastSyncedPhase != .allCleared {
                spawnGoalConfetti()
            }
        }
        lastSyncedPhase = model.phase
    }

    /// ゴール到達の紙吹雪。土煙と同じ丸だけの部品（#494）で、旗の色と白を交互に散らす。
    /// 座標は画面固定（走者の頭上）——クリアした瞬間 `field` は止まりコースも流れない。
    /// ノードは演出が終わると自分で消えるので、次の走行（`rebuildCourse`）に後始末は要らない。
    private func spawnGoalConfetti() {
        let origin = CGPoint(x: Metrics.playerX, y: Metrics.groundY + Metrics.playerHeight + 3)
        // 弾ける方向は決め打ち（乱数は使わない。撮影・QAで毎回同じ画になるように）。
        let specs: [(dx: Double, dy: Double, r: Double)] = [
            (-7, 9, 1.0), (-3, 12, 0.8), (2, 13, 1.1), (6, 11, 0.9), (9, 7, 0.8),
            (-9, 4, 0.7), (-1, 8, 0.7), (4, 6, 0.9), (11, 3, 0.7), (-5, 6, 0.8),
        ]
        for (i, spec) in specs.enumerated() {
            spawnDust(
                at: origin, specs: [spec], duration: 0.7,
                color: i.isMultiple(of: 2) ? RunnerPalette.goal : RunnerPalette.cloud
            )
        }
    }

    /// 取得済みのピックアップのノードを消す（`removedPickupIndices` の宣言を参照）。
    private func syncPickups(_ field: RunnerField) {
        guard !field.collectedPickupIndices.isSubset(of: removedPickupIndices) else { return }
        let indices = Self.pickupIndicesToRemove(
            collected: field.collectedPickupIndices,
            removed: removedPickupIndices,
            nodeCount: pickupNodes.count
        )
        for i in indices {
            removePickupNode(pickupNodes[i])
            removedPickupIndices.insert(i)
        }
    }

    /// 取得済みなのにまだ消していないピックアップの添字（昇順）。ノードの範囲外の添字は返さない
    /// ——ノードとステージの取り違えがあっても配列の範囲外を引いて落ちないようにするため（#733）。
    nonisolated static func pickupIndicesToRemove(
        collected: Set<Int>, removed: Set<Int>, nodeCount: Int
    ) -> [Int] {
        collected.subtracting(removed).filter { $0 >= 0 && $0 < nodeCount }.sorted()
    }

    /// ジャスト着地（#673）の土煙を出す。**1 回の着地につき 1 回だけ**——`field` の
    /// 単調増加する回数と、すでに出した回数の差で判断する（`syncPickups` と同じ形）。
    private func syncJustLanding(_ field: RunnerField) {
        guard field.justLandingCount > renderedJustLandingCount else { return }
        renderedJustLandingCount = field.justLandingCount
        spawnJustLandingDust(atWorldX: field.distance)
    }

    /// 無敵（たこ焼き・#797）の点滅を、`field.isInvincible` と食い違ったフレームだけ掛ける／外す。
    ///
    /// 点滅は走者ノード全体の `alpha` を `SKAction` で往復させる。周期は 0.36 秒（約 2.8 Hz）
    /// ——毎秒 3 回を超える明滅は光過敏の目安（WCAG 2.3.1）に掛かるので、その手前に留める。
    /// 位置・回転は `sync` が毎フレーム上書きするが `alpha` には触らないので、action と
    /// ぶつからない。
    private func syncInvincibility(_ field: RunnerField) {
        // ミス後（`.failed`）は `field` が無敵のまま凍るが、倒れた走者を点滅させない。
        // 一時停止中は掛けたままにする（止めるたびに外すと再開の瞬間にちらつく）。
        let shouldBlink = field.isInvincible && (model.phase == .running || model.phase == .paused)
        guard shouldBlink != isBlinkingInvincible else { return }
        if shouldBlink {
            isBlinkingInvincible = true
            let blink = SKAction.sequence([
                .fadeAlpha(to: 0.35, duration: 0.18),
                .fadeAlpha(to: 1.0, duration: 0.18),
            ])
            player.run(.repeatForever(blink), withKey: Self.invincibleBlinkKey)
        } else {
            stopInvincibleBlink()
        }
    }

    /// 無敵の点滅を外し、走者を不透明に戻す。無敵でないときに呼んでも何もしない。
    private func stopInvincibleBlink() {
        guard isBlinkingInvincible else { return }
        isBlinkingInvincible = false
        player.removeAction(forKey: Self.invincibleBlinkKey)
        player.alpha = 1
    }

    /// 穴に落ちる/ぶつかった瞬間だけ流す演出（`.falling` に入った最初のフレームで 1 回発火）。
    ///
    /// 新規アセットは作らず、既存の丸と長方形だけの走者ノード（`player`）をそのまま
    /// 沈める・回す・フェードする。当たり判定・進行のタイミングは `RunnerModel` 側の
    /// `RunnerRules.fallDuration` が決めており、ここは見た目だけを作る。
    private func playFallAnimation() {
        player.removeAllActions()
        let duration = RunnerRules.fallDuration

        // 序盤から倒れ始める。`easeIn` は終盤に速度が乗る動きで、演出時間の前半は
        // ほとんど回っておらず「立ったまま」に見えていた（会長QA「穴の横に落ちて
        // 縦になってるように見える」・2026-09-10）。
        //
        // 回転の向きは**負**（時計回り）にする。`player` の原点は前輪（+x）と後輪（-x）の
        // ちょうど中間にあり、正の回転（反時計回り）だと前輪側が先に持ち上がり後輪側から
        // 沈む——「なぜ後輪から落ちる、普通は前輪からやろ」という会長QA（2026-09-10）どおりの
        // 見え方になっていた。負の回転なら前輪側（進行方向）が先に沈み、後輪が後から
        // 持ち上がって前転するように見える。走者は左から近づき、穴・障害物は前方にあるので、
        // 前輪から落ちる/突っ込むほうが物理的に自然。
        let topple = SKAction.rotate(byAngle: -.pi * 0.85, duration: duration)
        topple.timingMode = .easeOut

        if model.field.isPit(at: model.field.distance) {
            // 穴の奈落は `Metrics.groundY` の深さまである（`addPitVoid`）。以前の沈み幅
            // （-3.5）はその1割ほどしかなく、穴の底へ落ちる前に演出が終わって
            // 「穴の横で止まっている」ように見えていた。奈落の深さに合わせて沈める。
            let sink = SKAction.moveBy(x: 0, y: -Metrics.groundY * 0.7, duration: duration)
            sink.timingMode = .easeIn
            let fade = SKAction.sequence([
                .wait(forDuration: duration * 0.25),
                .fadeAlpha(to: 0, duration: duration * 0.75),
            ])
            player.run(.group([sink, topple, fade]))
        } else {
            // 障害物への激突。以前は後退1単位+前傾（`topple` 相当）+フェードだけで、
            // 「その場で薄くなって終わり」にしか見えなかった（会長QA「岩にあたったときは
            // コケるアニメーションを再現してほしい」・2026-09-10）。つまずいて転げる
            // 「コケ」に作り直す:
            // - 回転はちょうど 1 回転（-2π・前転）。`topple`（-0.85π）より派手に転げて
            //   見えるうえ、終端で直立に戻るので、直後の `.failed` で `sync` が
            //   `zRotation = 0` へ戻すときの画の飛びも出ない。
            // - 体は岩に弾き返されて後方へ山なりに飛び、着地で小さくバウンドして止まる。
            // - 車輪は惰性で空転させ、激突点には土煙を散らす（丸のみ・#494 の範囲内）。
            //
            // moveBy + rotate の合成ではなく custom action で毎フレーム姿勢を計算する。
            // `player` の原点は足元にあり、rotate だけだと足元を軸に回って回転の途中で
            // 頭が地面へ潜る（実機確認で判明）。見た目の重心（原点の上 4.5）を軸に
            // 回って見えるよう、回転量に応じた座標の補正を毎フレーム掛ける。
            let pivotY = 4.5
            let baseX = player.position.x, baseY = player.position.y
            let crash = SKAction.customAction(withDuration: duration) { node, elapsed in
                let p = max(0, min(1, Double(elapsed) / duration))
                // 回転は序盤に大きく（2次の easeOut）。激突の勢いで回り、終端で失速する。
                let eased = 1 - (1 - p) * (1 - p)
                let theta = -2 * Double.pi * eased
                node.zRotation = CGFloat(theta)
                // 後方への山なり（前 64%）+ 着地後の小さなバウンド（後 36%）。
                // どちらも sin の半波なので、終端でちょうど y=0（地面）へ戻る。
                let dy = p < 0.64
                    ? 3.4 * sin(.pi * p / 0.64)
                    : 1.0 * sin(.pi * (p - 0.64) / 0.36)
                // 重心軸の回転に見せる補正: 原点 O を C=(0, pivotY) の周りに θ 回した
                // ときの O の移動量。回転が 1 回転し切ると 0 に戻る。
                let compX = pivotY * sin(theta)
                let compY = pivotY * (1 - cos(theta))
                node.position = CGPoint(
                    x: baseX + CGFloat(-3.2 * p + compX),
                    y: baseY + CGFloat(dy + compY)
                )
            }
            let fade = SKAction.sequence([
                .wait(forDuration: duration * 0.6),
                .fadeAlpha(to: 0.35, duration: duration * 0.4),
            ])
            player.run(.group([crash, fade]))
            // 空転。走行中の回転は `sync` が距離から出すが、`.falling` の間は触らない
            // （このメソッド参照）ので、ここで惰性ぶんを回し切る。有限時間の action
            // なので次の走行開始（`rebuildCourse`）までに勝手に終わる。
            for wheel in [frontWheel, rearWheel] {
                wheel.run(.rotate(byAngle: -12, duration: duration))
            }
            spawnCrashDust()
        }
    }

    /// 激突点の土煙。丸だけで組む（#494）。ノードは演出が終わると自分で消えるので、
    /// `rebuildCourse` 側での後始末は要らない。座標は画面固定（走者の前輪の先）——
    /// ミスの瞬間 `field` は凍っていてコースも流れないため、シーン直下に置いてよい。
    private func spawnCrashDust() {
        // 弾ける方向は決め打ち（乱数は使わない。撮影・QAで毎回同じ画になるように）。
        spawnDust(
            at: CGPoint(x: Metrics.playerX + 5.0, y: Metrics.groundY + 2.0),
            specs: [
                (-1.5, 2.5, 1.1), (0.8, 3.2, 0.9), (2.0, 1.8, 1.2),
                (-3.0, 1.2, 0.8), (0.2, 0.8, 1.3), (-4.5, 2.0, 0.7),
            ]
        )
    }

    /// ジャスト着地の土煙（#673）。激突の土煙と同じ作りで、**後輪の足元から後ろへ小さく**
    /// 散らす（越えた障害の真裏に降りた、という画にする）。ミスの演出と紛れないよう、
    /// 粒は少なく・小さく・短くしてある。
    ///
    /// **こちらはコース側（`courseLayer`）に置く**——走行中はコースが流れ続けるので、
    /// 画面固定にすると土煙が走者と一緒に前へ動いて見える。降りた地点に残して後ろへ流す。
    private func spawnJustLandingDust(atWorldX worldX: Double) {
        spawnDust(
            at: CGPoint(x: worldX - 2.6, y: Metrics.groundY + 0.8),
            specs: [(-2.2, 1.4, 0.8), (-4.0, 0.9, 0.6), (-0.6, 1.9, 0.7)],
            duration: 0.3,
            in: courseLayer
        )
    }

    /// 丸だけの土煙を 1 か所から散らす。ノードは演出が終わると自分で消える。
    private func spawnDust(
        at origin: CGPoint,
        specs: [(dx: Double, dy: Double, r: Double)],
        duration: TimeInterval = 0.4,
        in parent: SKNode? = nil,
        color: UInt32 = RunnerPalette.cloud
    ) {
        for spec in specs {
            let puff = SKShapeNode(circleOfRadius: spec.r)
            puff.fillColor = RunnerPalette.color(color)
            puff.strokeColor = .clear
            puff.alpha = 0.8
            puff.zPosition = 6
            puff.position = origin
            (parent ?? self).addChild(puff)
            let drift = SKAction.moveBy(x: spec.dx, y: spec.dy, duration: duration)
            drift.timingMode = .easeOut
            puff.run(.sequence([
                .group([
                    drift,
                    .scale(to: 1.8, duration: duration),
                    .fadeOut(withDuration: duration),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    /// 漕ぐ脚を進める（#569）。
    ///
    /// 位相は**接地して進んだ距離**から出す。時計で回すと、ゆっくりモードや一時停止のあいだも
    /// 脚だけが動いてしまう。速く走れば漕ぐのも速くなる（`pedalBoost` が距離に乗るため、
    /// ケイデンスはここで何もしなくても乗りに追従する）。
    private func syncPedaling(_ field: RunnerField) {
        // 初回は 0 から数える。`field.distance` を初期値にすると、シーンが出るより前に
        // 進んでいた場合（撮影用の `-simulateRunner`）にその区間だけ漕いでいない扱いになる。
        let delta = field.distance - (lastRenderedDistance ?? 0)
        lastRenderedDistance = field.distance
        pedalPhase = RunnerRider.advance(
            phase: pedalPhase, by: delta, isPedaling: field.isGrounded
        )
        place(thigh: farThigh, shin: farShin, knee: farKnee, shoe: farShoe,
              leg: RunnerRider.leg(phase: pedalPhase, isFar: true))
        let near = RunnerRider.leg(phase: pedalPhase, isFar: false)
        place(thigh: nearThigh, shin: nearShin, knee: nearKnee, shoe: nearShoe, leg: near)
        crankArm.zRotation = CGFloat(atan2(
            near.pedal.y - RunnerRider.crank.y, near.pedal.x - RunnerRider.crank.x
        ))
    }

    /// 片脚のノードを、求めた形（腰 → 膝 → ペダル）へ置き直す。
    private func place(
        thigh: SKSpriteNode, shin: SKSpriteNode, knee: SKShapeNode, shoe: SKSpriteNode,
        leg: RunnerRider.Leg
    ) {
        thigh.position = CGPoint(x: leg.hip.x, y: leg.hip.y)
        thigh.zRotation = CGFloat(atan2(leg.knee.y - leg.hip.y, leg.knee.x - leg.hip.x))
        shin.position = CGPoint(x: leg.knee.x, y: leg.knee.y)
        shin.zRotation = CGFloat(atan2(leg.pedal.y - leg.knee.y, leg.pedal.x - leg.knee.x))
        knee.position = CGPoint(x: leg.knee.x, y: leg.knee.y)
        // 靴はペダルに乗っているので水平のまま（回すと足首が回転して見える）。
        shoe.position = CGPoint(x: leg.pedal.x, y: leg.pedal.y + 0.15)
    }
}
