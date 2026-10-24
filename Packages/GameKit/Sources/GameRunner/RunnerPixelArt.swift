import Core
import Foundation

// MARK: - チャリンコおじさんのドット絵（走者以外）

/// チャリンコおじさんの**走者以外**のドット絵の置き場（#956）。走者と正面顔はおじさんシリーズで
/// 使い回すので `Core` の `OjisanPixel` にあり、こちらはこのゲーム限りの物——アイテム・障害物・
/// 背景の飾り——を集める。今後、図形の組み立て（`SKShapeNode`）からドット絵へ置き換える物は
/// すべてここに `〜Rows` と `〜()` を足し、`RunnerPixelArtTests` の走査に入れる。
///
/// 描き方は走者と同じ（SFC 級・#701）: 1 文字 = 1 ドット、`.` は透明、暗い縁取りで背景から
/// 浮かせる（#929「手前の物は縁取る」）。1 ドットの大きさはシーン側が走者と同じ単位
/// （`RunnerRider.placement` の `unit` ≒ 0.33）で貼るので、**ここでは寸法をドット数だけで考える**
/// （3 ドット ≒ 1 単位、走者の頭までが 36 ドット）。
enum RunnerPixelArt {
    /// 共通パレット。おじさんのパレット（`OjisanPixel.palette`）とは別に持つ——食べ物・背景の
    /// 色はキャラクターと混ぜたくない。文字は絵をまたいで同じ意味に使う（`K` は常に縁取り）。
    static let palette: [Character: UInt32] = [
        "K": outline,
        "D": takoyakiDough,
        "d": 0xB8682A,
        "S": 0x5C2C10,
        "s": 0x8E4A1E,
        "M": paperWhite,
        "A": 0x3F8F4C,
        "T": 0xE6C98C,
        // 港町の置物（#1009）。`H`/`h` はロープの麻色 2 階調、`N`/`n`/`L` はドラム缶の青 3 階調
        // （本体・陰・照り）。切り株は上の木肌 `T`・年輪 `d`・樹皮 `S`/`s`・苔 `A` で描ける。
        "H": 0xC9A064,
        "h": 0x8E6A3A,
        "N": 0x2A5480,
        "n": 0x1B3A5C,
        "L": 0x5A86B4,
        // 突き上げ（#1010）。竹の子は穂先の濃い緑 `a` と既にある苔の緑 `A`、皮は `T`（淡い生成り・
        // 主色）と `H`/`h`（皮の重なりの線）、斑点は `s`。波しぶきは泡の淡い水色 `C` と白 `M`、
        // 水柱の陰は `L`/`N`（ドラム缶と同じ青の階調）。
        "a": 0x27663A,
        "C": 0xBFE4F2,
        // 高い塀（#1091）。`G`/`g`/`W` は石垣の石・目地・笠石、`R`/`r`/`O` はコンテナの
        // 本体・桁とリブ・左肩の照り。どちらも**濃い側**（`g` / `r`）が背景との 3:1 を担う
        // （竹の子の `a`・波しぶきの `N` と同じ約束。`WorldTests` が固定）。
        "G": 0x9EA294,
        "g": 0x4A4D45,
        "W": 0xC8CCBE,
        "R": 0xC24A33,
        "r": 0x6E2118,
        "O": 0xC85B45,
        // 宝くじ（#1092）。`Y` は券面の上帯（金）、`P` はそこに刷られた赤い文字・罫線。
        // 紙そのものは既にある `M`（生成りの白）と `T`（淡いクリーム＝切り取り線の側）を使う。
        "Y": lotteryBand,
        "P": lotteryPrint,
        // 雪国（#2729）。`F` は雪の白、`I`/`i`/`J` は氷の 3 階調（青白・青・深い青）。雪だるま・雪柱・
        // 雪山・雪が舞い上がる予告で使い、**濃い側（`J`）が背景との 3:1 を担う**（湯柱の `g`・石垣の `g` と
        // 同じ約束。`WorldTests` が固定）。雪だるまの人参の鼻はたこ焼きの生地 `D`、マフラーはコンテナの赤 `R`、
        // 雪山の泥はねは樹皮の `s` を使う（新しい色を増やしすぎない）。
        "F": snowWhite,
        "I": iceLight,
        "i": iceMid,
        "J": iceDeep,
        // 東京（#2729）。`X` はカラーコーンの橙、`Q`/`q`/`u` はネオン看板の 3 階調（光る水色の面・暗い枠と桁・白い照り）、
        // `c`/`p` はマンホールの蒸気の灰 2 階調（明・中。暗い側は湯柱と同じ `g`）。東京は背景が暗い（宵の口）ので
        // **明るい側（`Q` / `u`・蒸気の `M`）が背景との 3:1 を担う**（夜の繁華街と同じ向き。`RunnerTokyoGimmickTests`）。
        // 自動販売機はコンテナの赤 `R`/`r`/`O` と白 `M`・缶の青 `N`・クリーム `T`、タクシーは `RunnerWorld.Creatures`
        // （イノシシの文字）で描く。
        "X": coneOrange,
        "Q": signboardBody,
        "q": signboardDark,
        "u": signboardLight,
        "c": steamLight,
        "p": steamMid,
    ]

    /// 縁取り（焦げ茶寄りの黒）。全世界の縁取り（`RunnerWorld.outline`・0x0E1420〜0x241A14）と同じ
    /// 濃さで、朝のパステルの丘・壁、夕方の手前の丘（0x6E5A96・いちばん厳しい）の上でも輪郭が立つ
    /// （`WorldTests` が 3:1 を固定。朝の値 0x241A14 は夕方の丘に 2.9 で届かないので一段暗い）。
    static let outline: UInt32 = 0x1A120E

    /// たこ焼きの生地の主色（きつね色）。岩のグレー・地面の茶・鳥の緑のどれとも系統が違う食べ物の色。
    static let takoyakiDough: UInt32 = 0xE8A860

    /// 生成りの白（`M`）。たこ焼きのマヨと、宝くじの券面（#1092）の主色を兼ねる。
    /// **宝くじが背景から浮くかの検査（`WorldTests.foregroundStandsOutFromBackdrops`）はこの色を見る。**
    static let paperWhite: UInt32 = 0xFAF6EC
    /// 宝くじの上帯（金）。
    static let lotteryBand: UInt32 = 0xE4B23C
    /// 宝くじに刷られた赤い文字・罫線。
    static let lotteryPrint: UInt32 = 0xC6314C

    /// 雪の白（`F`・#2729）。紙の生成り（`M`）より青白い。雪だるまの体・雪柱の照り・雪山の天端。
    static let snowWhite: UInt32 = 0xF7FAFC
    /// 氷の青白（`I`）。雪柱・雪山の面。
    static let iceLight: UInt32 = 0xDDEDF6
    /// 氷の青（`i`）。雪だるまの陰・雪柱の中の陰。
    static let iceMid: UInt32 = 0x9DC3DA
    /// 深い氷の青（`J`）。雪柱の右の陰・雪山の目地で、**白い背景との 3:1 を担う濃い側**。
    static let iceDeep: UInt32 = 0x2F5F7E

    /// カラーコーンの橙（`X`・#2729）。白い反射帯は紙の `M`、黒い台は縁取り `K` と暗い灰 `g`。
    static let coneOrange: UInt32 = 0xE8752E
    /// ネオン看板の面（`Q`）。光る水色で、**暗い背景との 3:1 を担う明るい側**。
    static let signboardBody: UInt32 = 0x7FE8F0
    /// 看板の枠と桁（`q`）。暗い鉄の枠。
    static let signboardDark: UInt32 = 0x24384C
    /// 看板の照り・白い文字（`u`）。
    static let signboardLight: UInt32 = 0xF4FBFC
    /// マンホールの蒸気の明るい灰（`c`）。湯柱の `W`（生成り）より青みの灰。
    static let steamLight: UInt32 = 0xD3D7DD
    /// マンホールの蒸気の中の灰（`p`）。
    static let steamMid: UInt32 = 0x9AA1AA

    // MARK: たこ焼き（`RunnerPickupKind.invincible`・#797 → #956）

    /// たこ焼き 1 個（15×18 ドット）。舟皿に 3 個を並べた図形は小さすぎて「何か分からない」
    /// （会長 QA 2026-09-15）ので、1 個を走者の頭ほどの大きさ（高さ 18 ドット ≒ 6 単位）で描く。
    ///
    /// - 丸い生地はきつね色 2 階調（`D` 明・`d` 陰は右下）
    /// - 上面に濃い茶のソース（`S`）と照り（`s`・左上）、その上を白いマヨ（`M`）の線が斜めに走る
    /// - 青のり（`A`）を 3 ドット
    /// - 上に爪楊枝（`T`）1 本（縁取り込みで 3 ドット幅・生地の上に 5 ドット）
    /// - 格子は絵にぴったり（透明な余白の行・列が無い）。シーン側は `anchorPoint = (0.5, 0)` で
    ///   **絵の底の中央**を置き場に合わせる（`RunnerPixelArtTests` が余白なしを固定）
    /// - 特定のキャラクター・作品には寄せない（#494 の権利チェック）
    static let takoyakiRows: [String] = [
        ".......K.......",
        "......KTK......",
        "......KTK......",
        "......KTK......",
        "......KTK......",
        ".....KKTKK.....",
        "...KKSKTKSKK...",
        "..KSssSSSSSSK..",
        ".KSsMMSSASSSSK.",
        "KSsMSSMMSSSSASK",
        "KSSSSSSSMMSSSSK",
        "KSSSASSSSSMMSSK",
        "KDSSDDSSDDDSSdK",
        "KDDDDDDSDDDDddK",
        ".KDDDDDDDDDddK.",
        "..KDDDDDDdddK..",
        "...KKdddddKK...",
        ".....KKKKK.....",
    ]

