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
        "M": 0xFAF6EC,
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
    ]

    /// 縁取り（焦げ茶寄りの黒）。全世界の縁取り（`RunnerWorld.outline`・0x0E1420〜0x241A14）と同じ
    /// 濃さで、朝のパステルの丘・壁、夕方の手前の丘（0x6E5A96・いちばん厳しい）の上でも輪郭が立つ
    /// （`WorldTests` が 3:1 を固定。朝の値 0x241A14 は夕方の丘に 2.9 で届かないので一段暗い）。
    static let outline: UInt32 = 0x1A120E

    /// たこ焼きの生地の主色（きつね色）。岩のグレー・地面の茶・鳥の緑のどれとも系統が違う食べ物の色。
    static let takoyakiDough: UInt32 = 0xE8A860

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
        case .dog: return dog(frame, colors: world.creatures)
        case .cat: return cat(frame, colors: world.creatures)
        }
    }

    /// イノシシの枠の絵（世界の着せ替えでイノシシかフォークリフト）。
    static func charger(_ frame: WalkFrame, world: RunnerWorld) -> PixelSprite {
        switch world.dressing.boar {
        case .boar:     return boar(frame, colors: world.creatures)
        case .forklift: return forklift(frame, colors: world.creatures)
        }
    }

    /// 犬の枠の格子（寸法を測る用。`RunnerScene.addDog`）。
    static func walkerRows(world: RunnerWorld) -> [String] {
        switch world.dressing.dog {
        case .dog: return dogWalk0Rows
        case .cat: return catWalk0Rows
        }
    }

    /// イノシシの枠の格子（寸法を測る用。`RunnerScene.addBoar`）。
    static func chargerRows(world: RunnerWorld) -> [String] {
        switch world.dressing.boar {
        case .boar:     return boarWalk0Rows
        case .forklift: return forkliftDrive0Rows
        }
    }

    /// イノシシの枠の土煙を立てる列（`boarRearFootX` / `forkliftRearWheelX`）。
    static func chargerRearFootX(world: RunnerWorld) -> Double {
        switch world.dressing.boar {
        case .boar:     return boarRearFootX
        case .forklift: return forkliftRearWheelX
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

    /// 切り株（`RunnerWorld.Dressing.Block.stump`）。
    static func stump() -> PixelSprite { PixelSprite(rows: stumpRows, palette: palette) }

    /// ロープの束（`RunnerWorld.Dressing.Block.ropeCoil`）。
    static func ropeCoil() -> PixelSprite { PixelSprite(rows: ropeCoilRows, palette: palette) }

    /// ドラム缶（`RunnerWorld.Dressing.Block.drum`）。
    static func drum() -> PixelSprite { PixelSprite(rows: drumRows, palette: palette) }

    // MARK: 突き上げ（`RunnerHazardKind.shoot`・#1010）

    /// 伸び切った突き上げ（世界の着せ替えで竹の子か波しぶき）。
    static func shoot(world: RunnerWorld) -> PixelSprite {
        switch world.dressing.shoot {
        case .bambooShoot: return PixelSprite(rows: bambooShootRows, palette: palette)
        case .seaSpray:    return PixelSprite(rows: seaSprayRows, palette: palette)
        }
    }

    /// 突き上げの予告（土が盛り上がる／泡が立つ）。
    static func shootCue(world: RunnerWorld) -> PixelSprite {
        switch world.dressing.shoot {
        case .bambooShoot: return PixelSprite(rows: soilMoundRows, palette: palette)
        case .seaSpray:    return PixelSprite(rows: foamRows, palette: palette)
        }
    }

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
}
