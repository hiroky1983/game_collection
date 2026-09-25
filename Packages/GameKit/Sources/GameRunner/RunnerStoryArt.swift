import Core
import CoreGraphics
import Foundation
import SwiftUI

// MARK: - ストーリーの場面の絵（#1092）

/// 始まりと世界の締めに出す 1 コマの絵。
///
/// **画像ファイルは足さない**（会長決裁 2026-09-17〜18 の受け入れ条件 B）。1 枚は
/// 「世界の空と道で作った土台（`backdrop`）に、ドット絵の部品を重ねた 1 つの `PixelSprite`」で、
/// 重ねるのは `PixelSprite.overlaying` が引き受ける。**`ZStack` に部品を並べない**
/// ——iOS では部品ごとのレイアウトがずれて図案が潰れる（チェス駒 #462・神経衰弱 #601 の教訓を、
/// `Canvas` ではなく「1 枚のドット絵に焼き込む」形で踏襲する）。焼き込んであるので
/// 全画素をテストで固定でき、実機とシミュレータで違う絵になる余地も無い。
///
/// 使い回すもの（同 B「既存の絵は使い回す」）: 走者のコマと正面顔（`OjisanPixel`）・
/// ゴールの宝くじ（`RunnerPixelArt.lotteryTicket`）・世界の配色（`RunnerWorld`）。
/// 新しく描き起こすのは、この話にしか出てこない**福引きのガラガラ・カラス・配達トラック・貨物船**の 4 つだけ。
enum RunnerStoryArt {
    /// 1 コマの格子（ドット）。16:9 より少し縦長にして、走者（40×37）と台詞の両方が収まる比にする。
    ///
    /// 格子の細かさは**正面顔（`OjisanPixel.face`・32×30）に合わせてある**（#1349）。`overlaying` は
    /// ドットの大きさが揃っていることが前提で、`scaled(_:)` は整数倍しか無いので、顔が 16×15 から
    /// 32×30 になった分だけコマの格子も倍（120×68 → 240×136）にした。顔以外の部品は元の粗さのまま
    /// `fit(_:times:)` で格子を合わせて置くので、**構図も画面に出る大きさも従来と同じ**で、顔だけが細かくなる。
    static let panelWidth = 240
    static let panelHeight = 136
    /// 土台の地面（道・川面・海面）の厚み。走者の足元はここに乗る。
    static let groundHeight = 24
    /// 走者・部品を置く床の y（この行から下が地面）。
    static var groundY: Int { panelHeight - groundHeight }

    /// 顔以外の部品（走者・宝くじ・ここで描き起こした 4 つ）を 1 コマの格子に合わせる。
    ///
    /// これらは 1 ドット = コマの 2 ドットの粗さで描いてあるので、そのまま重ねると半分の大きさになる。
    /// `times` はその部品だけさらに大きく見せたいときの倍率（格子を倍にする前の `.scaled(2)` に当たる）。
    private static func fit(_ art: PixelSprite, times: Int = 1) -> PixelSprite { art.scaled(2 * times) }

    // MARK: 1 コマの種類

    /// 場面のコマ。`RunnerStory` が並べ、`RunnerStoryView` がこの順に出す。
    enum Panel: String, CaseIterable, Sendable {
        /// 商店街の福引き。ガラガラを回して宝くじが当たる。
        case introDraw
        /// 大喜び（正面の `cheer` と宝くじ）。
        case introJoy
        /// 風に飛ばされる（宝くじが右上へ・おじさんは `frown`）。
        case introBlownAway
        /// ママチャリで追いかける（`ride0`）。
        case introChase

        /// 朝の下町: あと一歩で掴みかける（`jump` と宝くじ）。
        case morningReach
        /// 朝の下町: カラスが咥えて飛んでいく。
        case morningCrow

        /// 夕方の川沿い: カラスが落とす。
        case eveningDrop
        /// 夕方の川沿い: 川に落ちて流されていく。
        case eveningRiver