    static func takoyaki() -> PixelSprite {
        PixelSprite(rows: takoyakiRows, palette: palette)
    }

    // MARK: 犬・イノシシ（`RunnerHazardKind.dog` / `.boar`・#800 #801 → #975）

    /// 地面を走る動物の歩きのコマ。走者の `ride0` / `ride1` と同じく 2 枚を交互に出す。
    enum WalkFrame: Int, CaseIterable, Sendable {
        case walk0 = 0
        case walk1 = 1
    }

    /// 犬・イノシシのパレットは**世界ごと**（`RunnerWorld.creatures`・#929「朝は暗く、夜は明るく」）。
    /// たこ焼きのように 1 つの色で全世界を通すことはできない——イノシシらしい暗い茶は夜の路面
    /// （0x353A48）と 2:1 に届かず、縁取りも暗いので夜には沈む（`WorldTests` の
    /// `creatureBodiesStandOutFromBackdrops` が主色だけで 3:1 を求める）。そこで文字は固定し、
    /// 色だけを世界の `Creatures` から写す。`K` は世界の縁取り（`creatures.outline`）。
    ///
    /// - `O` 犬の体 / `o` 犬の暗部（耳の内側・奥の脚）/ `W` 犬の腹・頬・口元・巻き尾の内 / `R` 首輪
    /// - `B` イノシシの体 / `b` たてがみ・奥の脚・蹄・耳 / `S` 鼻先 / `T` 牙・白目
    static func creaturePalette(_ c: RunnerWorld.Creatures) -> [Character: UInt32] {
        [
            "K": c.outline,
            "O": c.dogBody, "o": c.dogDark, "W": c.dogBelly, "R": dogCollar,
            "B": c.boarBody, "b": c.boarDark, "S": c.boarSnout, "T": RunnerPalette.boarTusk,
        ]
    }

    /// 犬の首輪（赤）。「飼い犬」と分かる記号で、猫との取り違え（#975）を減らす。世界によらない。
    static let dogCollar: UInt32 = 0xD43C2C

    static func dog(_ frame: WalkFrame, colors: RunnerWorld.Creatures) -> PixelSprite {
        PixelSprite(rows: frame == .walk0 ? dogWalk0Rows : dogWalk1Rows, palette: creaturePalette(colors))
    }

    static func boar(_ frame: WalkFrame, colors: RunnerWorld.Creatures) -> PixelSprite {
        PixelSprite(rows: frame == .walk0 ? boarWalk0Rows : boarWalk1Rows, palette: creaturePalette(colors))
    }

    // MARK: 着せ替え（`RunnerWorld.Dressing`・#1009）

    /// 犬の枠の絵（世界の着せ替えで犬か猫）。色は世界の `Creatures` から写す。
    static func walker(_ frame: WalkFrame, world: RunnerWorld) -> PixelSprite {
        switch world.dressing.dog {
        case .dog:  return dog(frame, colors: world.creatures)
        case .cat:  return cat(frame, colors: world.creatures)
        case .deer: return deer(frame, colors: world.creatures)
        case .monkey: return monkey(frame, colors: world.creatures)
        case .fox: return fox(frame, colors: world.creatures)
        }
    }

    /// イノシシの枠の絵（世界の着せ替えでイノシシ・フォークリフト・タクシー）。
    static func charger(_ frame: WalkFrame, world: RunnerWorld) -> PixelSprite {
        switch world.dressing.boar {
        case .boar:     return boar(frame, colors: world.creatures)
        case .forklift: return forklift(frame, colors: world.creatures)
        case .taxi:     return taxi(frame, colors: world.creatures)
        }
    }

    /// 犬の枠の格子（寸法を測る用。`RunnerScene.addDog`）。
    static func walkerRows(world: RunnerWorld) -> [String] {
        switch world.dressing.dog {
        case .dog:  return dogWalk0Rows
        case .cat:  return catWalk0Rows
        case .deer: return deerWalk0Rows
        case .monkey: return monkeyWalk0Rows
        case .fox: return foxWalk0Rows
        }
    }

    /// イノシシの枠の格子（寸法を測る用。`RunnerScene.addBoar`）。
    static func chargerRows(world: RunnerWorld) -> [String] {
        switch world.dressing.boar {
        case .boar:     return boarWalk0Rows
        case .forklift: return forkliftDrive0Rows
        case .taxi:     return taxiDrive0Rows
        }
    }

    /// イノシシの枠の土煙を立てる列（`boarRearFootX` / `forkliftRearWheelX` / `taxiRearWheelX`）。
    static func chargerRearFootX(world: RunnerWorld) -> Double {
        switch world.dressing.boar {
        case .boar:     return boarRearFootX
        case .forklift: return forkliftRearWheelX
        case .taxi:     return taxiRearWheelX
        }
    }

    /// 猫のパレット。犬と同じ文字（`O` 体・`o` 縞と暗部・`W` 胸と口元）に目の `E` を足す。
    /// 首輪 `R` は使わない（野良）。
    static func catPalette(_ c: RunnerWorld.Creatures) -> [Character: UInt32] {
        creaturePalette(c).merging(["E": catEye]) { _, new in new }
    }

    /// 猫の目（黄）。世界によらない。
    static let catEye: UInt32 = 0xE8C84A

    static func cat(_ frame: WalkFrame, colors: RunnerWorld.Creatures) -> PixelSprite {
        PixelSprite(rows: frame == .walk0 ? catWalk0Rows : catWalk1Rows, palette: catPalette(colors))
    }

    /// フォークリフトのパレット。イノシシの文字を機械に読み替える: `B` 車体（錆橙・主色）/ `b` タイヤ・
    /// マスト・ヘッドガード / `S` 鋼のフォークとマストのレール・ホイール / `T` ヘッドライト。
    /// 回転灯と後ろの警告帯の黄 `Y` は世界によらない。
    static func forkliftPalette(_ c: RunnerWorld.Creatures) -> [Character: UInt32] {
        creaturePalette(c).merging(["Y": warningYellow]) { _, new in new }
    }

    /// フォークリフトの回転灯・警告帯の黄。穴の柵（`RunnerPalette.pitEdge`）より少し落とした黄。
    static let warningYellow: UInt32 = 0xF2C14E

    static func forklift(_ frame: WalkFrame, colors: RunnerWorld.Creatures) -> PixelSprite {
        PixelSprite(rows: frame == .walk0 ? forkliftDrive0Rows : forkliftDrive1Rows, palette: forkliftPalette(colors))
    }

    /// タクシー（東京のイノシシの枠・#2729）。イノシシの文字を車に読み替える: `B` 車体（黄・主色）/ `b` タイヤ /
    /// `S` 窓ガラスとバンパー・ホイールの銀 / `T` ヘッドライト / `R` 尾灯（犬の首輪の赤）/ `Y` 屋根の行灯（空車の緑）。
    static func taxiPalette(_ c: RunnerWorld.Creatures) -> [Character: UInt32] {
        creaturePalette(c).merging(["Y": taxiLamp]) { _, new in new }
    }

    /// タクシーの屋根の行灯（空車の緑）。黄色い車体の上で読めるよう黄ではなく緑にする。世界によらない。
    static let taxiLamp: UInt32 = 0x6FE09A

    static func taxi(_ frame: WalkFrame, colors: RunnerWorld.Creatures) -> PixelSprite {
        PixelSprite(rows: frame == .walk0 ? taxiDrive0Rows : taxiDrive1Rows, palette: taxiPalette(colors))
    }

    /// 切り株（`RunnerWorld.Dressing.Block.stump`）。
    static func stump() -> PixelSprite { PixelSprite(rows: stumpRows, palette: palette) }

    /// ロープの束（`RunnerWorld.Dressing.Block.ropeCoil`）。
    static func ropeCoil() -> PixelSprite { PixelSprite(rows: ropeCoilRows, palette: palette) }

    /// ドラム缶（`RunnerWorld.Dressing.Block.drum`）。
    static func drum() -> PixelSprite { PixelSprite(rows: drumRows, palette: palette) }

    /// 湯桶（`RunnerWorld.Dressing.Block.yuoke`・温泉街 案 B）。
    static func yuoke() -> PixelSprite { PixelSprite(rows: yuokeRows, palette: palette) }

    /// 雪だるま（`RunnerWorld.Dressing.Block.snowman`・雪国 #2729）。
    static func snowman() -> PixelSprite { PixelSprite(rows: snowmanRows, palette: palette) }

    /// カラーコーン（`RunnerWorld.Dressing.Block.trafficCone`・東京 #2729）。
    static func trafficCone() -> PixelSprite { PixelSprite(rows: trafficConeRows, palette: palette) }

    /// 自動販売機（`RunnerWorld.Dressing.Block.vendingMachine`・東京 #2729）。
    static func vendingMachine() -> PixelSprite { PixelSprite(rows: vendingMachineRows, palette: palette) }

    /// カラーコーン（東京の低い岩）: 橙の円錐（`X`）に白い反射帯 2 本（`M`）、黒い四角い台（`K`/`g`）。
    /// 低い岩の 4×5 に収まる 12×15。淡い灰の路面の上では橙と縁取りで形が立つ。
    static let trafficConeRows: [String] = [
        "....KKKK....",
        "....KXXK....",
        "....KXXK....",
        "...KXXXXK...",
        "...KMMMMK...",
        "...KMMMMK...",
        "..KXXXXXXK..",
        "..KXXXXXXK..",
        "..KMMMMMMK..",
        ".KXXXXXXXXK.",
        ".KXXXXXXXXK.",
        ".KXXXXXXXXK.",
        "KKKKKKKKKKKK",
        "KggggggggggK",
        "KKKKKKKKKKKK",
    ]

