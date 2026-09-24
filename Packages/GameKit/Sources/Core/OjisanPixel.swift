import CoreGraphics
import Foundation
import SwiftUI

// MARK: - おじさん（ドット絵）

/// 「あそびば」のマスコット、チャリンコおじさんのドット絵。スーパーファミコン級の 2D に統一する
/// 決裁（2026-09-15・会長）に従い、走者のコマと正面顔をここ（Core）に置く。おじさんシリーズの
/// 2 本目以降でも同じ顔にするため、ゲーム側にドットを書かない。
///
/// 設定: 大阪に住む 65 歳。薄い頭に白髪まじりの側頭部、太い眉、鼻の下のヒゲ（メガネは無し・会長
/// 指示 2026-09-15）、笑顔、黄色のポロシャツ、紺のズボン、前かご付きの赤いママチャリ。
/// **思い立ったらママチャリでどこへでも行く、ちょっと変わったおじさん。**
///
/// ストーリー（会長決裁 2026-09-17〜18・#1092。**おじさんシリーズの他のゲームも同じ設定を使う**）:
/// 商店街の福引きで当たった**宝くじ**が風に飛ばされ、どこまでも追いかけていく。あと一歩で掴み
/// かけるたび、カラス・川・トラック・用水路・貨物船に邪魔されて次の土地へ飛んでいく。最後は
/// （将来の版で）地獄の閻魔大王から取り返すが、**億だと思ったら 300 円**。
/// なぜママチャリで海を渡れるのかは**一切説明しない**（そこがギャグ）。
///
/// 走者のコマは 40×37 ドット（右向き）。1 ドット = 整数 pt で描く（`PixelSprite.cgImage(scale:)`）。
/// 正面顔は 32×30 ドット（ハブのカード・リザルト。#1349 で 16×15 から解像度を上げ、さらに会長指示で SD（ちびキャラ）寄りに
/// デフォルメを強めた: 頭を丸く大きく、目を大きく、鼻と口を小さく、額を広く。配色・表情の意味は同じ）。
/// 粗い版（`faceLowRes`）は元の写実寄りの絵柄のまま。
public enum OjisanPixel {
    /// 共通パレット（SFC 風に彩度をやや落とし、暗い輪郭で締める）。
    public static let palette: [Character: UInt32] = [
        "K": 0x2B2634,
        "S": 0xF2C8A0,
        "s": 0xD69E76,
        "W": 0xFAF6EC,
        "Y": 0xF0C030,
        "y": 0xC4901C,
        "B": 0x3E4E80,
        "b": 0x28345C,
        "H": 0x9696A2,
        "h": 0x626270,
        "E": 0x221E28,
        "R": 0xD43C2C,
        "r": 0x96241C,
        "T": 0x34343C,
        "t": 0x787882,
        "C": 0xE87860,
        "N": 0xAA763E,
        "G": 0x60586E,
        "M": 0x96282C,
        "Q": 0xFAF6EC,
        "X": 0x3C2828,
    ]

    /// 走者のコマ。
    public enum RiderFrame: String, CaseIterable, Sendable {
        /// 漕ぐ（右ペダルが前）。
        case ride0
        /// 漕ぐ（左ペダルが前）。
        case ride1
        /// 跳ぶ（前輪が上がり、体が少し反る）。
        case jump
        /// コケる（自転車が横倒し、前へ投げ出される）。
        case tumble
        /// 目を回す（座り込み）。
        case dizzy
    }

    /// 正面顔の表情。
    public enum Face: String, CaseIterable, Sendable {
        case smile, cheer, frown
        /// ぽかんと見送る（#1092 の世界の締め。宝くじに逃げられた直後・岸壁で船を見送る場面）。
        /// 眉は八の字、口は小さく開いたまま。しかめ面（`frown`）と違って怒っても悔しがってもいない。
        case gaze
    }

    public static func rider(_ frame: RiderFrame) -> PixelSprite {
        switch frame {
        case .ride0: return PixelSprite(rows: ride0Rows, palette: palette)
        case .ride1: return PixelSprite(rows: ride1Rows, palette: palette)
        case .jump: return PixelSprite(rows: jumpRows, palette: palette)
        case .tumble: return PixelSprite(rows: tumbleRows, palette: palette)
        case .dizzy: return PixelSprite(rows: dizzyRows, palette: palette)
        }
    }