        /// 夜の繁華街: 路上の宝くじを拾いかける。
        case nightReach
        /// 夜の繁華街: 配達トラックの荷台に貼り付いて田舎へ。
        case nightTruck

        /// 里山: あぜ道で掴みかける。
        case satoyamaReach
        /// 里山: 用水路に落ちて海のほうへ流されていく。
        case satoyamaDitch

        /// 港町: 岸壁で掴みかける。
        case harborReach
        /// 港町: 出航する貨物船の甲板に落ちる。
        case harborShip
        /// 港町: 岸壁で見送る（`gaze`）。
        case harborWatch
        /// 港町: 「つづく」。
        case harborToBeContinued
    }

    // MARK: 1 コマを組む

    static func sprite(_ panel: Panel) -> PixelSprite {
        switch panel {
        case .introDraw:
            // 朝の下町の商店街。右にガラガラ、左でおじさんが回している。
            return backdrop(.morning)
                .overlaying(fit(lotteryDrum(), times: 2), x: 124, y: panelHeight - 80)
                .overlaying(bust(.smile), x: 16, y: bustY)
        case .introJoy:
            // 当たった宝くじを掲げて大喜び。
            return backdrop(.morning)
                .overlaying(fit(RunnerPixelArt.lotteryTicket(), times: 2), x: 132, y: 24)
                .overlaying(bust(.cheer), x: 16, y: bustY)
        case .introBlownAway:
            // 風に飛ばされる。宝くじは右上の空へ。
            return backdrop(.morning)
                .overlaying(fit(windLines(), times: 2), x: 108, y: 32)
                .overlaying(fit(RunnerPixelArt.lotteryTicket()), x: 188, y: 6)
                .overlaying(bust(.frown), x: 16, y: bustY)
        case .introChase:
            // ママチャリで追いかける。以降のゲーム画面と同じ「右へ走る」向き。
            return backdrop(.morning)
                .overlaying(fit(OjisanPixel.rider(.ride0)), x: 28, y: groundY - 74)
                .overlaying(fit(RunnerPixelArt.lotteryTicket()), x: 188, y: 16)

        case .morningReach:  return reachPanel(.morning)
        case .morningCrow:
            // カラスが咥えて飛んでいく。宝くじはくちばしの先（左）に重ねる。
            return backdrop(.morning)
                .overlaying(fit(crow(), times: 2), x: 116, y: 0)
                // くちばしの先（カラスは左へ飛ぶ）。
                .overlaying(fit(RunnerPixelArt.lotteryTicket()), x: 80, y: 24)
                .overlaying(bust(.gaze), x: 12, y: bustY)

        case .eveningDrop:
            // カラスが落とす。宝くじはカラスの真下、まだ空の途中。
            return backdrop(.evening)
                .overlaying(fit(crow(), times: 2), x: 116, y: 0)
                .overlaying(fit(RunnerPixelArt.lotteryTicket()), x: 144, y: 68)
                .overlaying(bust(.cheer), x: 12, y: bustY)
        case .eveningRiver:
            // 川に落ちて流されていく。地面を川面に差し替え、宝くじを水面に浮かべる。
            return backdrop(.evening, ground: RunnerWorld.SceneryPalette.riverWater)
                .overlaying(waterGlints(RunnerWorld.SceneryPalette.riverGlint), x: 0, y: groundY + 6)
                .overlaying(fit(RunnerPixelArt.lotteryTicket()), x: 164, y: groundY - 10)
                .overlaying(bust(.gaze), x: 12, y: bustY)

        case .nightReach:    return reachPanel(.night)
        case .nightTruck:
            // 配達トラックの荷台に貼り付いて走り去る。**おじさんは出さない**
            // ——貼り付いているのは宝くじのほうなので、トラックを大きく見せる。
            return backdrop(.night)
                .overlaying(fit(deliveryTruck(), times: 2), x: 32, y: groundY - 64)
                .overlaying(fit(RunnerPixelArt.lotteryTicket()), x: 92, y: groundY - 80)

        case .satoyamaReach: return reachPanel(.satoyama)
        case .satoyamaDitch:
            // 用水路に落ちて海のほうへ。地面を用水路の水に差し替える。
            return backdrop(.satoyama, ground: RunnerWorld.DressingPalette.ditchWater)
                .overlaying(waterGlints(RunnerWorld.DressingPalette.waterGlint), x: 0, y: groundY + 6)
                .overlaying(fit(RunnerPixelArt.lotteryTicket()), x: 168, y: groundY - 10)
                .overlaying(bust(.gaze), x: 12, y: bustY)

        case .harborReach:   return reachPanel(.harbor)
        case .harborShip:
            // 出航する貨物船の甲板に落ちる。ここだけは船を大きく見せて「行ってしまった」を出す。
            return backdrop(.harbor, ground: RunnerWorld.SceneryPalette.seaWater)
                .overlaying(waterGlints(RunnerWorld.SceneryPalette.seaGlint), x: 0, y: groundY + 8)
                .overlaying(fit(cargoShip(), times: 2), x: 8, y: groundY - 64)
                // 甲板（コンテナの上）に落ちたところ。空へ浮かせない。
                .overlaying(fit(RunnerPixelArt.lotteryTicket()), x: 80, y: groundY - 56)
        case .harborWatch:
            // 岸壁で見送る。船は水平線の向こうへ（等倍のまま右に置く）。
            return backdrop(.harbor, ground: RunnerWorld.SceneryPalette.seaWater)
                .overlaying(waterGlints(RunnerWorld.SceneryPalette.seaGlint), x: 0, y: groundY + 8)
                .overlaying(fit(cargoShip()), x: 124, y: groundY - 34)
                .overlaying(bust(.gaze), x: 12, y: bustY)
        case .harborToBeContinued:
            // 「つづく」。文字は台詞側に出すので、絵は水平線と遠ざかる船だけにする。
            return backdrop(.harbor, ground: RunnerWorld.SceneryPalette.seaWater)
                .overlaying(waterGlints(RunnerWorld.SceneryPalette.seaGlint), x: 0, y: groundY + 8)
                .overlaying(fit(cargoShip()), x: 116, y: groundY - 30)
        }
    }