    /// 自動販売機（東京の高い岩）: 赤い筐体（`R`・左の照り `O`・右の陰 `r`）の上半分に白い見本窓（`M`）と
    /// 缶の列（青 `N`・クリーム `T`）、中段にコイン投入口、下段に取り出し口（`g`）。ドラム缶と同じ 12×27。
    static let vendingMachineRows: [String] = [
        "KKKKKKKKKKKK",
        "KORRRRRRRRrK",
        "KOKKKKKKKKrK",
        "KOKMMMMMMKrK",
        "KOKNMTMNMKrK",
        "KOKNMTMNMKrK",
        "KOKMMMMMMKrK",
        "KOKTMNMTMKrK",
        "KOKTMNMTMKrK",
        "KOKMMMMMMKrK",
        "KOKKKKKKKKrK",
        "KORRRRRRRRrK",
        "KORRKKKRRRrK",
        "KORRKgKRRRrK",
        "KORRKKKRRRrK",
        "KORRRRRRRRrK",
        "KORRRRRRRRrK",
        "KORRRRRRRRrK",
        "KOKKKKKKKKrK",
        "KOKggggggKrK",
        "KOKggggggKrK",
        "KOKKKKKKKKrK",
        "KORRRRRRRRrK",
        "KORRRRRRRRrK",
        "KrrrrrrrrrrK",
        "KrrrrrrrrrrK",
        "KKKKKKKKKKKK",
    ]

    /// 雪だるま（雪国の低い岩）: 雪の白（`F`）の 2 段の玉に右側の青い陰（`i`）、炭の目と口（`K`）、人参の鼻（`D`）、
    /// 赤いマフラー（`R`）、胸のボタン（`K`）。白い背景の前では縁取り（`K`）とマフラーの赤で形が立つ。
    static let snowmanRows: [String] = [
        "...KKKKKK...",
        "..KFFFFFFK..",
        ".KFFFFFFFFK.",
        "KFKFFFFKFFiK",
        "KFFFDDFFFFiK",
        "KFFKFFFKFFiK",
        ".KRRRRRRRRK.",
        "KRRFFFFFFRRK",
        "KFFFFFFFFFiK",
        "KFFFFKFFFFiK",
        "KFFFFFFFFiiK",
        "KFFFFKFFFiiK",
        "KFFFFFFFFiiK",
        ".KFFFFFFFiK.",
        ".KKKKKKKKKK.",
    ]

    /// 湯桶（温泉街の低い岩・案 B）: 木の桶（`H`/`h` の縦の板・`S` のたが）に白い手ぬぐい（`M`）を載せる。
    static let yuokeRows: [String] = [
        "...KKKKKK...",
        ".KKMMMMMMKK.",
        "KMMMMMMMMMMK",
        "KTMMMMMMMMTK",
        "KHhHhHhHhHhK",
        "KHhHhHhHhHhK",
        "KSSSSSSSSSSK",
        "KHhHhHhHhHhK",
        "KHhHhHhHhHhK",
        "KHhHhHhHhHhK",
        "KHhHhHhHhHhK",
        "KSSSSSSSSSSK",
        "KHhHhHhHhHhK",
        "KhhhhhhhhhhK",
        "KKKKKKKKKKKK",
    ]

    // MARK: 突き上げ（`RunnerHazardKind.shoot`・#1010）

    /// 伸び切った突き上げの絵（着せ替えから直接引く）。
    ///
    /// **着せ替え → 絵の対応はここ 1 か所だけ**。`RunnerScene` は世界から着せ替えを引いて
    /// この関数に渡すだけで、世界と絵の対応を自分では持たない（かつては
    /// 「着せ替え → 世界 → 着せ替え → 絵」と 2 度写していて、途中で取り違えても
    /// テストで気付けなかった）。
    static func shootArt(for style: RunnerWorld.Dressing.Shoot) -> PixelSprite {
        switch style {
        case .bambooShoot: return PixelSprite(rows: bambooShootRows, palette: palette)
        case .seaSpray:    return PixelSprite(rows: seaSprayRows, palette: palette)
        case .steamColumn: return PixelSprite(rows: steamColumnRows, palette: palette)
        case .snowSpout:   return PixelSprite(rows: snowSpoutRows, palette: palette)
        case .manholeSteam: return PixelSprite(rows: manholeSteamRows, palette: palette)
        }
    }

    /// 突き上げの予告の絵（土が盛り上がる／泡が立つ）。対応は `shootArt(for:)` と同じ作法。
    static func shootCueArt(for style: RunnerWorld.Dressing.Shoot) -> PixelSprite {
        switch style {
        case .bambooShoot: return PixelSprite(rows: soilMoundRows, palette: palette)
        case .seaSpray:    return PixelSprite(rows: foamRows, palette: palette)
        case .steamColumn: return PixelSprite(rows: steamBubbleRows, palette: palette)
        case .snowSpout:   return PixelSprite(rows: snowPuffRows, palette: palette)
        case .manholeSteam: return PixelSprite(rows: manholeLidRows, palette: palette)
        }
    }

    /// 世界から引く版（テスト・寸法の測り方で使う）。
    /// 高い塀の絵（#1091）。**絵の選び方は持たない**——着せ替え（`RunnerWorld.Dressing.Wall`）を
    /// そのまま受け取って対応する格子を返すだけ（突き上げの `shootArt(for:)` と同じ作法）。
    static func wallArt(for style: RunnerWorld.Dressing.Wall) -> PixelSprite {
        switch style {
        case .stoneWall:      return PixelSprite(rows: stoneWallRows, palette: palette)
        case .containerStack: return PixelSprite(rows: containerStackRows, palette: palette)
        case .snowBank:       return PixelSprite(rows: snowBankRows, palette: palette)
        case .signboardStack: return PixelSprite(rows: signboardStackRows, palette: palette)
        }
    }

    static func shoot(world: RunnerWorld) -> PixelSprite { shootArt(for: world.dressing.shoot) }
    static func shootCue(world: RunnerWorld) -> PixelSprite { shootCueArt(for: world.dressing.shoot) }

    /// 歩きのコマを、**自分が進んだ距離**（ワールド単位・0 以上）から選ぶ。`stride` ごとに
    /// `walk0` / `walk1` を入れ替える（走者の `RunnerRider.pedalFrame` と同じ作法。位相ではなく
    /// 距離で刻むのは、動物の速さがルール層の定数 `dogAdvance` / `boarAdvance` で決まっていて、
    /// 描画側で時間を数える必要が無いから）。距離が負（まだ現れていない）なら `walk0`。
    static func walkFrame(travel: Double, stride: Double) -> WalkFrame {
        guard travel > 0, stride > 0 else { return .walk0 }
        let steps = Int((travel / stride).rounded(.down))
        return steps.isMultiple(of: 2) ? .walk0 : .walk1
    }

    /// 犬の 1 歩（ワールド単位）。犬は自分の速さ `dogAdvance`（走者の 0.35 倍）でトコトコ歩くので
    /// 短く刻む。
    static let dogWalkStride: Double = 1.6

    /// イノシシの 1 歩。突進（走者と同じ速さ）なので大きく刻む。
    static let boarWalkStride: Double = 2.5

    /// イノシシの後ろ脚の足元の x（絵の左端からのドット数。脚の中心）。土煙（`RunnerScene.addBoar`
    /// の `movingOnly`）をここに立てる。2 コマとも後ろの 2 本の脚はこの列を挟んで並ぶ
    /// （`RunnerPixelArtTests` が底の行で確かめる）。
    static let boarRearFootX: Double = 27.5

    /// 犬（柴犬・左向き）30×21 ドット（#975）。
    ///
    /// 会長 QA「犬が猫に見える・脚が長い」への答え: **横長の胴に短い脚**（脚は下の 5 行 = 全体の
    /// 1/4 以下）、**前へ突き出たマズル**（額より 2 ドット前に出て、先に黒い鼻）、三角の立ち耳
    /// （内側は暗い `o`）、**背中の上で丸く巻いた尾**（尻から立ち上がって前へ巻く）、頬・胸・腹の
    /// 薄い色（`W`・柴の「裏白」）、赤い首輪。猫に見せないため、細い立ち尾・丸い小顔にはしない。
    /// 頭が x の小さい側（左）で、右から左へ歩いて来る向きそのもの——シーン側は反転しない。
    /// 2 コマの違いは脚だけ（`walk0` は手前の前脚が前・奥の後脚が前、`walk1` は逆）。
    static let dogWalk0Rows: [String] = dogBodyRows + [
        ".......KKOOKKKooKKKKKooKKKOOK.",
        "........KOOK.KooK...KooK.KOOK.",
        "........KOOK.KooK...KooK.KOOK.",
        "........KOOK.KooK...KooK.KOOK.",
        "........KOOK.KooK...KooK.KOOK.",
        "........KKKK.KKKK...KKKK.KKKK.",
    ]

    static let dogWalk1Rows: [String] = dogBodyRows + [
        ".......KooKKKOOKKKKKKOOKKooKK.",
        ".......KooK.KOOK....KOOKKooK..",
        ".......KooK.KOOK....KOOKKooK..",
        ".......KooK.KOOK....KOOKKooK..",
        ".......KooK.KOOK....KOOKKooK..",
        ".......KKKK.KKKK....KKKKKKKK..",
    ]

