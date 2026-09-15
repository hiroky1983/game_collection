import Foundation

// MARK: - おじさん（ドット絵）

/// 「あそびば」のマスコット、チャリンコおじさんのドット絵。スーパーファミコン級の 2D に統一する
/// 決裁（2026-09-15・会長）に従い、走者のコマと正面顔をここ（Core）に置く。おじさんシリーズの
/// 2 本目以降でも同じ顔にするため、ゲーム側にドットを書かない。
///
/// 設定: 大阪に住む 65 歳。薄い頭に白髪まじりの側頭部、太い眉、鼻の下のヒゲ（メガネは無し・会長
/// 指示 2026-09-15）、笑顔、黄色のポロシャツ、紺のズボン、前かご付きの赤いママチャリ。
///
/// 走者のコマは 40×36 ドット（右向き）。1 ドット = 整数 pt で描く（`PixelSprite.cgImage(scale:)`）。
/// 正面顔は 16×15 ドット（ハブのカード・リザルト・LP）。
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

    // MARK: 格子（手で直すときは行の長さを揃えること。PixelArtTests が検査する）

    // ride0 40x36
    static let ride0Rows: [String] = [
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
    // ride1 40x36
    static let ride1Rows: [String] = [
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
    // jump 40x36
    static let jumpRows: [String] = [
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
    // tumble 40x36
    static let tumbleRows: [String] = [
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
    // dizzy 40x36
    static let dizzyRows: [String] = [
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
    static let smileRows: [String] = [
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
    // cheer 16x15
    static let cheerRows: [String] = [
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
    // frown 16x15
    static let frownRows: [String] = [
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
}