    /// 顔を出すコマの置き方（バストアップ）。
    ///
    /// 正面顔（`OjisanPixel.face`・32×30）は**顔だけ**なので、3 倍にして地面に置くと首から下が無い
    /// 「浮いた丸い頭」に見える。ここで首と肩（黄色いポロシャツ）を継ぎ足し、下端をコマの
    /// 下端に接地させて胸から上の絵にする。**足すのはこの話の中だけ**——顔そのものは
    /// `OjisanPixel` の定義のまま（`Core` の定義は変えない）。
    ///
    /// #1349 で顔が 16×15 → 32×30 になったが、コマの格子も倍にしたので **3 倍のまま**でよい
    /// （96×90 ドット = 旧 48×45 と画面に出る大きさは同じ）。肩は旧来の粗さで描いてあるので
    /// `fit(_:)` で格子を合わせる。
    static func bust(_ face: OjisanPixel.Face) -> PixelSprite {
        let head = OjisanPixel.face(face).scaled(3)
        let body = fit(PixelSprite(rows: shoulderRows, palette: OjisanPixel.palette))
        // 肩は顎に少し重ねる（隙間を空けると首が切れて見える）。
        return PixelSprite.blank(width: head.width, height: bustHeight)
            .overlaying(head, x: 0, y: 0)
            .overlaying(body, x: 0, y: head.height - 12)
    }

    /// バストアップの高さ（顔 90 + 肩 28 − 重ね 12）。
    static let bustHeight = OjisanPixel.faceDotSize.height * 3 + 28 - 12

    /// バストアップの上端（下端がコマの下端にちょうど接する位置）。
    static var bustY: Int { panelHeight - bustHeight }