    /// 犬の頭・胴・尾（脚より上の 15 行）。2 コマで共通。
    private static let dogBodyRows: [String] = [
        "....KK...KK...................",
        "....KOK.KOK...................",
        "...KOoKKOoK...........KKKKK...",
        "...KOOOOOOK..........KOOOOOK..",
        "..KOOOOOOOOK........KOOWWOOOK.",
        "..KOOKWOOOOOK.......KOWKKWOOK.",
        "..KOOOOOOOOOOK......KOWK.KOOK.",
        ".KOOOOOOOOOOORKKKKKKKOOK.KOOK.",
        "KKWWOOOOOOOOORROOOOOOOOOKOOOK.",
        "KWWWWWOOOOOOORROOOOOOOOOOOOOOK",
        "KWWWWWWOOOOOOORROOOOOOOOOOOOOK",
        ".KWWWWWWOOOOOORROOOOOOOOOOOOOK",
        "..KWWWWWWOOOOORRWWWWWWWWWWOOOK",
        "...KKWWWWWWWWWRRWWWWWWWWWWOOOK",
        ".....KKWWWWWWWWWWWWWWWWWWWOOK.",
    ]

    /// イノシシ（左向き）33×23 ドット（#975）。
    ///
    /// 会長 QA「イノシシが熊に見える・脚が長い」への答え: **低く重いくさび形**（肩が高く、背中は
    /// 尻へ向かって下がる）、**極端に短い脚**（下の 4 行）、前へ長く伸びた頭の先に**下向きの鼻先**
    /// （`S`・鼻の穴 2 つ）と口元から上へ反る**白い牙**（`T`）、頭から肩へ**たてがみの毛の段**
    /// （`b`・上に 2 本のとげ）、小さな立ち耳（内側 `S`）、尻に短く立つ尾。熊に見せないため、
    /// 丸い耳・直立した体つきにはしない。頭は左（右から左へ突進する向き）。
    /// 鼻先が絵の左端（列 0）に接する——シーン側はこの左端を当たり判定の左端に合わせる（岩で
    /// 止まったとき鼻先が岩に触れた形になる。#943 の `boarSnout` と同じ約束）。
    static let boarWalk0Rows: [String] = boarBodyRows + [
        "....KKbKKKBBKKKKKKKKKKKbbKKBBK...",
        "....KbbK.KBBK.........KbbKKBBK...",
        "....KbbK.KBBK.........KbbKKBBK...",
        "....KbbK.KbbK.........KbbKKbbK...",
        "....KKKK.KKKK.........KKKKKKKK...",
    ]

    static let boarWalk1Rows: [String] = boarBodyRows + [
        ".....KBBKKKbbKKKKKKKKKBBKKKbbK...",
        ".....KBBK.KbbK.......KBBK.KbbK...",
        ".....KBBK.KbbK.......KBBK.KbbK...",
        ".....KbbK.KbbK.......KbbK.KbbK...",
        ".....KKKK.KKKK.......KKKK.KKKK...",
    ]

    /// イノシシの頭・胴・たてがみ・尾（脚より上の 18 行）。2 コマで共通。
    private static let boarBodyRows: [String] = [
        ".......K.....K...................",
        "......KbK.K.KbK..................",
        ".....KbbKKSKKbbKK................",
        "....KbbbKSSKbbbbbKKK.............",
        "...KbBBBbbbbbbbbbbbbKKK.........K",
        "..KbBBBBBBbbbbbbbbbbbbbKKK......K",
        "..KBBBBBBBBBBBbbbbbbbbbbbbKKK...K",
        ".KBBBBKTBBBBBBBBBBBBBbbbbbbbbKKK.",
        ".KBBBBBBBBBBBBBBBBBBBBBBBbbbbbBBK",
        "KSSKBBBBBBBBBBBBBBBBBBBBBBBBbbBBK",
        "KSSSKBBBBBBBBBBBBBBBBBBBBBBBBBBBK",
        "KSKSKBBBBBBBBBBBBBBBBBBBBBBBBBBBK",
        "KSSSKBBBBBBBBBBBBBBBBBBBBBBBBBBBK",
        "KSSKTBBBBBBBBBBBBBBBBBBBBBBBBBBBK",
        ".KKKKTBBBBBBBBBBBBBBBBBBBBBBBBBK.",
        "....KTKBBBBBBBBBBBBBBBBBBBBBBBBK.",
        ".....KKBBBBBBBBBBBBBBBBBBBBBBBK..",
        "......KBBBBBBBBBBBBBBBBBBBBBBK...",
    ]

    // MARK: 野良猫（港町の犬の枠・#1009）

    /// 野良猫（左向き）30×21 ドット。犬と同じ格子・同じ脚の段（下の 6 行、うち脚は 5 行）で、
    /// `RunnerScene.addDog` が犬と同じ置き方で貼れる（当たり判定・寸法は犬のまま）。
    ///
    /// 犬との見分けは**三角の立ち耳が頭の上に 2 つ・短い顔・細く立ち上がって先が前に曲がる尾・
    /// 背中の縞（`o`）・胸と口元の薄い色（`W`）・黄色い目（`E`）・首輪なし**。#975 で犬から
    /// 意図的に外した「猫らしさ」をこちらに集めてある。頭は左（右から左へ歩いて来る向き）。
    static let catWalk0Rows: [String] = catBodyRows + [
        ".....KOOKKKooKKKKooKKKOOK.....",
        ".....KOOK.KooK..KooK.KOOK.....",
        ".....KOOK.KooK..KooK.KOOK.....",
        ".....KOOK.KooK..KooK.KOOK.....",
        ".....KOOK.KooK..KooK.KOOK.....",
        ".....KKKK.KKKK..KKKK.KKKK.....",
    ]

    static let catWalk1Rows: [String] = catBodyRows + [
        ".....KooKKKOOKKKKOOKKKooK.....",
        ".....KooK.KOOK..KOOK.KooK.....",
        ".....KooK.KOOK..KOOK.KooK.....",
        ".....KooK.KOOK..KOOK.KooK.....",
        ".....KooK.KOOK..KOOK.KooK.....",
        ".....KKKK.KKKK..KKKK.KKKK.....",
    ]

    /// 猫の頭・胴・尾（脚より上の 15 行）。2 コマで共通。
    private static let catBodyRows: [String] = [
        "...........................KK.",
        "..........................KOOK",
        "..KK....KK...............KOoOK",
        "..KOK..KOK..............KOOKK.",
        "..KOoKKoOK.............KOoK...",
        "..KOOOOOOK.............KOOK...",
        ".KOOOOOOOOK...........KOoOK...",
        ".KOEKOOOOOOK..........KOOK....",
        "KWOOOOOOOOOKKKKKKKKKKKOoK.....",
        "KWWKOOOOOOOOOOoOOOOoOOOOK.....",
        ".KWWWOOOOOOOOOOoOOOOoOOOK.....",
        "..KKOOOOOOOOOOOOoOOOOoOOK.....",
        "...KWWWOOOOOOOOOOOOOOOOOK.....",
        "...KWWWWWWWWOOOOOOOOOOOOK.....",
        "....KWWWWWWWWWWWWWWWWWOOK.....",
    ]

    // MARK: 奈良の鹿（京都・奈良の犬の枠・#1824）

    /// 鹿（左向き）30×21 ドット。犬・猫と同じ格子・同じ脚の段（下の 6 行、うち脚は 5 行）で、
    /// `RunnerScene.addDog` が犬と同じ置き方で貼れる（当たり判定・寸法・動きは犬のまま）。
    /// 色は犬と同じ文字で世界の `Creatures` から写す（`O` 体・`o` 暗部・`W` 白・`K` 縁取り）。
    ///
    /// 鹿に見せる要素: **長い首の先の小さな頭**（胴より上に突き出す）、頭の上の**小さな枝角 1 本**と
    /// 後ろ向きの耳（`o`）、**背中の白い斑点**と**白いお尻**（鹿の子模様と尻の白）、細い脚（幅 1 ドット）。
    /// 犬・猫と取り違えないため、巻き尾・立ち尾・首輪は持たない。頭は左（右から左へ歩いて来る向き）。
    /// 2 コマの違いは脚だけ（犬と同じ約束。`walk0` は手前の前脚が前・奥の後脚が前、`walk1` は逆）。
    static func deer(_ frame: WalkFrame, colors: RunnerWorld.Creatures) -> PixelSprite {
        PixelSprite(rows: frame == .walk0 ? deerWalk0Rows : deerWalk1Rows, palette: creaturePalette(colors))
    }

    static let deerWalk0Rows: [String] = deerBodyRows + [
        "..........KOKKoKKKKKKKKoKKOK..",
        "..........KOKKoK......KoKKOK..",
        "..........KOKKoK......KoKKOK..",
        "..........KOKKoK......KoKKOK..",
        "..........KOKKoK......KoKKOK..",
        "...........K..K........K..K...",
    ]

    static let deerWalk1Rows: [String] = deerBodyRows + [
        "..........KoKKOKKKKKKKKOKKoK..",
        "..........KoKKOK......KOKKoK..",
        "..........KoKKOK......KOKKoK..",
        "..........KoKKOK......KOKKoK..",
        "..........KoKKOK......KOKKoK..",
        "...........K..K........K..K...",
    ]