    public static func face(_ face: Face) -> PixelSprite {
        switch face {
        case .smile: return PixelSprite(rows: smileRows, palette: palette)
        case .cheer: return PixelSprite(rows: cheerRows, palette: palette)
        case .frown: return PixelSprite(rows: frownRows, palette: palette)
        case .gaze: return PixelSprite(rows: gazeRows, palette: palette)
        }
    }

    /// 正面顔の粗い版（16×15）。世界の締め（`RunnerStoryArt` の胸像）が 3 倍にして荒い格子の場面に重ねるので、
    /// 高解像度化（#1349）の対象外としてそのまま残す。ハブ・リザルトは `face(_:)` を使う。
    public static func faceLowRes(_ face: Face) -> PixelSprite {
        switch face {
        case .smile: return PixelSprite(rows: smileLowRows, palette: palette)
        case .cheer: return PixelSprite(rows: cheerLowRows, palette: palette)
        case .frown: return PixelSprite(rows: frownLowRows, palette: palette)
        case .gaze: return PixelSprite(rows: gazeLowRows, palette: palette)
        }
    }
    /// 粗い版の正面顔のドット数（`faceLowRes` の大きさ）。
    public static let faceLowResDotSize: (width: Int, height: Int) = (width: 16, height: 15)

    // MARK: ハブ・リザルト用の正面顔

    /// アイコン用キャンバスの一辺（ドット）。32×30 の顔を 48×48 の中央に置き、周りの余白で
    /// 他ゲームの SF Symbol（枠の 5〜6 割の大きさ）と見た目の比率を揃える。
    public static let iconCanvasDots = 48

    /// 正面顔（笑顔）のビットマップ。起動後 1 回だけ作る（#700 の受け入れ条件: 毎表示でビットマップ化しない）。
    /// 1 ドット = 2px で持ち（旧 16×15 の 1 ドット = 4px と同じ 96px 四方）、表示側で枠の大きさに合わせて縮尺する（`mascotIcon`）。
    public static let mascotFaceImage: CGImage? =
        face(.smile).padded(width: iconCanvasDots, height: iconCanvasDots).cgImage(scale: 2)

    /// ハブのカード・おすすめ・設定などで `GameModule.icon` として出す正面顔。
    /// 呼び出し側は SF Symbol と同じく `.font(...)` で大きさを決めているが、ビットマップには効かないので
    /// `resizable` で枠（44pt・36pt・32pt、iPad では `layout.scaled` で拡大）に追従させる。
    /// `interpolation(.none)` でにじませない（枠 44pt で 1 ドット ≒ 1.8pt。整数倍でなくてもドットの縁は立つ）。
    public static var mascotIcon: Image {
        guard let cg = mascotFaceImage else { return Image(systemName: "bicycle") }
        return Image(decorative: cg, scale: 1).resizable().interpolation(.none)
    }

    // MARK: リザルト・スタート画面用の正面顔（#702）

    /// 高解像度化前（16×15）に対する正面顔の細かさ（縦横とも何倍か）。表示の大きさは旧来の
    /// 「16 ドット × 倍率 pt」のままにしたいので、`faceDotSize` を `faceResolution` で割って枠を切る。
    public static let faceResolution = 2

    /// 正面顔のドット数（幅 32 × 高さ 30）。表示側はこの比率で枠を切る（`faceImage` の doc）。
    public static let faceDotSize: (width: Int, height: Int) = (width: 16 * faceResolution, height: 15 * faceResolution)

    /// 表情ごとのビットマップ。`mascotFaceImage` と同じく起動後 1 回だけ作る（`static let` は初回参照時に
    /// 1 度だけ評価される）。1 ドット = 4px（128×120px）で持ち、
    /// 表示側で縮尺する。
    public static let faceImages: [Face: CGImage] = {
        var out: [Face: CGImage] = [:]
        for face in Face.allCases { out[face] = Self.face(face).cgImage(scale: 4) }
        return out
    }()