    /// 首と肩（48×14。`fit(_:)` で 96×28 にして使う）。顔を 3 倍にしたときの幅に合わせてある。色は `OjisanPixel.palette`
    /// （`S` = 肌・`Y` = 黄色いポロシャツ・`K` = 輪郭）をそのまま使う。
    static let shoulderRows: [String] = [
        "....................KKKKKKKK....................",
        "....................KSSSSSSK....................",
        "....................KSSSSSSK....................",
        "..............KKKKKKKSSSSSSKKKKKKK..............",
        "..........KKKKYYYYYYYYYYYYYYYYYYYYKKKK..........",
        "........KKKYYYYYYYYYYYYYYYYYYYYYYYYYYKKK........",
        "......KKYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYKK......",
        ".....KKYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYKK.....",
        ".....KYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYK.....",
        ".....KYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYK.....",
        ".....KYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYK.....",
        ".....KYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYK.....",
        ".....KYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYK.....",
        ".....KYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYK.....",
    ]

    /// 「あと一歩で掴みかける」コマ。世界ごとに背景だけ変えて、構図は 5 回とも同じにする
    /// （毎回同じ形で外されるのがこの話の型なので、絵でもそれを繰り返す）。
    private static func reachPanel(_ world: RunnerWorld) -> PixelSprite {
        backdrop(world)
            .overlaying(fit(OjisanPixel.rider(.jump)), x: 52, y: groundY - 80)
            // 伸ばした手のすぐ先に置く（届きそうで届かない距離）。
            .overlaying(fit(RunnerPixelArt.lotteryTicket()), x: 140, y: groundY - 88)
    }

    // MARK: 土台

    /// 世界の空・丘・道で作る土台。`ground` を渡すと道のかわりにその色（川面・海面）で塗る。
    static func backdrop(_ world: RunnerWorld, ground: UInt32? = nil) -> PixelSprite {
        let p = world.palette
        var out = PixelSprite.solid(width: panelWidth, height: panelHeight, color: p.sky)
        // 遠景の丘（奥・手前）を 2 段。地面の上に薄く重ねるだけで、面の形は作らない。
        out = out.overlaying(
            PixelSprite.solid(width: panelWidth, height: 16, color: p.hillFar),
            x: 0, y: groundY - 28
        )
        out = out.overlaying(
            PixelSprite.solid(width: panelWidth, height: 14, color: p.hillNear),
            x: 0, y: groundY - 14
        )
        out = out.overlaying(
            PixelSprite.solid(width: panelWidth, height: groundHeight, color: ground ?? world.road.asphalt),
            x: 0, y: groundY
        )
        if ground == nil {
            // 路面の白線。破線 1 段だけ入れて「道」だと読めるようにする。
            out = out.overlaying(roadLine(world.road.line), x: 0, y: groundY + 10)
        }
        return out
    }

    /// 路面の破線（画面の幅いっぱい・4 ドットおき）。他の部品と同じ粗さで作って `fit(_:)` で格子を合わせる
    /// （コマの格子で直接描くと線が半分の太さになり、破線が細かく散る）。
    private static func roadLine(_ color: UInt32) -> PixelSprite {
        let row = String((0..<(panelWidth / 2)).map { $0 % 8 < 4 ? "#" : "." })
        return fit(PixelSprite(rows: [row], palette: ["#": color]))
    }

    /// 水面の照り（細い破線を 2 段）。川・用水路・海で共通。破線は `roadLine` と同じ粗さで作る。
    private static func waterGlints(_ color: UInt32) -> PixelSprite {
        let w = panelWidth / 2
        let a = String((0..<w).map { $0 % 14 < 5 ? "#" : "." })
        let gap = String(repeating: ".", count: w)
        let b = String((0..<w).map { ($0 + 7) % 12 < 4 ? "#" : "." })
        return fit(PixelSprite(rows: [a, gap, b], palette: ["#": color]))
    }

    /// 風の線（飛ばされるコマ）。
    private static func windLines() -> PixelSprite {
        PixelSprite(
            rows: [
                "##########....",
                "....##########",
                "..##########..",
            ],
            palette: ["#": 0xFFFFFF]
        )
    }