    /// 鹿の頭・首・胴（脚より上の 15 行）。2 コマで共通。
    private static let deerBodyRows: [String] = [
        "....KK...K....................",
        "...KooK.KOK...................",
        "....KooKOoK...................",
        "...KKoKKOoK...................",
        "..KOOOOOOK....................",
        ".KOOOOOOOOK...................",
        "KKOOKOOOOOOK..................",
        ".KWWOOOOOOOOK.KKKKKKKKK.......",
        "..KKKKKOOOOOOKOOOOOOOOOKKKK...",
        ".......KOoOOOOOOWOOWOOWOOOWKK.",
        "........KKoOOWOOOOOOOOOOOWWWWK",
        ".........KOoOOOWOOWOOWOOWWWWWK",
        ".........KOOWOOOOOOOOOOWWWWWK.",
        "..........KKOOOOWWWWWWOOOWWK..",
        "...........KKKWWWWWWWWWWKKK...",
    ]

    // MARK: ニホンザル（温泉街の犬の枠・#1938）

    /// サル（左向き）30×21 ドット。犬・猫・鹿と同じ格子・同じ脚の段。色は犬と同じ文字で世界の `Creatures` から
    /// 写し、顔の赤だけ犬の首輪の `R` を流用する。
    /// サルに見せる要素: **赤い顔**を薄い毛（`W`）が囲む、丸い頭に小さな耳（`o`）、**前かがみに盛り上がった背中**、
    /// 腹の薄い毛、ごく短い尾（`o`）。
    static func monkey(_ frame: WalkFrame, colors: RunnerWorld.Creatures) -> PixelSprite {
        PixelSprite(rows: frame == .walk0 ? monkeyWalk0Rows : monkeyWalk1Rows, palette: creaturePalette(colors))
    }

    static let monkeyWalk0Rows: [String] = monkeyBodyRows + [
        "..........KOOKKKooKKKKooKKOOK.",
        "..........KOOK.KooK..KooKKOOK.",
        "..........KOOK.KooK..KooKKOOK.",
        "..........KOOK.KooK..KooKKOOK.",
        "..........KOOK.KooK..KooKKOOK.",
        "..........KKKK.KKKK..KKKKKKKK.",
    ]

    static let monkeyWalk1Rows: [String] = monkeyBodyRows + [
        "..........KooKKKOOKKKKOOKKooK.",
        "..........KooK.KOOK..KOOKKooK.",
        "..........KooK.KOOK..KOOKKooK.",
        "..........KooK.KOOK..KOOKKooK.",
        "..........KooK.KOOK..KOOKKooK.",
        "..........KKKK.KKKK..KKKKKKKK.",
    ]

    private static let monkeyBodyRows: [String] = [
        "...KKKK........KKKKKK.........",
        "..KOOOOK.....KKOOOOOOKK.......",
        ".KOOOOOOK...KOOOoOOOOoOKK.....",
        ".KoKWWWWKK.KOOOOOOOOOOOOOK....",
        "KOoKWRRRRWKOOOoOOOOoOOOOOOK...",
        "KOOKWRKRKRWKOOOOOOOOOOOOOOOK..",
        ".KKWWRRRRRWKOOOOOOOOOOOOOOOK..",
        "..KWWRRKKRWKOOOOOOOOOOOOOOOOK.",
        "..KWWWRRRRWKOOOOOOOOOOOOOOOOK.",
        "...KKWWWWWKOOOWWOOOOOOOOOOOOK.",
        ".....KKKKKOOWWWWWOOOOOOOOOOOoK",
        "........KOWWWWWWWOOOOOOOOOOKoK",
        ".........KWWWWWWWWWWOOOOOOOKK.",
        ".........KKWWWWWWWWWWWWOOOOK..",
        "..........KKKWWWWWWWWWKKOOOK..",
    ]

    // MARK: キタキツネ（雪国の犬の枠・#2729）

    /// キタキツネ（左向き）30×21 ドット。犬・猫・鹿・サルと同じ格子・同じ脚の段（下の 6 行、うち脚は 5 行）で、
    /// `RunnerScene.addDog` が犬と同じ置き方で貼れる（当たり判定・寸法・動きは犬のまま）。
    /// 色は犬と同じ文字で世界の `Creatures` から写す（`O` 赤錆の毛・`o` 黒い脚と耳の先と鼻・`W` 白・`K` 縁取り）。
    ///
    /// キツネに見せる要素: **前へ細く突き出た鼻先**（犬のマズルより長く、先に黒い鼻）、頭の上の**大きな三角の耳**
    /// （先が黒）、胸から腹へ続く**白い毛**、**後ろへ長く伸びて先が白いふさふさの尾**（犬の巻き尾・猫の立ち尾・
    /// 鹿の枝角とは別物）、**黒い脚**（キツネの黒い靴下。手前の脚は `o`、奥の脚は縁取りの色で沈める）。
    /// 首輪は持たない（野生）。頭は左（右から左へ歩いて来る向き）。2 コマの違いは脚だけ（犬と同じ約束）。
    static func fox(_ frame: WalkFrame, colors: RunnerWorld.Creatures) -> PixelSprite {
        PixelSprite(rows: frame == .walk0 ? foxWalk0Rows : foxWalk1Rows, palette: creaturePalette(colors))
    }

    static let foxWalk0Rows: [String] = foxBodyRows + [
        "........KKooKKKKKKKKKKKKKooKK.",
        "........KooK.KKKK...KKKK.KooK.",
        "........KooK.KKKK...KKKK.KooK.",
        "........KooK.KKKK...KKKK.KooK.",
        "........KooK.KKKK...KKKK.KooK.",
        "........KKKK.KKKK...KKKK.KKKK.",
    ]

    static let foxWalk1Rows: [String] = foxBodyRows + [
        "........KKKKKKooKKKKKooKKKKKK.",
        "........KKKK.KooK...KooK.KKKK.",
        "........KKKK.KooK...KooK.KKKK.",
        "........KKKK.KooK...KooK.KKKK.",
        "........KKKK.KooK...KooK.KKKK.",
        "........KKKK.KKKK...KKKK.KKKK.",
    ]

    /// キツネの頭・胴・尾（脚より上の 15 行）。2 コマで共通。
    private static let foxBodyRows: [String] = [
        "..KK....KK....................",
        "..KoK..KoK....................",
        "..KOOK.KOOK.............KKKKK.",
        "..KOWOKKOWOK...........KWWWWWK",
        ".KOOOOOOOOOK..........KWWWOOOK",
        ".KOOOOOOOOOOK........KWWOOOOOK",
        "KKWOOOOOOOOOOKKKKKKKKKOOOOOOOK",
        "KoKWWOOOOOOOOOOOOOOOOOOOOOOOOK",
        "KKWWWWOOOOOOOOOOOOOOOOOOOOOOK.",
        ".KWWWWWOOOOOOOOOOOOOOOOOOOOK..",
        "..KWWWWWWOOOOOOOOOOOOOOOOOK...",
        "...KKWWWWWWOOOOOOOOOOOOOOOK...",
        ".....KWWWWWWWWWWWWOOOOOOOOK...",
        ".....KKWWWWWWWWWWWWWWOOOOOK...",
        ".......KKWWWWWWWWWWWWWWOOOK...",
    ]

    // MARK: フォークリフト（港町のイノシシの枠・#1009）

    /// フォークリフト（左向き）33×23 ドット。イノシシと同じ格子で、`RunnerScene.addBoar` が
    /// イノシシと同じ置き方（左端＝当たり判定の左端）で貼れる。**フォークの先が絵の左端（列 0）**
    /// ——イノシシの鼻先と同じ約束で、ドラム缶にぶつかって止まるとフォークが缶に触れた形になる。
    ///
    /// 左からフォーク 2 本（`S`・地面の高さ）・マスト（`S` のレール 2 本に `b` の芯）・ヘッドガード
    /// （`b` の枠に回転灯 `Y`）・錆橙の車体（`B`）にヘッドライト（`T`）・後ろのカウンターウェイトに
    /// 黄黒の警告帯・タイヤ 2 つ（`b`・ホイール `S`）。運転席は空で誰も乗せない（おじさんシリーズの
    /// 顔を機械に付けない）。2 コマの違いはホイールの向きだけ（走っていると分かる程度）。
    static let forkliftDrive0Rows: [String] = forkliftBodyRows + [
        "........KbbbKKbbbbK....KbbbbK....",
        "........KKKKKKbSSbK....KbSSbK....",
        "KKKKKKKKKKKK.KbSSbK....KbSSbK....",
        "KSSSSSSSSSSK.KbbbbK....KbbbbK....",
        "KKKKKKKKKKKK..KKKK......KKKK.....",
    ]

    static let forkliftDrive1Rows: [String] = forkliftBodyRows + [
        "........KbbbKKbbbbK....KbbbbK....",
        "........KKKKKKbbSbK....KbbSbK....",
        "KKKKKKKKKKKK.KbSbbK....KbSbbK....",
        "KSSSSSSSSSSK.KbbbbK....KbbbbK....",
        "KKKKKKKKKKKK..KKKK......KKKK.....",
    ]

    /// フォークリフトの後輪の中心の列（絵の左端からのドット数）。土煙（排気）はここに立てる。
    static let forkliftRearWheelX: Double = 25.5

