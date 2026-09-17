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
///
/// 走者のコマは 40×37 ドット（右向き）。1 ドット = 整数 pt で描く（`PixelSprite.cgImage(scale:)`）。
/// 正面顔は 32×30 ドット（ハブのカード・リザルト・LP）。走者の頭（8 ドット幅）より細かく、
/// 大きく表示しても目・眉・ヒゲが 1 ドットに潰れない（会長指摘 2026-09-17）。
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
        // 正面顔 32×30 用の中間色（2026-09-17）。走者のコマは使っていない。
        "L": 0xFBE0BE,
        "p": 0xE8B88E,
        "d": 0xB57A52,
        "I": 0xC8C8D2,
        "m": 0x5E1418,
        "a": 0x6CB8E8,
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
        }
    }

    // MARK: ハブ・リザルト用の正面顔

    /// アイコン用キャンバスの一辺（ドット）。32×30 の顔を 48×48 の中央に置き、周りの余白で
    /// 他ゲームの SF Symbol（枠の 5〜6 割の大きさ）と見た目の比率を揃える（顔 : 枠 = 2 : 3）。
    public static let iconCanvasDots = 48

    /// 正面顔（笑顔）のビットマップ。起動後 1 回だけ作る（#700 の受け入れ条件: 毎表示でビットマップ化しない）。
    /// 1 ドット = 2px で持ち（96×96px。16×15 時代の 4px と同じ寸法・同じメモリ）、表示側で枠の大きさに
    /// 合わせて縮尺する（`mascotIcon`）。
    public static let mascotFaceImage: CGImage? =
        face(.smile).padded(width: iconCanvasDots, height: iconCanvasDots).cgImage(scale: 2)

    /// ハブのカード・おすすめ・設定などで `GameModule.icon` として出す正面顔。
    /// 呼び出し側は SF Symbol と同じく `.font(...)` で大きさを決めているが、ビットマップには効かないので
    /// `resizable` で枠（44pt・36pt・32pt、iPad では `layout.scaled` で拡大）に追従させる。
    /// `interpolation(.none)` でにじませない（枠 44pt で 1 ドット ≒ 0.9pt。整数倍でなくてもドットの縁は立つ）。
    public static var mascotIcon: Image {
        guard let cg = mascotFaceImage else { return Image(systemName: "bicycle") }
        return Image(decorative: cg, scale: 1).resizable().interpolation(.none)
    }

    // MARK: リザルト・スタート画面用の正面顔（#702）

    /// 正面顔のドット数（幅 32 × 高さ 30）。表示側はこの比率で枠を切る（`faceImage` の doc）。
    public static let faceDotSize: (width: Int, height: Int) = (width: 32, height: 30)

    /// 3 表情のビットマップ。`mascotFaceImage` と同じく起動後 1 回だけ作る（`static let` は初回参照時に
    /// 1 度だけ評価される）。1 ドット = 2px で持ち（64×60px。16×15 時代の 4px と同じ寸法・同じメモリ）、
    /// 表示側で pt に縮尺する。
    public static let faceImages: [Face: CGImage] = {
        var out: [Face: CGImage] = [:]
        for face in Face.allCases { out[face] = Self.face(face).cgImage(scale: 2) }
        return out
    }()

    /// リザルト（クリア・ミス）とスタート画面に出す正面顔（#702）。
    ///
    /// 装飾（`Image(decorative:)`）なので VoiceOver は読まない。`resizable` + `interpolation(.none)` で
    /// にじませない。呼び出し側は `faceDotSize` × 倍率の `frame` を切る（例: 2 倍 = 64×60pt、1.5 倍 = 48×45pt）。
    /// 倍率は 1 ドットが Retina の整数ピクセルになる値（1・1.5・2）に限る。比率を崩すと 1 ドットが縦横で
    /// 違う大きさになるので、`frame` の幅と高さは必ず同じ倍率で決める。
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
    // smile 32x30
    static let smileRows: [String] = [
        "...........KKKKKKKKKK...........",
        ".........KKpppppppppsKK.........",
        "........KppSSSLLLLSSSpsK........",
        ".......KIHhSLLLLLLLLSSHIK.......",
        "......KIHhSSLLLLLLLLLShHIK......",
        ".....KIHHhSSSLLLLLLLSShHHIK.....",
        "....KIIHhSSSSSLLLLLSSSSHHIIK....",
        "....KIHHhSSSSSSLLLSSSSShHHIK....",
        "...KHIhSSShhhhSSSShhhhSSShHHK...",
        "...KIHhSSHhhhSSSSSShhhHSShHIK...",
        "...KHHhSSSKKKKSLLSKKKKSSShIHK...",
        "..KIHhSSSSQtEQSLLSQtEQSSSShHIK..",
        "..KIhSSSSSQEEQSLLSQEEQSSSSShHK..",
        ".KphSSSSSSpppppLLpppppSSSSSphsK.",
        ".KsSSSSCCSppppSLSpppppSCCSSpSdK.",
        ".KdSSSCCCSSSSspSSpsSSSSCCCSpSdK.",
        ".KsdSSSSpSSSSdssssdSSSSpSSSpddK.",
        ".KdKpSSSSShhHHHHHHHHhhSSSSpsKdK.",
        "..KKpSSSSSSSShHHHHhSSSSSSSpsKK..",
        "...KdSSSSSSSSSSSSSSSSSSSSSpdK...",
        "....KppSSSSMQQQQQQQQMSSSSpsK....",
        "....KdpSSSSSMQQQQQQMSSSSSpdK....",
        ".....KdppSSSdMMMMMMdSSSppdK.....",
        "......KdppSSSSLLLLSSSSppdK......",
        ".......KdppSSSSLLSSSSppdK.......",
        "........KKsppppppppppsKK........",
        "..........KKsppppppsKK..........",
        "............KssssssK............",
        ".............KKKKKK.............",
        "................................",
    ]
    // cheer 32x30
    static let cheerRows: [String] = [
        "...........KKKKKKKKKK...........",
        ".........KKpppppppppsKK.........",
        "........KppSSSLLLLSSSpsK........",
        ".......KIHhSLLLLLLLLSSHIK.......",
        "......KIHhSSLLLLLLLLLShHIK......",
        ".....KIHHhSSSLLLLLLLSShHHIK.....",
        "....KIIHhSSSSSLLLLLSSSSHHIIK....",
        "....KIHHhShhhSSLLLShhhShHHIK....",
        "...KHIhSSHhhhhSSSShhhhHSShHHK...",
        "...KIHhSSSSSSSSSSSSSSSSSShHIK...",
        "...KHHhSSSKKKKSLLSKKKKSSShIHK...",
        "..KIHhSSSSQtEQSLLSQtEQSSSShHIK..",
        "..KIhSSSSSQEEQSLLSQEEQSSSSShHK..",
        ".KphSSSSSSpppppLLpppppSSSSSphsK.",
        ".KsSSSSCCSppppSLSpppppSCCSSpSdK.",
        ".KdSSSCCCSSSSspSSpsSSSSCCCSpSdK.",
        ".KsdSSSSpSSSSdssssdSSSSpSSSpddK.",
        ".KdKpSSSSShhHHHHHHHHhhSSSSpsKdK.",
        "..KKpSSSSSSSShHHHHhSSSSSSSpsKK..",
        "...KdSSSSSSSSSSSSSSSSSSSSSpdK...",
        "....KppSSSSMQQQQQQQQMSSSSpsK....",
        "....KdpSSSMmmmmmmmmmmMSSSpdK....",
        ".....KdppSMmmRRRRRRmmMSppdK.....",
        "......KdppdMMMMMMMMMMdppdK......",
        ".......KdppSSSSLLSSSSppdK.......",
        "........KKsppppppppppsKK........",
        "..........KKsppppppsKK..........",
        "............KssssssK............",
        ".............KKKKKK.............",
        "................................",
    ]
    // frown 32x30
    static let frownRows: [String] = [
        "...........KKKKKKKKKK...........",
        ".........KKpppppppppsKK.........",
        "........KppSSSLLLLSSSpsK........",
        ".......KIHhSLLLLLLLLSSHIK.......",
        "......KIHhSSLLLLLLLLLShHIK......",
        ".....KIHHhSSSLLLLLLLSShHHIK.....",
        "....KIIHhSSSSSLLLLLSSSSHHIIK....",
        "....KIHHhSSSSSSLLLSSSSShHHIK.K..",
        "...KHIhSSSSShhSSSShhSSSSShHHKaK.",
        "...KIHhSSShhhSSddSShhhSSShHIKWaK",
        "...KHHhShhKKSSSLLSSSKKhhShIHKKK.",
        "..KIHhSSSSSSKKSLLSKKSSSSSShHIK..",
        "..KIhSSSSSKKSSSLLSSSKKSSSSShHK..",
        ".KphSSSSSSpppppLLpppppSSSSSphsK.",
        ".KsSSSSSSSppppSLSpppppSSSSSpSdK.",
        ".KdSSSSSSSSSSspSSpsSSSSSSSSpSdK.",
        ".KsdSSSSpSSSSdssssdSSSSpSSSpddK.",
        ".KdKpSSSSShhHHHHHHHHhhSSSSpsKdK.",
        "..KKpSSSShhSShHHHHhSShhSSSpsKK..",
        "...KdSSSSSSSSSSSSSSSSSSSSSpdK...",
        "....KppSSSSMMMMMMMMMMSSSSpsK....",
        "....KdpSSSSMQQMQQMQQMSSSSpdK....",
        ".....KdppSSMMMMMMMMMMSSppdK.....",
        "......KdppSSSSLLLLSSSSppdK......",
        ".......KdppSSSSLLSSSSppdK.......",
        "........KKsppppppppppsKK........",
        "..........KKsppppppsKK..........",
        "............KssssssK............",
        ".............KKKKKK.............",
        "................................",
    ]
}
