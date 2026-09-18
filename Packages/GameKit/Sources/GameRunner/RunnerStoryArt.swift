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
            // 朝の下町の商店街。ガラガラを右に据え、左のおじさんが回している。
            return backdrop(.morning)
                .overlaying(lotteryDrum(), x: 66, y: groundY - 20)
                .overlaying(OjisanPixel.face(.smile).scaled(2), x: 24, y: groundY - 30)
        case .introJoy:
            // 当たった宝くじを掲げて大喜び。顔を 3 倍にして、この話の主役が誰かを最初に見せる。
            return backdrop(.morning)
                .overlaying(OjisanPixel.face(.cheer).scaled(3), x: 20, y: groundY - 45)
                .overlaying(RunnerPixelArt.lotteryTicket().scaled(2), x: 72, y: 8)
        case .introBlownAway:
            // 風に飛ばされる。宝くじは右上の空へ、おじさんは追いかける前のしかめ面。
            return backdrop(.morning)
                .overlaying(OjisanPixel.face(.frown).scaled(2), x: 18, y: groundY - 30)
                .overlaying(RunnerPixelArt.lotteryTicket(), x: 88, y: 6)
                .overlaying(windLines(), x: 52, y: 14)
        case .introChase:
            // ママチャリで追いかける。以降のゲーム画面と同じ「右へ走る」向き。
            return backdrop(.morning)
                .overlaying(OjisanPixel.rider(.ride0), x: 20, y: groundY - 37)
                .overlaying(RunnerPixelArt.lotteryTicket(), x: 92, y: 10)

        case .morningReach:  return reachPanel(.morning)
        case .morningCrow:
            // カラスが咥えて飛んでいく。宝くじはくちばしの先に重ねる。
            return backdrop(.morning)
                .overlaying(crow(), x: 56, y: 6)
                .overlaying(RunnerPixelArt.lotteryTicket(), x: 36, y: 12)
                .overlaying(OjisanPixel.face(.gaze).scaled(2), x: 12, y: groundY - 30)

        case .eveningDrop:
            // カラスが落とす。宝くじはカラスの真下、まだ空の途中。
            return backdrop(.evening)
                .overlaying(crow(), x: 62, y: 4)
                .overlaying(RunnerPixelArt.lotteryTicket(), x: 60, y: 24)
                .overlaying(OjisanPixel.face(.cheer).scaled(2), x: 14, y: groundY - 30)
        case .eveningRiver:
            // 川に落ちて流されていく。地面を川面に差し替え、宝くじを水面に浮かべる。
            return backdrop(.evening, ground: RunnerWorld.SceneryPalette.riverWater)
                .overlaying(waterGlints(RunnerWorld.SceneryPalette.riverGlint), x: 0, y: groundY + 3)
                .overlaying(RunnerPixelArt.lotteryTicket(), x: 78, y: groundY - 4)
                .overlaying(OjisanPixel.face(.gaze).scaled(2), x: 16, y: groundY - 32)

        case .nightReach:    return reachPanel(.night)
        case .nightTruck:
            // 配達トラックの荷台に貼り付いて走り去る。宝くじは荷台の縁に。
            return backdrop(.night)
                .overlaying(deliveryTruck(), x: 52, y: groundY - 16)
                .overlaying(RunnerPixelArt.lotteryTicket(), x: 68, y: groundY - 22)
                .overlaying(OjisanPixel.face(.gaze).scaled(2), x: 12, y: groundY - 30)

        case .satoyamaReach: return reachPanel(.satoyama)
        case .satoyamaDitch:
            // 用水路に落ちて海のほうへ。地面を用水路の水に差し替える。
            return backdrop(.satoyama, ground: RunnerWorld.DressingPalette.ditchWater)
                .overlaying(waterGlints(RunnerWorld.DressingPalette.waterGlint), x: 0, y: groundY + 3)
                .overlaying(RunnerPixelArt.lotteryTicket(), x: 80, y: groundY - 4)
                .overlaying(OjisanPixel.face(.gaze).scaled(2), x: 16, y: groundY - 32)

        case .harborReach:   return reachPanel(.harbor)
        case .harborShip:
            // 出航する貨物船の甲板に落ちる。海の上に船、宝くじは甲板の上。
            return backdrop(.harbor, ground: RunnerWorld.SceneryPalette.seaWater)
                .overlaying(waterGlints(RunnerWorld.SceneryPalette.seaGlint), x: 0, y: groundY + 4)
                .overlaying(cargoShip(), x: 44, y: groundY - 15)
                .overlaying(RunnerPixelArt.lotteryTicket(), x: 62, y: groundY - 22)
        case .harborWatch:
            // 岸壁で見送る。船は水平線の向こうへ小さく（等倍のまま右端に置く）。
            return backdrop(.harbor, ground: RunnerWorld.SceneryPalette.seaWater)
                .overlaying(waterGlints(RunnerWorld.SceneryPalette.seaGlint), x: 0, y: groundY + 4)
                .overlaying(cargoShip(), x: 76, y: groundY - 14)
                .overlaying(OjisanPixel.face(.gaze).scaled(3), x: 8, y: groundY - 45)
        case .harborToBeContinued:
            // 「つづく」。文字は台詞側に出すので、絵は水平線と小さくなった船だけにする。
            return backdrop(.harbor, ground: RunnerWorld.SceneryPalette.seaWater)
                .overlaying(waterGlints(RunnerWorld.SceneryPalette.seaGlint), x: 0, y: groundY + 4)
                .overlaying(cargoShip(), x: 92, y: groundY - 13)
        }
    }

    /// 「あと一歩で掴みかける」コマ。世界ごとに背景だけ変えて、構図は 5 回とも同じにする
    /// （毎回同じ形で外されるのがこの話の型なので、絵でもそれを繰り返す）。
    private static func reachPanel(_ world: RunnerWorld) -> PixelSprite {
        backdrop(world)
            .overlaying(OjisanPixel.rider(.jump), x: 30, y: groundY - 42)
            .overlaying(RunnerPixelArt.lotteryTicket(), x: 76, y: groundY - 40)
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
        "G": 0x18181F, "B": 0x23232B, "E": 0x7A7A88,     // カラス（里山の鳥の 3 階調）
        "y": 0x4A4A52,                                   // カラスのくちばし
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
        "..KRRRRRRRRRRRRRRRRK.KK.",
        "..KRRRRWWWWWWRRRRRRK.KX.",
        "..KRRRRWWWWWWRRRRRRKKKX.",
        "..KRRRRRRRRRRRRRRRRK.KX.",
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
        "..........KKKK..............",
        ".........KGGGGKK............",
        "........KGGGGGGGKK..........",
        ".......KGGGGGGGGGGKK........",
        "..KKKKKGGGGGGGGGGGGGKKK.....",
        ".KBBBKGGGGGGGGGGGGGGGGKK....",
        "KBBEBKGGGGGGGGGGGGGGGGGK....",
        "yyKBBBKGGGGGGGGGGGGGGGGK....",
        "..KBBBBKGGGGGGGGGGGGGGK.....",
        "...KBBBBBKKGGGGGGGGGKK......",
        "....KBBBBBBBKKKKKKKK........",
        ".....KBBBBBBBBBK............",
        "......KKBBBBBKK.............",
        "........KKKKK...............",
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