    /// フォークリフトのマスト・ヘッドガード・車体（タイヤより上の 18 行）。2 コマで共通。
    private static let forkliftBodyRows: [String] = [
        "...................KKKKK.........",
        "..............KKKKKKYYYKKKKKKK...",
        "..............KbbbbbbbbbbbbbbK...",
        "........KKKKK.KbbKKKKKKKKKKbbK...",
        "........KSbSK.KbbK........KbbK...",
        "........KSbSK.KbbK.......KKbbK...",
        "........KSbSK.KbbK.......KbbbK...",
        "........KSbSK.KbbK.......KbbbK...",
        "........KSbSKKKbbK.......KbbbK...",
        "........KSbSKBBBBBKKKKKKKBBBBKKK.",
        "........KSbSKBBBBBBBBBBBBBBBBBBBK",
        "........KSbSKTBBBBBBBBBBBBBBBBBBK",
        "........KSbSKBBBBBBBBBBBBBBBKYKYK",
        "........KSbSKBBBBBBBBBBBBBBBKYKYK",
        "........KSbSKBBBBBBBBBBBBBBBBBBBK",
        "........KSbSKBBBBBBBBBBBBBBBBBBBK",
        "........KSbSKBBBBBBBBBBBBBBBBBBBK",
        "........KSbSKKKKKKKKKKKKKKKKKKKKK",
    ]

    // MARK: タクシー（東京のイノシシの枠・#2729）

    /// タクシー（左向き）33×23 ドット。フォークリフトと同じ格子で、`RunnerScene.addBoar` がイノシシと同じ置き方
    /// （左端＝当たり判定の左端）で貼れる。**ヘッドライト（`T`）が絵の左端（列 0〜2）**——イノシシの鼻先・
    /// フォークの先と同じ約束で、自動販売機にぶつかって止まるとバンパーが筐体に触れた形になる。
    ///
    /// 黄色い車体（`B`）に銀の窓（`S`）3 枚、屋根の行灯（`Y`）、前のヘッドライト（`T`）、後ろの尾灯（`R`）、
    /// 銀のバンパー（`S`）、黒いタイヤ（`b`）に銀のホイール（`S`）。運転席は空で誰も乗せない
    /// （フォークリフトと同じ）。2 コマの違いはホイールの向きだけ（走っていると分かる程度）。
    static let taxiDrive0Rows: [String] = taxiBodyRows + [
        "....KbbbbKKKKKKKKKKKKKKKbbbbK....",
        "....KbSSbK.............KbSSbK....",
        "....KbSSbK.............KbSSbK....",
        "....KbSSbK.............KbSSbK....",
        ".....KKKK...............KKKK.....",
    ]

    static let taxiDrive1Rows: [String] = taxiBodyRows + [
        "....KbbbbKKKKKKKKKKKKKKKbbbbK....",
        "....KbbSbK.............KbbSbK....",
        "....KbSbbK.............KbSbbK....",
        "....KbSSbK.............KbSSbK....",
        ".....KKKK...............KKKK.....",
    ]

    /// タクシーの後輪の中心の列（絵の左端からのドット数）。土煙（排気）はここに立てる。
    static let taxiRearWheelX: Double = 25.5

    /// タクシーの屋根・窓・車体（タイヤより上の 18 行）。2 コマで共通。
    private static let taxiBodyRows: [String] = [
        "..............KKKKK..............",
        "..............KYYYK..............",
        "..........KKKKKYYYKKKKKKK........",
        "..........KBBBBBBBBBBBBBK........",
        ".........KBBKSSSSKBKSSSSSKKK.....",
        "........KBBKSSSSSKBKSSSSSKBBKK...",
        ".......KBBBKSSSSSKBKSSSSSKBBBBK..",
        "......KBBBBKSSSSSKBKSSSSSKBBBBBK.",
        ".....KBBBBBKKKKKKKBKKKKKKKBBBBBBK",
        "....KBBBBBBBBBBBBBBBBBBBBBBBBBBBK",
        "...KBBBBBBBBBBBBBBBBBBBBBBBBBBBBK",
        "..KBBBBBBBBBBBBBBBBBBBBBBBBBBBBBK",
        ".KBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBK",
        "KTTBBBBBBBBBBBBBBBBBBBBBBBBBBBBBK",
        "KTTBBBBBBBBBBBBBBBBBBBBBBBBBBRRK.",
        "KSSSBBBBBBBBBBBBBBBBBBBBBBBBSSSK.",
        "KKKKBBBBBBBBBBBBBBBBBBBBBBBBKKKK.",
        "....KBBBBBBBBBBBBBBBBBBBBBBBK....",
    ]

    // MARK: 切り株・ロープの束・ドラム缶（岩の枠・#1009）

    /// 岩の枠の置物は**当たり判定の箱いっぱい**に描く（岩塊 `RunnerScene.makeRock` と同じ）。
    /// 低い岩は幅 4 × 高さ 5、高い岩は 4 × 9 なので、格子は 12×15 と 12×27（1 ドット ≒ 0.33 単位
    /// ＝走者と同じ）。縦横比が箱と一致することは `RunnerPixelArtTests` が固定する。
    ///
    /// 切り株（里山の低い岩）: 上面は木肌（`T`）に年輪（`d`）、側面は樹皮の縦の筋（`S`/`s`）と苔（`A`）。
    static let stumpRows: [String] = [
        "...KKKKKK...",
        ".KKTTTTTTKK.",
        "KTTTddddTTTK",
        "KTTdTTTTdTTK",
        "KTTTddddTTTK",
        "KsTTTTTTTTsK",
        "KSsSSsSSSsSK",
        "KSsSSsSSSsSK",
        "KSsSSsSSSsSK",
        "KSsSAsSSSsSK",
        "KSsSAAsSSsSK",
        "KSsSSsSSSsSK",
        "KSSSSsSSSSSK",
        "KSSSSSSSSSSK",
        "KKKKKKKKKKKK",
    ]

    /// ロープの束（港町の低い岩）: 上面は渦巻きに巻いた麻縄（`H`/`h`）、側面は横の縄の段。
    static let ropeCoilRows: [String] = [
        "...KKKKKK...",
        ".KKHHHHHHKK.",
        "KHHhhhhhhHHK",
        "KHhHHHHHHhHK",
        "KHhHhhhhHhHK",
        "KHhHhHHhHhHK",
        "KHhHHHHhHhHK",
        "KHhhhhhhhhHK",
        "KHHHHHHHHHHK",
        "KhHHHHHHHHhK",
        "KHhhhhhhhhHK",
        "KHHHHHHHHHHK",
        "KHhhhhhhhhHK",
        "KHHHHHHHHHHK",
        "KKKKKKKKKKKK",
    ]

    /// ドラム缶（港町の高い岩）: 青い缶（`N`）に左の照り（`L`）と右の陰（`n`）、上の蓋と 2 本のリブ。
    static let drumRows: [String] = [
        "..KKKKKKKK..",
        ".KLLNNNNNNK.",
        "KLLNNNNNNnnK",
        "KnnnnnnnnnnK",
        "KLLNNNNNNnnK",
        "KLLNNNNNNnnK",
        "KLLNNNNNNnnK",
        "KLLNNNNNNnnK",
        "KLLNNNNNNnnK",
        "KLLNNNNNNnnK",
        "KLLLLLLLLLnK",
        "KnnnnnnnnnnK",
        "KLLNNNNNNnnK",
        "KLLNNNNNNnnK",
        "KLLNNNNNNnnK",
        "KLLNNNNNNnnK",
        "KLLNNNNNNnnK",
        "KLLLLLLLLLnK",
        "KnnnnnnnnnnK",
        "KLLNNNNNNnnK",
        "KLLNNNNNNnnK",
        "KLLNNNNNNnnK",
        "KLLNNNNNNnnK",
        "KLLNNNNNNnnK",
        "KLLNNNNNNnnK",
        "KnnnnnnnnnnK",
        "KKKKKKKKKKKK",
    ]

    // MARK: 高い塀の絵（#1091）

    /// 石垣（里山の高い塀）。当たり判定は 4×18 なので格子は 12×54
    /// （`RunnerPixelArtTests.wallsFitTheWallHitBox` が縦横比と余白なしを固定）。
    ///
    /// **高い岩（大きな石）と一目で区別できる**（決裁）ようにしてある: 岩塊は 4×9 の丸い塊 1 つだが、
    /// 石垣は**高さが 2 倍以上**あり、横一直線の目地（`g`）で 8 段に積まれた四角い石の列。
    /// 天端の笠石（`W`）で上端が一直線に見えるのも、丸い岩との違いを作っている。
    /// 下のほうの石には苔（`A`・切り株と同じ緑）を差して、地面に古くから在る物に見せる。
    static let stoneWallRows: [String] = [
        "KKKKKKKKKKKK",
        "KWWWWWWWWWWK",
        "KWWWWWWWWWWK",
        "KWWWWWWWWWWK",
        "KggggggggggK",
        "KWWWgWWWgWWK",
        "KGGGgGGGgGGK",
        "KGGGgGGGgGGK",
        "KGGGgGGGgGGK",
        "KGGGgGGGgGGK",
        "KGGGgGGGgGGK",
        "KggggggggggK",
        "KWWWWWgWWWgK",
        "KGGGGGgGGGgK",
        "KGGGGGgGGGgK",
        "KGGGGGgGGGgK",
        "KGGGGGgGGGgK",
        "KGGGGGgGGGgK",
        "KggggggggggK",
        "KWWgWWWgWWWK",
        "KGGgGGGgGGGK",
        "KGGgGGGgGGGK",
        "KGGgGGGgGGGK",
        "KGGgGGGgGGGK",
        "KGGgGGGgGGGK",
        "KggggggggggK",
        "KWWWWgWWWgWK",
        "KGGGGgGGGgGK",
        "KGGGGgGGGgGK",
        "KGGGGgGGGgGK",
        "KGGGGgGGGgGK",
        "KGGGGgGGGgGK",
        "KggggggggggK",
        "KWWWgWWWWgWK",
        "KGGGgGGGGgGK",
        "KGGGgGGGGgGK",
        "KGAGgGGGGgGK",
        "KGAGgGGGGgGK",
        "KGGGgGGGGgGK",
        "KggggggggggK",
        "KWWgWWgWWWWK",
        "KGGgGGgGGGGK",
        "KGGgGGgGGGGK",
        "KGGgGGgGGAGK",
        "KGGgGGgGGAGK",
        "KGGgGGgGGGGK",
        "KggggggggggK",
        "KWWWWgWWgWWK",
        "KGGGGgGGgGGK",
        "KGGGGgGGgGGK",
        "KGGAGgGGgGGK",
        "KGGAGgGGgGGK",
        "KGGGGgGGgGGK",
        "KKKKKKKKKKKK",
    ]

