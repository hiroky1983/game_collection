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
    ]

    /// 縁取り（焦げ茶寄りの黒）。3 世界の縁取り（`RunnerWorld.outline`・0x0E1420〜0x241A14）と同じ
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
    /// たこ焼きのように 1 つの色で 3 世界を通すことはできない——イノシシらしい暗い茶は夜の路面
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
}