    // MARK: 描き起こした部品

    /// 部品の共通パレット。色は既存の定義から引く（新しい色を増やさない）。
    static let palette: [Character: UInt32] = [
        "K": 0x1A120E,                                   // 輪郭（`RunnerPixelArt.outline`）
        "R": 0xD43C2C, "r": 0x96241C,                    // 赤（ママチャリと同じ）
        "W": 0xFAF6EC,                                   // 生成りの白
        "Y": 0xE4B23C,                                   // 金（宝くじの帯）
        "N": 0xC89A5E, "X": 0x5A3A1A,                    // 木（木箱の板・継ぎ目）
        // カラス。里山の鳥（`RunnerWorld.satoyama.creatures`）は黒に近い 3 階調だが、それは
        // 淡い背景の前を**横切る**前提の色で、1 コマの主役に据えると翼・胴・輪郭が同じ黒の塊に
        // なって鳥だと読めない。**階調だけ開いて**、翼を一段明るく・羽の筋をさらに明るくする
        // （「カラス = 黒い鳥」は保つ）。
        // 手前の翼 `G` → 羽の筋 `w` → 胴 `B` → 奥の翼 `b` の 4 階調。奥の翼をいちばん暗くすると
        // 翼が 2 枚に見え、1 枚の三角（＝飛行機のシルエット）にならない。
        "G": 0x44445A, "w": 0x6E6E88, "B": 0x2A2A38, "b": 0x16161E, "E": 0xF4F4F4,
        "y": 0x8A8A96,                                   // カラスのくちばし
        "V": 0x60A040, "O": 0xE08030,                    // 野菜（緑・橙）
        "C": 0x3E4E80, "T": 0x34343C, "t": 0x787882,     // 運転席（紺）・タイヤ
        "H": 0xA3AFBC, "D": 0xD0A094, "Q": 0xD8D3C8,     // 船体・喫水線・船橋
        "U": 0xD4A08E, "u": 0x9FB9CC, "F": 0xC9A79A,     // コンテナ 2 色・煙突
    ]

    /// 福引きのガラガラ（24×20）。八角のドラムに小窓、下は木の台、右にハンドル。
    static func lotteryDrum() -> PixelSprite { PixelSprite(rows: lotteryDrumRows, palette: palette) }

    static let lotteryDrumRows: [String] = [
        "........................",
        "......KKKKKKKKKK........",
        "....KKRRRRRRRRRRKK......",
        "...KRRRRRRRRRRRRRRK.....",
        "..KRRRRRRRRRRRRRRRRK....",
        "..KRrRRRRRRRRRRRRrRK.KK.",
        "..KRrRRWWWWRRRRRRrRK.KX.",
        "..KRrRRWWWWRRRRRRrRKKKX.",
        "..KRrRRRRRRRRRRRRrRK.KX.",
        "...KRRRRRRRRRRRRRRK..KX.",
        "....KKRRRRRRRRRRKK.KKX..",
        "......KKKKKKKKKK........",
        ".......KNNNNNNK.........",
        ".......KNNNNNNK.........",
        "....KKKKNNNNNNKKKK......",
        "...KNNNNNNNNNNNNNNK.....",
        "...KNXXXXXXXXXXXXNK.....",
        "...KNNNNNNNNNNNNNNK.....",
        "...KKKKKKKKKKKKKKKK.....",
        "........................",
    ]

    /// カラス（28×16・左向き）。宝くじはくちばしの先に別途重ねる。
    static func crow() -> PixelSprite { PixelSprite(rows: crowRows, palette: palette) }

    static let crowRows: [String] = [
        "............................",
        "....KK..............KK......",
        "...KbbK............KGGK.....",
        "..KbbbbK..........KGGGGK....",
        "..KbbbbbK........KGGwwGK....",
        "...KbbbbbK......KGwwwGK.....",
        "....KbbbbbKKKKKKGGGGGK......",
        ".....KbbbbBBBBBBBBGGGK......",
        "...KKBBBBBBBBBBBBBBBBKKK....",
        ".yyKBEBBBBBBBBBBBBBBBBGGK...",
        ".yyKBBBBBBBBBBBBBBBBBBGGGK..",
        "...KKBBBBBBBBBBBBBBBKGGGK...",
        ".....KKKKKKKKKKKKKKKKKKK....",
        "............................",
        "............................",
        "............................",
    ]