    /// 積まれたコンテナ（港町の高い塀）。同じ 12×54 の格子に**海上コンテナを 2 段**積む。
    ///
    /// 遠景のコンテナ（`SceneryPalette.containerRust` ほか）は淡い色で奥に置いてあるので、
    /// 手前のこれは**濃い赤**（`R`）と黒に近い桁・リブ（`r`）で描く。段の継ぎ目に桁（`r`）が
    /// 2 本並ぶので、1 個の箱ではなく「2 つ積んである」と読める——ドラム缶（4×9 の円筒）とは
    /// 高さも形も違う。縦のリブ（波板）は列で通してあり、走っていても縦縞として見える。
    static let containerStackRows: [String] = [
        "KKKKKKKKKKKK",
        "KrrrrrrrrrrK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrMRrMRrRK",
        "KORrMRrMRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KrrrrrrrrrrK",
        "KKKKKKKKKKKK",
        "KKKKKKKKKKKK",
        "KrrrrrrrrrrK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrMRrMRrRK",
        "KORrMRrMRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KORrRRrRRrRK",
        "KrrrrrrrrrrK",
        "KKKKKKKKKKKK",
    ]

    /// 除雪の雪山（雪国の高い塀・#2729）。石垣とまったく同じ 12×54 の格子で、色だけが固く締まった雪。
    ///
    /// 天端は雪の白（`F`）、面は氷の青白（`I`）、段と段のあいだの目地は深い氷の青（`J`）で、**目地が
    /// 白い背景との 3:1 を担う**（石垣の `g` と同じ約束）。下の段には除雪で混じった泥はね（`s`）を差して、
    /// 道の脇に積まれた雪だと分かるようにする。雪だるま（4×5 の丸い 2 段）とは高さも形も違う。
    static let snowBankRows: [String] = [
        "KKKKKKKKKKKK",
        "KFFFFFFFFFFK",
        "KFFFFFFFFFFK",
        "KFFFFFFFFFFK",
        "KJJJJJJJJJJK",
        "KFFFJFFFJFFK",
        "KIIIJIIIJIIK",
        "KIIIJIIIJIIK",
        "KIIIJIIIJIIK",
        "KIIIJIIIJIIK",
        "KIIIJIIIJIIK",
        "KJJJJJJJJJJK",
        "KFFFFFJFFFJK",
        "KIIIIIJIIIJK",
        "KIIIIIJIIIJK",
        "KIIIIIJIIIJK",
        "KIIIIIJIIIJK",
        "KIIIIIJIIIJK",
        "KJJJJJJJJJJK",
        "KFFJFFFJFFFK",
        "KIIJIIIJIIIK",
        "KIIJIIIJIIIK",
        "KIIJIIIJIIIK",
        "KIIJIIIJIIIK",
        "KIIJIIIJIIIK",
        "KJJJJJJJJJJK",
        "KFFFFJFFFJFK",
        "KIIIIJIIIJIK",
        "KIIIIJIIIJIK",
        "KIIIIJIIIJIK",
        "KIIIIJIIIJIK",
        "KIIIIJIIIJIK",
        "KJJJJJJJJJJK",
        "KFFFJFFFFJFK",
        "KIIIJIIIIJIK",
        "KIIIJIIIIJIK",
        "KIsIJIIIIJIK",
        "KIsIJIIIIJIK",
        "KIIIJIIIIJIK",
        "KJJJJJJJJJJK",
        "KFFJFFJFFFFK",
        "KIIJIIJIIIIK",
        "KIIJIIJIIIIK",
        "KIIJIIJIIsIK",
        "KIIJIIJIIsIK",
        "KIIJIIJIIIIK",
        "KJJJJJJJJJJK",
        "KFFFFJFFJFFK",
        "KIIIIJIIJIIK",
        "KIIIIJIIJIIK",
        "KIIsIJIIJIIK",
        "KIIsIJIIJIIK",
        "KIIIIJIIJIIK",
        "KKKKKKKKKKKK",
    ]

    /// 積まれたネオン看板（東京の高い塀・#2729）。コンテナとまったく同じ 12×54 の格子で、色だけが光る水色
    /// ——面は `Q`、枠と桁は `q`、左肩の照りは `u`、白い文字は `M`。**面（`Q`）が宵の暗い背景との 3:1 を担う**
    /// （背景が暗い世界は明るい側が担う。夜の繁華街と同じ向き）。
    static let signboardStackRows: [String] = [
        "KKKKKKKKKKKK",
        "KqqqqqqqqqqK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqMQqMQqQK",
        "KuQqMQqMQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KqqqqqqqqqqK",
        "KKKKKKKKKKKK",
        "KKKKKKKKKKKK",
        "KqqqqqqqqqqK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqMQqMQqQK",
        "KuQqMQqMQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KuQqQQqQQqQK",
        "KqqqqqqqqqqK",
        "KKKKKKKKKKKK",
    ]

    // MARK: 突き上げの絵（#1010）

    /// 竹の子（里山の突き上げ）。当たり判定は高い岩と同じ 4×9 なので格子は 12×27
    /// （`RunnerPixelArtTests.shootsFitTheTallHitBox` が縦横比と余白なしを固定）。
    ///
    /// **切り株（低い岩）と明確に見分けられる形と色**（決裁）にしてある: 切り株は 4×5 の
    /// 平たい円筒で側面が濃い樹皮（`S`）だが、竹の子は**高さが 2 倍近い円錐**で、主色は
    /// 淡い生成りの皮（`T`）、穂先だけ濃い緑（`a`/`A`）。皮の重なりを `H`/`h` の山形の線で
    /// 3 段入れ、斑点（`s`）を散らしてある。
    static let bambooShootRows: [String] = [
        ".....KK.....",
        ".....KK.....",
        "....KaaK....",
        "....KaaK....",
        "....KaaK....",
        "...KaaaaK...",
        "...KaAAaK...",
        "...KAAAAK...",
        "..KaAAAAaK..",
        "..KAAAAAAK..",
        "..KAAAAAAK..",
        "..KhTTTThK..",
        ".KTThTThTTK.",
        ".KTTTTTTTTK.",
        ".KTTTTTTTTK.",
        ".KhTTTTTThK.",
        "KTTThTTThTTK",
        "KTTTTTTTTTTK",
        "KTTTTTTTTTTK",
        "KTTsTTTTsTTK",
        "KhTTTTTTTThK",
        "KTTThTTThTTK",
        "KTTTTTTTTTTK",
        "KTTTTTTTTTTK",
        "KTTsTTTTTsTK",
        "KhTTTTTTTThK",
        "KKKKKKKKKKKK",
    ]

    /// 波しぶき（港町の突き上げ）。竹の子とまったく同じ格子・同じシルエットで、色だけが水。
    /// **動きと当たり判定は竹の子と 1 つ**（`RunnerHazardKind.shoot`）で、替わるのは絵だけ。
    ///
    /// 港町の背景（海 0x9FC0D4・岬 0xA4C1CE・岸壁 0xB9BDBD）は水と同じ淡い青の帯なので、
    /// **柱の中で左（白い泡 `M`）から右（水の陰 `L`→`N`）へ濃淡を付けて形を立てる**。
    /// 縁取りだけに頼ると、背景に溶けた平たい三角に見える（最初にそう描いて撮って分かった）。
    static let seaSprayRows: [String] = [
        ".....KK.....",
        ".....KK.....",
        "....KMMK....",
        "....KMMK....",
        "....KMCK....",
        "...KMMCLK...",
        "...KMCCLK...",
        "...KMCCLK...",
        "..KMMCCLLK..",
        "..KMCCCLLK..",
        "..KMCCCLNK..",
        "..KMCCCLNK..",
        ".KMMCCCLLNK.",
        ".KMCCMCLLNK.",
        ".KMCCCCLLNK.",
        ".KMMCCCLLNK.",
        "KMMCCCCLLNNK",
        "KMCCMCCLLNNK",
        "KMCCCCCLLNNK",
        "KMMCCCCLLNNK",
        "KMCCMCCLLNNK",
        "KMCCCCCLLNNK",
        "KMMCCCCLLNNK",
        "KMCCMCCLLNNK",
        "KMCCCCCLLNNK",
        "KMMCCCLLNNNK",
        "KKKKKKKKKKKK",
    ]

