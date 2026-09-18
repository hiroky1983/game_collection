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
    static let panelWidth = 120
    static let panelHeight = 68
    /// 土台の地面（道・川面・海面）の厚み。走者の足元はここに乗る。
    static let groundHeight = 12
    /// 走者・部品を置く床の y（この行から下が地面）。
    static var groundY: Int { panelHeight - groundHeight }

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
                .overlaying(lotteryDrum().scaled(2), x: 62, y: panelHeight - 40)
                .overlaying(bust(.smile), x: 8, y: bustY)
        case .introJoy:
            // 当たった宝くじを掲げて大喜び。
            return backdrop(.morning)
                .overlaying(RunnerPixelArt.lotteryTicket().scaled(2), x: 66, y: 12)
                .overlaying(bust(.cheer), x: 8, y: bustY)
        case .introBlownAway:
            // 風に飛ばされる。宝くじは右上の空へ。
            return backdrop(.morning)
                .overlaying(windLines().scaled(2), x: 54, y: 16)
                .overlaying(RunnerPixelArt.lotteryTicket(), x: 94, y: 3)
                .overlaying(bust(.frown), x: 8, y: bustY)
        case .introChase:
            // ママチャリで追いかける。以降のゲーム画面と同じ「右へ走る」向き。
            return backdrop(.morning)
                .overlaying(OjisanPixel.rider(.ride0), x: 14, y: groundY - 37)
                .overlaying(RunnerPixelArt.lotteryTicket(), x: 94, y: 8)

        case .morningReach:  return reachPanel(.morning)
        case .morningCrow:
            // カラスが咥えて飛んでいく。宝くじはくちばしの先（左）に重ねる。
            return backdrop(.morning)
                .overlaying(crow().scaled(2), x: 58, y: 0)
                // くちばしの先（カラスは左へ飛ぶ）。
                .overlaying(RunnerPixelArt.lotteryTicket(), x: 40, y: 12)
                .overlaying(bust(.gaze), x: 6, y: bustY)

        case .eveningDrop:
            // カラスが落とす。宝くじはカラスの真下、まだ空の途中。
            return backdrop(.evening)
                .overlaying(crow().scaled(2), x: 58, y: 0)
                .overlaying(RunnerPixelArt.lotteryTicket(), x: 72, y: 34)
                .overlaying(bust(.cheer), x: 6, y: bustY)
        case .eveningRiver:
            // 川に落ちて流されていく。地面を川面に差し替え、宝くじを水面に浮かべる。
            return backdrop(.evening, ground: RunnerWorld.SceneryPalette.riverWater)
                .overlaying(waterGlints(RunnerWorld.SceneryPalette.riverGlint), x: 0, y: groundY + 3)
                .overlaying(RunnerPixelArt.lotteryTicket(), x: 82, y: groundY - 5)
                .overlaying(bust(.gaze), x: 6, y: bustY)

        case .nightReach:    return reachPanel(.night)
        case .nightTruck:
            // 配達トラックの荷台に貼り付いて走り去る。**おじさんは出さない**
            // ——貼り付いているのは宝くじのほうなので、トラックを大きく見せる。
            return backdrop(.night)
                .overlaying(deliveryTruck().scaled(2), x: 16, y: groundY - 32)
                .overlaying(RunnerPixelArt.lotteryTicket(), x: 46, y: groundY - 40)

        case .satoyamaReach: return reachPanel(.satoyama)
        case .satoyamaDitch:
            // 用水路に落ちて海のほうへ。地面を用水路の水に差し替える。
            return backdrop(.satoyama, ground: RunnerWorld.DressingPalette.ditchWater)
                .overlaying(waterGlints(RunnerWorld.DressingPalette.waterGlint), x: 0, y: groundY + 3)
                .overlaying(RunnerPixelArt.lotteryTicket(), x: 84, y: groundY - 5)
                .overlaying(bust(.gaze), x: 6, y: bustY)

        case .harborReach:   return reachPanel(.harbor)
        case .harborShip:
            // 出航する貨物船の甲板に落ちる。ここだけは船を大きく見せて「行ってしまった」を出す。
            return backdrop(.harbor, ground: RunnerWorld.SceneryPalette.seaWater)
                .overlaying(waterGlints(RunnerWorld.SceneryPalette.seaGlint), x: 0, y: groundY + 4)
                .overlaying(cargoShip().scaled(2), x: 4, y: groundY - 32)
                // 甲板（コンテナの上）に落ちたところ。空へ浮かせない。
                .overlaying(RunnerPixelArt.lotteryTicket(), x: 40, y: groundY - 28)
        case .harborWatch:
            // 岸壁で見送る。船は水平線の向こうへ（等倍のまま右に置く）。
            return backdrop(.harbor, ground: RunnerWorld.SceneryPalette.seaWater)
                .overlaying(waterGlints(RunnerWorld.SceneryPalette.seaGlint), x: 0, y: groundY + 4)
                .overlaying(cargoShip(), x: 62, y: groundY - 17)
                .overlaying(bust(.gaze), x: 6, y: bustY)
        case .harborToBeContinued:
            // 「つづく」。文字は台詞側に出すので、絵は水平線と遠ざかる船だけにする。
            return backdrop(.harbor, ground: RunnerWorld.SceneryPalette.seaWater)
                .overlaying(waterGlints(RunnerWorld.SceneryPalette.seaGlint), x: 0, y: groundY + 4)
                .overlaying(cargoShip(), x: 58, y: groundY - 15)
        }
    }

    /// 顔を出すコマの置き方（バストアップ）。
    ///
    /// 正面顔（`OjisanPixel.face`）は**顔だけ**なので、3 倍にして地面に置くと首から下が無い
    /// 「浮いた丸い頭」に見える。ここで首と肩（黄色いポロシャツ）を継ぎ足し、下端をコマの
    /// 下端に接地させて胸から上の絵にする。**足すのはこの話の中だけ**——顔そのものは
    /// ハブのアイコン・リザルトと同じ `OjisanPixel` のまま（`Core` の定義は変えない）。
    static func bust(_ face: OjisanPixel.Face) -> PixelSprite {
        let head = OjisanPixel.face(face).scaled(3)
        let body = PixelSprite(rows: shoulderRows, palette: OjisanPixel.palette)
        // 肩は顎に少し重ねる（隙間を空けると首が切れて見える）。
        return PixelSprite.blank(width: head.width, height: bustHeight)
            .overlaying(head, x: 0, y: 0)
            .overlaying(body, x: 0, y: head.height - 6)
    }

    /// バストアップの高さ（顔 45 + 肩 14 − 重ね 6）。
    static let bustHeight = OjisanPixel.faceDotSize.height * 3 + 14 - 6

    /// バストアップの上端（下端がコマの下端にちょうど接する位置）。
    static var bustY: Int { panelHeight - bustHeight }

    /// 首と肩（48×14）。顔を 3 倍にしたときの幅に合わせてある。色は `OjisanPixel.palette`
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
            .overlaying(OjisanPixel.rider(.jump), x: 26, y: groundY - 40)
            // 伸ばした手のすぐ先に置く（届きそうで届かない距離）。
            .overlaying(RunnerPixelArt.lotteryTicket(), x: 70, y: groundY - 44)
    }

    // MARK: 土台

    /// 世界の空・丘・道で作る土台。`ground` を渡すと道のかわりにその色（川面・海面）で塗る。
    static func backdrop(_ world: RunnerWorld, ground: UInt32? = nil) -> PixelSprite {
        let p = world.palette
        var out = PixelSprite.solid(width: panelWidth, height: panelHeight, color: p.sky)
        // 遠景の丘（奥・手前）を 2 段。地面の上に薄く重ねるだけで、面の形は作らない。
        out = out.overlaying(
            PixelSprite.solid(width: panelWidth, height: 8, color: p.hillFar),
            x: 0, y: groundY - 14
        )
        out = out.overlaying(
            PixelSprite.solid(width: panelWidth, height: 7, color: p.hillNear),
            x: 0, y: groundY - 7
        )
        out = out.overlaying(
            PixelSprite.solid(width: panelWidth, height: groundHeight, color: ground ?? world.road.asphalt),
            x: 0, y: groundY
        )
        if ground == nil {
            // 路面の白線。破線 1 段だけ入れて「道」だと読めるようにする。
            out = out.overlaying(roadLine(world.road.line), x: 0, y: groundY + 5)
        }
        return out
    }

    /// 路面の破線（画面の幅いっぱい・4 ドットおき）。
    private static func roadLine(_ color: UInt32) -> PixelSprite {
        let row = String((0..<panelWidth).map { $0 % 8 < 4 ? "#" : "." })
        return PixelSprite(rows: [row], palette: ["#": color])
    }

    /// 水面の照り（細い破線を 2 段）。川・用水路・海で共通。
    private static func waterGlints(_ color: UInt32) -> PixelSprite {
        let a = String((0..<panelWidth).map { $0 % 14 < 5 ? "#" : "." })
        let gap = String(repeating: ".", count: panelWidth)
        let b = String((0..<panelWidth).map { ($0 + 7) % 12 < 4 ? "#" : "." })
        return PixelSprite(rows: [a, gap, b], palette: ["#": color])
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
    /// 16 コマを起動時にまとめて作ると 1 枚 120×68 でも無視できない量になるので、
    /// `faceImages` のような一括生成にはしない（1 場面で使うのは 2〜4 枚）。
    @MainActor private static var cache: [Panel: CGImage] = [:]

    /// 場面の 1 コマ。装飾（`Image(decorative:)`）なので VoiceOver は読まない
    /// ——読み上げるのは台詞のほう（`RunnerStoryView`）。
    @MainActor static func image(_ panel: Panel) -> Image {
        if let cg = cache[panel] {
            return Image(decorative: cg, scale: 1).resizable().interpolation(.none)
        }
        guard let cg = sprite(panel).cgImage(scale: 2) else { return Image(systemName: "bicycle") }
        cache[panel] = cg
        return Image(decorative: cg, scale: 1).resizable().interpolation(.none)
    }
}