    /// リザルト（クリア・ミス）とスタート画面に出す正面顔（#702）。
    ///
    /// 装飾（`Image(decorative:)`）なので VoiceOver は読まない。`resizable` + `interpolation(.none)` で
    /// にじませない。呼び出し側は `faceDotSize` ÷ `faceResolution` × 整数倍の `frame` を切る（例: 4 倍 = 64×60pt。
    /// 1 ドット = 2pt）。比率を崩すと 1 ドットが縦横で違う大きさになるので、`frame` の幅と高さは必ず同じ倍率で決める。
    public static func faceImage(_ face: Face) -> Image {
        guard let cg = faceImages[face] else { return Image(systemName: "bicycle") }
        return Image(decorative: cg, scale: 1).resizable().interpolation(.none)
    }

    // MARK: 格子（手で直すときは行の長さを揃えること。PixelArtTests が検査する）

    // ride0 40x37
    static let ride0Rows: [String] = [
        "........................................",
        ".....................KKKKKK.............",
        "...................KKHHSSSSKK...........",
        "..................KHHhSSSSSSSK..........",
        "..................KHhSSSSSSSSK..........",
        ".................KHhSShhSSShhSK.........",
        ".................KHhSSQESSSQESK.........",
        ".................KhSSSSSSSSSsSK.........",
        "..................KsSSSSSSSCssK.........",
        "..................KsSShhHhhhhhK.........",
        "...................KshhMMMMMhK..........",
        "...................KKsQQQQQsK...........",
        ".................KKKKKKssKK.............",
        "................KYYYYQQKKK..............",
        "................KYYYYYQYYYK.............",
        "...............KyYYYYYYYYYYK............",
        "...............KyYYYYYYYyYYK............",
        "...............KyyYYYYYYYyYK............",
        "...............KyyYYYYYYYyyYSS..........",
        "................KyyyYYYYyyKySKKKK.......",
        "................KKyyyyyyyKK..K..KKKKKKK.",
        "................KKKBBBBB....K...NNNNNNK.",
        "...............K...BBBBB........NNNNNNK.",
        "............RRRRRbbRRRBBBRRR....NNNNNNK.",
        ".......KKKrK.....bbR..BBB..RKKKKNNNNNNK.",
        ".....KKTTTTrKK...bbR..BBBKKTRTTTKKKKKK..",
        "....KKTtttttrKK.bb.R..BBBKTttRttTKK.....",
        "....KTtt.t.ttrK.bb.R.bb.KTtt.tRttTK.....",
        "...KTttt...tttrKbb.R.bbKTttt...RttTK....",
        "...KTt..KKK..rrKKKrr.bbKTt..KKK..tTK....",
        "...KTtt.KKK.ttTK.....bbKTtt.KKK.ttTK....",
        "...KTt..KKK..tTK....KbbKTt..KKK..tTK....",
        "...KTttt...tttTK....KKKKTttt...tttTK....",
        "....KTtt.t.ttTK.........KTtt.t.ttTK.....",
        "....KKTtttttTKK.........KKTtttttTKK.....",
        ".....KKTTTTTKK...........KKTTTTTKK......",
        ".......KKKKK...............KKKKK........",
    ]
    // ride1 40x37
    static let ride1Rows: [String] = [
        "........................................",
        ".....................KKKKKK.............",
        "...................KKHHSSSSKK...........",
        "..................KHHhSSSSSSSK..........",
        "..................KHhSSSSSSSSK..........",
        ".................KHhSShhSSShhSK.........",
        ".................KHhSSQESSSQESK.........",
        ".................KhSSSSSSSSSsSK.........",
        "..................KsSSSSSSSCssK.........",
        "..................KsSShhHhhhhhK.........",
        "...................KshhMMMMMhK..........",
        "...................KKsQQQQQsK...........",
        ".................KKKKKKssKK.............",
        "................KYYYYQQKKK..............",
        "................KYYYYYQYYYK.............",
        "...............KyYYYYYYYYYYK............",
        "...............KyYYYYYYYyYYK............",
        "...............KyyYYYYYYYyYK............",
        "...............KyyYYYYYYYyyYSS..........",
        "................KyyyYYYYyyKySKKKK.......",
        "................KKyyyyyyyKK..K..KKKKKKK.",
        "................KKKBBBBB....K...NNNNNNK.",
        "...............K...BBBBB........NNNNNNK.",
        "............RRRRRbbRRBBBRRRR....NNNNNNK.",
        ".......KKKrK.....bbR.BBB...RKKKKNNNNNNK.",
        ".....KKTTTTrKK...bbR.BBB.KKTRTTTKKKKKK..",
        "....KKTtttttrKK..bbRBB..KKTttRttTKK.....",
        "....KTtt.t.ttrK..bbRBB..KTtt.tRttTK.....",
        "...KTttt...tttrK.bbRBB.KTttt...RttTK....",
        "...KTt..KKK..rrrrbbKKKKKTt..KKK..tTK....",
        "...KTtt.KKK.ttTK.bb....KTtt.KKK.ttTK....",
        "...KTt..KKK..tTK.bb....KTt..KKK..tTK....",
        "...KTttt...tttTKKKKK...KTttt...tttTK....",
        "....KTtt.t.ttTK.........KTtt.t.ttTK.....",
        "....KKTtttttTKK.........KKTtttttTKK.....",
        ".....KKTTTTTKK...........KKTTTTTKK......",
        ".......KKKKK...............KKKKK........",
    ]
    // jump 40x37
    static let jumpRows: [String] = [
        "...................KKKKKK...............",
        ".................KKHHSSSSKK.............",
        "................KHHhSSSSSSSK............",
        "................KHhSSSSSSSSK............",
        "...............KHhSShhSSShhSK...........",
        "...............KHhSSQESSSQESK...........",
        "...............KhSSSSSSSSSsSK...........",
        "................KsSSSSSSSCssK...........",
        "................KsSShhHhhhhhK...........",
        ".................KshhMMMMMhK............",
        ".................KKsQQQQQsK.............",
        "................KKKKKssKK...............",
        "...............KYYYYQKKKK...............",
        "...............KYYYYYQYYYK..............",
        "..............KyYYYYYYYYYYK.............",
        "..............KyYYYYYYYyYYK.............",
        "..............KyyYYYYYYYyYKSSKKK........",
        "..............KyyYYYYYYYyyYSK..KKKKKKK..",
        "...............KyyyYYYYyyKyK...NNNNNNK..",
        "...............KKyyyyyyyKK.....NNNNNNK..",
        "..................BBBBB........NNNNNNK..",
        "..................BBBBBRRRRRKKKNNNNNNK..",
        "...............KKKBBBBB...KKRTTTKKKKK...",
        "..............KRbbR..BBB.KKTtRtttTKK....",
        "...........RRRR.bb...BBB.KTtt.R.ttTK....",
        "......KKKrK.....bbR..BBBKTttt...tttTK...",
        "....KKTTTTrKK...bbR..BBBKTt..KKK..tTK...",
        "...KKTtttttrKK.bb.R..bb.KTtt.KKK.ttTK...",
        "...KTtt.t.ttrK.bb.R..bb.KTt..KKK..tTK...",
        "..KTttt...tttrKbb.R..bb.KTttt...tttTK...",
        "..KTt..KKK..rrKKKKr.KKKK.KTtt.t.ttTK....",
        "..KTtt.KKK.ttTK..........KKTtttttTKK....",
        "..KTt..KKK..tTK...........KKTTTTTKK.....",
        "..KTttt...tttTK.............KKKKK.......",
        "...KTtt.t.ttTK..........................",
        "...KKTtttttTKK..........................",
        "....KKTTTTTKK...........................",
    ]
    // tumble 40x37
    static let tumbleRows: [String] = [
        "........................................",
        "........................................",
        "........................................",
        "........................................",
        "........................................",
        ".........................KKKKKK.........",
        ".......................KKHHSSSSKK.......",
        "......................KHHhSSSSSSSK......",
        "......................KHhSSSSSSSSK......",
        "............KK.......KHhSShhSSShhSK.....",
        "...........KYYKK.....KHhSSQESSSQESK.....",
        ".........BBBYYYYKK...KhSSSSSSSSSsSK.....",
        ".....KBBBBBBYYYYYYKK..KsSSSSSSSCssK.....",
        ".....KBBBbbbYYYYYYYYKKKsSShhHhhhhhK.....",
        ".....Kbbb..KyyYYYYYYYY.KshhMMMMMhK......",
        "...........KKKyyYYYYYY.KKsQQQQQsK.......",
        "..............KKyyYYYYYy.KKssKK.........",
        "................KKyyYY.Yy..KKK..........",
        "..................KKyy..Yy..............",
        "....................KK...Yy.............",
        "..........................Yy............",
        "...........................Yy...........",
        "............................Yy..........",
        ".............................SS.........",
        "..............KKKK............S.........",
        "......KKKKK....K........KKKKKKKKKK......",
        "....KKTTTTTRRRRRRRRRRRRRTTTNNNNNNN......",
        "...KKTtttttTrrrrrrrrrrrTtttNNNNNNN......",
        "...KTtt.t.ttTK.......KTtt.tNNNNNNN......",
        "..KTttt...tttTK.....KTttt...tttTK.......",
        "..KTt..KKK..tTK.....KTt..KKK..tTK.......",
        "..KTtt.KKK.ttTK.....KTtt.KKK.ttTK.......",
        "..KTt..KKK..tTK.....KTt..KKK..tTK.......",
        "..KTttt...tttTK.....KTttt...tttTK.......",
        "...KTtt.t.ttTK.......KTtt.t.ttTK........",
        "...KKTtttttTKK.......KKTtttttTKK........",
        "....KKTTTTTKK.........KKTTTTTKK.........",
    ]
    // dizzy 40x37
    static let dizzyRows: [String] = [
        "........................................",
        "........................................",
        "................................YY......",
        "...................KKKKKK......Y..Y.....",
        ".................KKHHSSSSKK.......Y.....",
        "................KHHhSSSSSSSK....YY......",
        "................KHhSSSSSSSSK............",
        "...............KHhSShhSSShhSK...........",
        "...............KHhSSXXSSSXXSK...........",
        "...............KhSSSSSSSSSsSK...........",
        "................KsSSSSSSSCssK...........",
        "................KsSShhHhhhhhK...........",
        ".................KshhQMQMQhK............",
        ".................KKsSSSSSsK.............",
        "...................KKssKK...............",
        ".................KKKKKKKK...............",
        "................KYYYYQQYYK..............",
        "................KYYYYYQYYYK.............",
        "...............KyYYYYYYYYYYK............",
        "...............KyYYYYYYYyYYK............",
        "...............KyyYYYYYYYyYK............",
        "...............KyyYYYYYYYyyYS...........",
        "................KyyyYYYYyyKyS...........",
        "................KKyyyyyyyKK.............",
        "...............BBBBBBB..................",
        ".....KKKKK.....BBBBBBBBBBBBB............",
        "...KKTTTTTRRRRRBBBBBBBBBBBBBKK..........",
        "..KKTtttttTrrrrBBBBBBBBBBBBBTKK.........",
        "..KTtt.t.ttTK..bbbbbbbBBBBBBtTK.........",
        ".KTttt...tttTK.....KTtbbbbbbttTK........",
        ".KTt..KKK..tTK.....KTtbbbbbKKKTK........",
        ".KTtt.KKK.ttTK.....KTtt.KKK.ttTK........",
        ".KTt..KKK..tTK.....KTt..KKK..tTK........",
        ".KTttt...tttTK.....KTttt...tttTK........",
        "..KTtt.t.ttTK.......KTtt.t.ttTK.........",
        "..KKTtttttTKK.......KKTtttttTKK.........",
        "...KKTTTTTKK.........KKTTTTTKK..........",
    ]
    // smile 16x15
    static let smileLowRows: [String] = [
        ".....KKKKKK.....",
        "...KKHHSSHHKK...",
        "..KHHhSSSShHHK..",
        "..KHhSSSSSShHK..",
        ".KHhShhSSSShhSHK",
        ".KHhSQESSSSQESHK",
        ".KhSSSSSsSSSSShK",
        ".KsSSCSSSSSSCSsK",
        ".KsSSShhHHhhSSsK",
        "..KsSShMMMMhSsK.",
        "..KKsSSQQQQSsKK.",
        "....KsSSSSSsK...",
        ".....KKssKKK....",
        ".......KKK......",
        "................",
    ]
    // smile 32x30（#1349・SD 寄りのデフォルメ）。頭を横幅いっぱいの丸い大きな輪郭にして首を無くし、額を広く取った
    // 「薄い頭」（頭頂は地肌だけ・左上に W のツヤ・側頭部に H/h の髪と W の白髪）。目は 6×5 の黒目に Q のハイライト、
    // 鼻は s の 2 段、頬は 5×3 の C、鼻の下のヒゲは h/H の 12〜14 幅、口は歯（Q）の見える笑い。
    // 左右対称に描き、頭頂のツヤだけ左に寄せている。以下の「N 行」は配列の添字（0 始まり）。
    static let smileRows: [String] = [
        "..........KKKKKKKKKKKK..........",
        ".......KKKSSSSSSSSSSSSKKK.......",
        ".....KKHHSSSSSSSSSSSSSSHHKK.....",
        "....KHWhSSSSSWWSSSSSSSSShWHK....",
        "...KHHhhSSSSWSSSSSSSSSSShhHHK...",
        "..KHHhhSSSSSSSSSSSSSSSSSShhHHK..",
        "..KWHhhSSSSSSSSSSSSSSSSSShhHWK..",
        ".KHHhhSSSSSSSSSSSSSSSSSSSShhHHK.",
        ".KHWhhSSSSSSSSSSSSSSSSSSSShhWHK.",
        "KHHhhSSSSSSSSSSSSSSSSSSSSSShhHHK",
        "KHHhhSSSSSSSSSSSSSSSSSSSSSShhHHK",
        "KHWhhSSShhhhhSSSSSShhhhhSSShhWHK",
        "KHHhhSShhhhhhSSSSSShhhhhhSShhHHK",
        "KHhhSSSSSSSSSSSSSSSSSSSSSSSShhHK",
        "KHhhSSSSQQEESSSSSSSSEEQQSSSShhHK",
        "KhhSSSSQQEEEESSSSSSEEEEQQSSSShhK",
        "KhhSSSSQEEEEESSSSSSEEEEEQSSSShhK",
        "KssSSSSEEEEEESSSSSSEEEEEESSSSssK",
        "KssSSSSSEEEESSSSSSSSEEEESSSSSssK",
        "KsSCCCCSSSSSSSSssSSSSSSSSCCCCSsK",
        "KsCCCCCSSSSSSSssssSSSSSSSCCCCCsK",
        "KsSCCCCSSShhhhHHHHhhhhSSSCCCCSsK",
        ".KssSSSSShhhhhHHHHhhhhhSSSSSssK.",
        ".KssSSSSSSSMSSSSSSSSMSSSSSSSssK.",
        "..KssSSSSSSMQQQQQQQQMSSSSSSssK..",
        "...KssSSSSSSMMMMMMMMSSSSSSssK...",
        "....KssSSSSSSSSSSSSSSSSSSssK....",
        "......KKKssSSSSSSSSSSssKKK......",
        ".........KKKKKKKKKKKKKK.........",
        "................................",
    ]
    // cheer 16x15
    static let cheerLowRows: [String] = [
        ".....KKKKKK.....",
        "...KKHHSSHHKK...",
        "..KHHhSSSShHHK..",
        "..KHhSSSSSShHK..",
        ".KHhShhSSSShhSHK",
        ".KHhSQESSSSQESHK",
        ".KhSSSSSsSSSSShK",
        ".KsSSCSSSSSSCSsK",
        ".KsSSShhHHhhSSsK",
        "..KsSShMMMMhSsK.",
        "..KKsMMMMMMMsKK.",
        "....KsQQQQQsK...",
        ".....KKssKKK....",
        ".......KKK......",
        "................",
    ]
    // cheer 32x30（#1349）。smile と同じ格子で、眉（11 行）を少し上げ、口（23〜27 行）を顎まで届く大口＋下の歯に差し替え。
    static let cheerRows: [String] = [
        "..........KKKKKKKKKKKK..........",
        ".......KKKSSSSSSSSSSSSKKK.......",
        ".....KKHHSSSSSSSSSSSSSSHHKK.....",
        "....KHWhSSSSSWWSSSSSSSSShWHK....",
        "...KHHhhSSSSWSSSSSSSSSSShhHHK...",
        "..KHHhhSSSSSSSSSSSSSSSSSShhHHK..",
        "..KWHhhSSSSSSSSSSSSSSSSSShhHWK..",
        ".KHHhhSSSSSSSSSSSSSSSSSSSShhHHK.",
        ".KHWhhSSSSSSSSSSSSSSSSSSSShhWHK.",
        "KHHhhSSSSSSSSSSSSSSSSSSSSSShhHHK",
        "KHHhhSSSSSSSSSSSSSSSSSSSSSShhHHK",
        "KHWhhSSSShhhhSSSSSShhhhSSSShhWHK",
        "KHHhhSShhhhhhSSSSSShhhhhhSShhHHK",
        "KHhhSSSSSSSSSSSSSSSSSSSSSSSShhHK",
        "KHhhSSSSQQEESSSSSSSSEEQQSSSShhHK",
        "KhhSSSSQQEEEESSSSSSEEEEQQSSSShhK",
        "KhhSSSSQEEEEESSSSSSEEEEEQSSSShhK",
        "KssSSSSEEEEEESSSSSSEEEEEESSSSssK",
        "KssSSSSSEEEESSSSSSSSEEEESSSSSssK",
        "KsSCCCCSSSSSSSSssSSSSSSSSCCCCSsK",
        "KsCCCCCSSSSSSSssssSSSSSSSCCCCCsK",
        "KsSCCCCSSShhhhHHHHhhhhSSSCCCCSsK",
        ".KssSSSSShhhhhHHHHhhhhhSSSSSssK.",
        ".KssSSSSSMMMMMMMMMMMMMMSSSSSssK.",
        "..KssSSSSMMMMMMMMMMMMMMSSSSssK..",
        "...KssSSSMQQQQQQQQQQQQMSSSssK...",
        "....KssSSSMMMMMMMMMMMMSSSssK....",
        "......KKKssSMMMMMMMMSssKKK......",
        ".........KKKKKKKKKKKKKK.........",
        "................................",
    ]
    // frown 16x15
    static let frownLowRows: [String] = [
        ".....KKKKKK.....",
        "...KKHHSSHHKK...",
        "..KHHhSSSShHHK..",
        "..KHhSSSSSShHK..",
        ".KHhSSShhShhSSHK",
        ".KHhSQESSSSQESHK",
        ".KhSSSSSsSSSSShK",
        ".KsSSCSSSSSSCSsK",
        ".KsSSShhHHhhSSsK",
        "..KsSShhhhhhSsK.",
        "..KKsSMMMMMSsKK.",
        "....KsSSSSSsK...",
        ".....KKssKKK....",
        ".......KKK......",
        "................",
    ]
    // frown 32x30（#1349）。smile と同じ格子で、眉（11〜13 行）を内側が下がる怒り眉に、口（24〜25 行）をヒゲの下のへの字に差し替え。
    static let frownRows: [String] = [
        "..........KKKKKKKKKKKK..........",
        ".......KKKSSSSSSSSSSSSKKK.......",
        ".....KKHHSSSSSSSSSSSSSSHHKK.....",
        "....KHWhSSSSSWWSSSSSSSSShWHK....",
        "...KHHhhSSSSWSSSSSSSSSSShhHHK...",
        "..KHHhhSSSSSSSSSSSSSSSSSShhHHK..",
        "..KWHhhSSSSSSSSSSSSSSSSSShhHWK..",
        ".KHHhhSSSSSSSSSSSSSSSSSSSShhHHK.",
        ".KHWhhSSSSSSSSSSSSSSSSSSSShhWHK.",
        "KHHhhSSSSSSSSSSSSSSSSSSSSSShhHHK",
        "KHHhhSSSSSSSSSSSSSSSSSSSSSShhHHK",
        "KHWhhSShhhhSSSSSSSSSShhhhSShhWHK",
        "KHHhhSSSShhhhhSSSShhhhhSSSShhHHK",
        "KHhhSSSSSSShhhSSSShhhSSSSSSShhHK",
        "KHhhSSSSQQEESSSSSSSSEEQQSSSShhHK",
        "KhhSSSSQQEEEESSSSSSEEEEQQSSSShhK",
        "KhhSSSSQEEEEESSSSSSEEEEEQSSSShhK",
        "KssSSSSEEEEEESSSSSSEEEEEESSSSssK",
        "KssSSSSSEEEESSSSSSSSEEEESSSSSssK",
        "KsSCCCCSSSSSSSSssSSSSSSSSCCCCSsK",
        "KsCCCCCSSSSSSSssssSSSSSSSCCCCCsK",
        "KsSCCCCSSShhhhHHHHhhhhSSSCCCCSsK",
        ".KssSSSSShhhhhHHHHhhhhhSSSSSssK.",
        ".KssSSSSSSSSSSSSSSSSSSSSSSSSssK.",
        "..KssSSSSSMMSSSSSSSSMMSSSSSssK..",
        "...KssSSSSSSMMMMMMMMSSSSSSssK...",
        "....KssSSSSSSSSSSSSSSSSSSssK....",
        "......KKKssSSSSSSSSSSssKKK......",
        ".........KKKKKKKKKKKKKK.........",
        "................................",
    ]
    // gaze 16x15（#1092）。眉（`h`）を内側へ寄せて八の字にし、口（`M`）は 2×2 で小さく開けたまま。
    // 頬（`C`）は笑顔と同じ位置に残す——血の気が引いた顔ではなく「呆けている」顔にしたいので。
    static let gazeLowRows: [String] = [
        ".....KKKKKK.....",
        "...KKHHSSHHKK...",
        "..KHHhSSSShHHK..",
        "..KHhSSSSSShHK..",
        ".KHhSShhSShhSSHK",
        ".KHhSQESSSSQESHK",
        ".KhSSSSSsSSSSShK",
        ".KsSSCSSSSSSCSsK",
        ".KsSSShhHHhhSSsK",
        "..KsSSShMMhSSsK.",
        "..KKsSShMMhSsKK.",
        "....KsSSSSSsK...",
        ".....KKssKKK....",
        ".......KKK......",
        "................",
    ]
    // gaze 32x30（#1349）。smile と同じ格子で、眉（11〜13 行）を八の字に、口（23〜25 行）を小さく開いた楕円（幅 4/6/4）に差し替え。頬はそのまま。
    static let gazeRows: [String] = [
        "..........KKKKKKKKKKKK..........",
        ".......KKKSSSSSSSSSSSSKKK.......",
        ".....KKHHSSSSSSSSSSSSSSHHKK.....",
        "....KHWhSSSSSWWSSSSSSSSShWHK....",
        "...KHHhhSSSSWSSSSSSSSSSShhHHK...",
        "..KHHhhSSSSSSSSSSSSSSSSSShhHHK..",
        "..KWHhhSSSSSSSSSSSSSSSSSShhHWK..",
        ".KHHhhSSSSSSSSSSSSSSSSSSSShhHHK.",
        ".KHWhhSSSSSSSSSSSSSSSSSSSShhWHK.",
        "KHHhhSSSSSSSSSSSSSSSSSSSSSShhHHK",
        "KHHhhSSSSSSSSSSSSSSSSSSSSSShhHHK",
        "KHWhhSSSSSShhhSSSShhhSSSSSShhWHK",
        "KHHhhSSShhhhhSSSSSShhhhhSSShhHHK",
        "KHhhSSShhhSSSSSSSSSSSShhhSSShhHK",
        "KHhhSSSSQQEESSSSSSSSEEQQSSSShhHK",
        "KhhSSSSQQEEEESSSSSSEEEEQQSSSShhK",
        "KhhSSSSQEEEEESSSSSSEEEEEQSSSShhK",
        "KssSSSSEEEEEESSSSSSEEEEEESSSSssK",
        "KssSSSSSEEEESSSSSSSSEEEESSSSSssK",
        "KsSCCCCSSSSSSSSssSSSSSSSSCCCCSsK",
        "KsCCCCCSSSSSSSssssSSSSSSSCCCCCsK",
        "KsSCCCCSSShhhhHHHHhhhhSSSCCCCSsK",
        ".KssSSSSShhhhhHHHHhhhhhSSSSSssK.",
        ".KssSSSSSSSSSSMMMMSSSSSSSSSSssK.",
        "..KssSSSSSSSSMMMMMMSSSSSSSSssK..",
        "...KssSSSSSSSSMMMMSSSSSSSSssK...",
        "....KssSSSSSSSSSSSSSSSSSSssK....",
        "......KKKssSSSSSSSSSSssKKK......",
        ".........KKKKKKKKKKKKKK.........",
        "................................",
    ]
}