    /// 湯柱（温泉街の突き上げ・間欠泉）。波しぶきとまったく同じ格子・同じシルエットで、色だけが湯気。
    ///
    /// 温泉街の背景は淡い灰青の空（0xDAE0E8）と雪の山なので、**青みを入れると氷柱に見える**
    /// （モック担当の指摘）。柱は白（`M`・左の照り）→ 灰（`W`）→ 灰（`G`）→ 暗い灰（`g`・右の陰）の
    /// 無彩色の濃淡で立て、右の陰（`g`）が背景との 3:1 を担う（竹の子の `a`・波しぶきの `N` と同じ約束）。
    static let steamColumnRows: [String] = [
        ".....KK.....",
        ".....KK.....",
        "....KMMK....",
        "....KMMK....",
        "....KMWK....",
        "...KMMWGK...",
        "...KMWWGK...",
        "...KMWWGK...",
        "..KMMWWGGK..",
        "..KMWWWGGK..",
        "..KMWWWGgK..",
        "..KMWWWGgK..",
        ".KMMWWWGGgK.",
        ".KMWWMWGGgK.",
        ".KMWWWWGGgK.",
        ".KMMWWWGGgK.",
        "KMMWWWWGGggK",
        "KMWWMWWGGggK",
        "KMWWWWWGGggK",
        "KMMWWWWGGggK",
        "KMWWMWWGGggK",
        "KMWWWWWGGggK",
        "KMMWWWWGGggK",
        "KMWWMWWGGggK",
        "KMWWWWWGGggK",
        "KMMWWWGGgggK",
        "KKKKKKKKKKKK",
    ]

    /// 地吹雪の雪柱（雪国の突き上げ・#2729）。湯柱とまったく同じ格子・同じシルエットで、色だけが雪と氷。
    ///
    /// 雪国の背景は白い丘と淡い空なので、柱は雪の白（`F`・左の照り）→ 氷の青白（`I`）→ 氷の青（`i`）→
    /// 深い氷の青（`J`・右の陰）の寒色の濃淡で立て、右の陰（`J`）が背景との 3:1 を担う（湯柱の `g` と同じ約束）。
    static let snowSpoutRows: [String] = [
        ".....KK.....",
        ".....KK.....",
        "....KFFK....",
        "....KFFK....",
        "....KFIK....",
        "...KFFIiK...",
        "...KFIIiK...",
        "...KFIIiK...",
        "..KFFIIiiK..",
        "..KFIIIiiK..",
        "..KFIIIiJK..",
        "..KFIIIiJK..",
        ".KFFIIIiiJK.",
        ".KFIIFIiiJK.",
        ".KFIIIIiiJK.",
        ".KFFIIIiiJK.",
        "KFFIIIIiiJJK",
        "KFIIFIIiiJJK",
        "KFIIIIIiiJJK",
        "KFFIIIIiiJJK",
        "KFIIFIIiiJJK",
        "KFIIIIIiiJJK",
        "KFFIIIIiiJJK",
        "KFIIFIIiiJJK",
        "KFIIIIIiiJJK",
        "KFFIIIiiJJJK",
        "KKKKKKKKKKKK",
    ]

    /// 予告（雪国）: 地面の雪が舞い上がる。塚・泡・湯だまりとまったく同じ格子で、色だけが雪。
    static let snowPuffRows: [String] = [
        ".......KKKK.......",
        ".....KKIIIIKK.....",
        "...KKIIFIIIFIKK...",
        "..KIIFIIIIFIIIIK..",
        ".KIIIFIIIIIIFIIIK.",
        "KIIFIIIIIIIIFIIIIK",
        "KKKKKKKKKKKKKKKKKK",
    ]

    /// マンホールの蒸気（東京の突き上げ・#2729）。湯柱とまったく同じ格子・同じシルエットで、色だけが灰白。
    ///
    /// 白（`M`・左の照り）→ 明るい灰（`c`）→ 中の灰（`p`）→ 暗い灰（`g`・右の陰）の 4 階調で、東京は背景が暗いので
    /// 白い照り（`M`）が 3:1 を担う。湯柱の生成り（`W`）より青みの灰にして、都心の地下から噴く蒸気に見せる。
    static let manholeSteamRows: [String] = [
        ".....KK.....",
        ".....KK.....",
        "....KMMK....",
        "....KMMK....",
        "....KMcK....",
        "...KMMcpK...",
        "...KMccpK...",
        "...KMccpK...",
        "..KMMccppK..",
        "..KMcccppK..",
        "..KMcccpgK..",
        "..KMcccpgK..",
        ".KMMcccppgK.",
        ".KMccMcppgK.",
        ".KMccccppgK.",
        ".KMMcccppgK.",
        "KMMccccppggK",
        "KMccMccppggK",
        "KMcccccppggK",
        "KMMccccppggK",
        "KMccMccppggK",
        "KMcccccppggK",
        "KMMccccppggK",
        "KMccMccppggK",
        "KMcccccppggK",
        "KMMcccppgggK",
        "KKKKKKKKKKKK",
    ]

    /// 予告（東京）: マンホールの蓋がカタカタと浮く。塚・泡とまったく同じ格子で、絵は鉄の蓋
    /// （暗い灰 `g` に石の灰 `G` の滑り止めの格子模様、縁取り `K`）。
    static let manholeLidRows: [String] = [
        ".....KKKKKKKK.....",
        "...KKggGGGGggKK...",
        ".KKgGgGgGgGgGgGKK.",
        "KgGgGgGgGgGgGgGgGK",
        "KggggggggggggggggK",
        "KKggggggggggggggKK",
        "KKKKKKKKKKKKKKKKKK",
    ]

    /// 予告（温泉街）: 湯だまりにぶくぶくと泡が立つ。塚・泡とまったく同じ格子で、色だけが湯気。
    static let steamBubbleRows: [String] = [
        ".......KKKK.......",
        ".....KKWWWWKK.....",
        "...KKWWMWWWMWKK...",
        "..KWWMWWWWMWWWWK..",
        ".KWWWMWWWWWWMWWWK.",
        "KWWMWWWWWWWWMWWWWK",
        "KKKKKKKKKKKKKKKKKK",
    ]

    /// 予告（里山）: 土が盛り上がる。地面に置く**低くて横に広い**塚（18×7 ドット）。
    ///
    /// 横に広げてあるのは読ませたい予告だから——当たり判定（1 タイル = 12 ドット）の
    /// `shootCueVisualScale` 倍（= 18 ドット）の幅で貼るので、**1 ドットの大きさは本体の
    /// 竹の子と同じ**（`RunnerPixelArtTests.shootsFitTheTallHitBox` が固定）。
    /// 高さは 7 ドット = 本体の 1/4 弱で、伸びてくる竹の子の根元だけを隠す。
    static let soilMoundRows: [String] = [
        ".......KKKK.......",
        ".....KKSSSSKK.....",
        "...KKSSsSSSsSKK...",
        "..KSSsSSSSsSSSSK..",
        ".KSSSsSSSSSSsSSSK.",
        "KSSsSSSSSSSSsSSSSK",
        "KKKKKKKKKKKKKKKKKK",
    ]

    /// 予告（港町）: 岸壁の縁に泡が立つ。塚とまったく同じ格子で、色だけが泡。
    static let foamRows: [String] = [
        ".......KKKK.......",
        ".....KKCCCCKK.....",
        "...KKCCMCCCMCKK...",
        "..KCCMCCCCMCCCCK..",
        ".KCCCMCCCCCCMCCCK.",
        "KCCMCCCCCCCCMCCCCK",
        "KKKKKKKKKKKKKKKKKK",
    ]

    /// 予告（塚・泡）を当たり判定の幅の何倍で描くか（`RunnerScene.addShoot`）。
    ///
    /// **格子の幅がこの倍率そのもの**（18 ドット / 本体 12 ドット = 1.5）なので、この倍率で
    /// 貼ると 1 ドットの大きさが本体と揃う。倍率を変えるなら格子の幅も一緒に変える。
    static let shootCueVisualScale: Double = 1.5

    // MARK: 宝くじ（毎面のゴール・#1092）

    /// ゴールに浮いている宝くじ（21×13 ドット）。旗を置き換える目印（会長決裁 2026-09-18）。
    ///
    /// おじさんが追いかけている当たり券そのものなので、**紙の券面**として読める形にする:
    /// 上段に金の帯（`Y`）と赤い刷り（`P`）、下段は生成りの紙（`M`）に赤い罫線、右寄りの
    /// 縦 1 列だけクリーム（`T`）で切り取り線の耳を出す。文字は書かない——この大きさ
    /// （幅 7 単位 ≒ 走者の自転車 1 台ぶん）では読めず、`RunnerAccessibility` が
    /// 言葉のほうを担うため。
    ///
    /// 格子は絵にぴったり（透明な余白の行・列が無い）。シーン側は `anchorPoint = (0.5, 0.5)` で
    /// **絵の中心**を走者の高さに合わせる（たこ焼きの底合わせとは違う——浮いている物なので）。
    static let lotteryTicketRows: [String] = [
        "KKKKKKKKKKKKKKKKKKKKK",
        "KYYYYYYYYYYYYYYYYYYYK",
        "KYYYYPPPPPPPPPPPYYYYK",
        "KMMMMMMMMMMMMMMMMMMMK",
        "KMPPPMMPPPMMPPPMMMTMK",
        "KMMMMMMMMMMMMMMMMMTMK",
        "KMPPPPPPPPPPPPPMMMTMK",
        "KMMMMMMMMMMMMMMMMMTMK",
        "KMPPPMMMPPPMMMPPPMTMK",
        "KMMMMMMMMMMMMMMMMMTMK",
        "KTTTTTTTTTTTTTTTTTTTK",
        "KTTTTTTTTTTTTTTTTTTTK",
        "KKKKKKKKKKKKKKKKKKKKK",
    ]

    static func lotteryTicket() -> PixelSprite {
        PixelSprite(rows: lotteryTicketRows, palette: palette)
    }
}