    /// 配達トラック（44×16・左向き）。荷台に野菜、運転席は左。
    static func deliveryTruck() -> PixelSprite { PixelSprite(rows: deliveryTruckRows, palette: palette) }

    static let deliveryTruckRows: [String] = [
        "............................................",
        "...........KKKKKKKKKKKKKKKKKKKKKK...........",
        "...........KNNNNNNNNNNNNNNNNNNNNK...........",
        "...........KNVVNOONVVNOONVVNOONNK...........",
        "...........KNNNNNNNNNNNNNNNNNNNNK...........",
        "....KKKKKKKKNNNNNNNNNNNNNNNNNNNNK...........",
        "...KCCCCCCCKNNNNNNNNNNNNNNNNNNNNK...........",
        "..KCWWWWCCCKNNNNNNNNNNNNNNNNNNNNK...........",
        "..KCWWWWCCCKNNNNNNNNNNNNNNNNNNNNK...........",
        "..KCCCCCCCCKNNNNNNNNNNNNNNNNNNNNK...........",
        "..KCCCCCCCCKNNNNNNNNNNNNNNNNNNNNK...........",
        "..KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK...........",
        "...KTTTTK..........KTTTTK...................",
        "...KTtTTK..........KTtTTK...................",
        "...KTTTTK..........KTTTTK...................",
        "....KKKK............KKKK....................",
    ]

    /// 貨物船（56×17・左向き）。甲板にコンテナ、煙突は右。
    static func cargoShip() -> PixelSprite { PixelSprite(rows: cargoShipRows, palette: palette) }

    static let cargoShipRows: [String] = [
        "........................................................",
        "..............................KK........................",
        "..............................KFK.......................",
        ".........................KKKKKKFKKK.....................",
        ".........................KQQQQQQQQK.....................",
        ".........................KQWWQWWQQK.....................",
        "...............KKKKKKKKKKKQQQQQQQQK.....................",
        "...............KUUUKuuuKUUUKQQQQQQK.....................",
        "...............KUUUKuuuKUUUKQQQQQQK.....................",
        "...............KKKKKKKKKKKKKKKKKKKK.....................",
        "...KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK....................",
        "..KHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHK...................",
        ".KHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHK...................",
        "KHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHK...................",
        "KDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDK...................",
        ".KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK....................",
        "........................................................",
    ]

    // MARK: 表示用のビットマップ

    /// 表示したコマだけをビットマップにして覚えておく。
    ///
    /// 16 コマを起動時にまとめて作ると 1 枚 240×136 でも無視できない量になるので、
    /// `faceImages` のような一括生成にはしない（1 場面で使うのは 2〜4 枚）。
    @MainActor private static var cache: [Panel: CGImage] = [:]

    /// 場面の 1 コマ。装飾（`Image(decorative:)`）なので VoiceOver は読まない
    /// ——読み上げるのは台詞のほう（`RunnerStoryView`）。
    @MainActor static func image(_ panel: Panel) -> Image {
        if let cg = cache[panel] {
            return Image(decorative: cg, scale: 1).resizable().interpolation(.none)
        }
        // 1 ドット = 1px。#1349 で格子を倍にしたぶん、ここは 2 倍から 1 倍に落とす
        // ——出来上がりの画素数（240×136px）は従来と同じで、顔だけが細かくなる。
        // 顔のいちばん細かい部分でも 3px 角あるので、これ以上増やしても情報は増えない。
        guard let cg = sprite(panel).cgImage(scale: 1) else { return Image(systemName: "bicycle") }
        cache[panel] = cg
        return Image(decorative: cg, scale: 1).resizable().interpolation(.none)
    }
}
