import SwiftUI

/// 具体物カードの絵柄（#1243・#1244）。カードしりとりと神経衰弱が同じ絵を使う。
///
/// **OS の絵文字は使わない**（意匠が iOS のバージョンで変わるため）。チャリンコおじさんと同じ
/// ドット絵（`PixelSprite`）で、**20×20 ドット・外側に 1 ドットの縁取り**に揃えてある。
/// 描き方: 図形（楕円・矩形・線）を重ねてから縁取りを自動で付けて文字列にした。
///
/// `rawValue` は**中断データに書く識別子**になりうるので、一度出した値は変えない。
public enum ObjectCardKind: String, CaseIterable, Sendable, Codable {
    case apple, gorilla, seaOtter, koala, camel, rabbit, guitar, drum, kitten, glass
    case squirrel, watermelon, turtle, eyeglasses, cat, spinningTop, pillow, ostrich, handFan, crocodile

    /// VoiceOver の読み上げ文。絵だけのカードなので、言葉はここで持つ。
    public var displayName: String {
        switch self {
        case .apple:       return "りんご"
        case .gorilla:     return "ゴリラ"
        case .seaOtter:    return "ラッコ"
        case .koala:       return "コアラ"
        case .camel:       return "ラクダ"
        case .rabbit:      return "ウサギ"
        case .guitar:      return "ギター"
        case .drum:        return "たいこ"
        case .kitten:      return "こねこ"
        case .glass:       return "コップ"
        case .squirrel:    return "リス"
        case .watermelon:  return "スイカ"
        case .turtle:      return "カメ"
        case .eyeglasses:  return "めがね"
        case .cat:         return "ネコ"
        case .spinningTop: return "こま"
        case .pillow:      return "まくら"
        case .ostrich:     return "ダチョウ"
        case .handFan:     return "うちわ"
        case .crocodile:   return "ワニ"
        }
    }

    /// ドット絵の 1 辺（ドット）。全種そろっている（テストが縛る）。
    public static let dots = 20

    public var sprite: PixelSprite {
        switch self {
        case .apple:       return ObjectCardSprites.apple
        case .gorilla:     return ObjectCardSprites.gorilla
        case .seaOtter:    return ObjectCardSprites.seaOtter
        case .koala:       return ObjectCardSprites.koala
        case .camel:       return ObjectCardSprites.camel
        case .rabbit:      return ObjectCardSprites.rabbit
        case .guitar:      return ObjectCardSprites.guitar
        case .drum:        return ObjectCardSprites.drum
        case .kitten:      return ObjectCardSprites.kitten
        case .glass:       return ObjectCardSprites.glass
        case .squirrel:    return ObjectCardSprites.squirrel
        case .watermelon:  return ObjectCardSprites.watermelon
        case .turtle:      return ObjectCardSprites.turtle
        case .eyeglasses:  return ObjectCardSprites.eyeglasses
        case .cat:         return ObjectCardSprites.cat
        case .spinningTop: return ObjectCardSprites.spinningTop
        case .pillow:      return ObjectCardSprites.pillow
        case .ostrich:     return ObjectCardSprites.ostrich
        case .handFan:     return ObjectCardSprites.handFan
        case .crocodile:   return ObjectCardSprites.crocodile
        }
    }

    /// 1 ドット = 4px で持つビットマップ。起動後 1 回だけ作る（毎表示でビットマップ化しない）。
    private static let images: [ObjectCardKind: CGImage] = {
        var out: [ObjectCardKind: CGImage] = [:]
        for kind in allCases { if let cg = kind.sprite.cgImage(scale: 4) { out[kind] = cg } }
        return out
    }()

    public var cgImage: CGImage? { Self.images[self] }
}

/// 具体物カードの絵。枠いっぱいに整数倍でなくても、補間せずドットの縁を立てる。
/// 装飾扱い（VoiceOver は親のカードが `displayName` で読む）。
public struct ObjectCardArt: View {
    private let kind: ObjectCardKind

    public init(_ kind: ObjectCardKind) { self.kind = kind }

    public var body: some View {
        if let cg = kind.cgImage {
            Image(decorative: cg, scale: 1).renderingMode(.original).resizable().interpolation(.none)
                .aspectRatio(1, contentMode: .fit)
        } else {
            Image(systemName: "questionmark.square").resizable().aspectRatio(1, contentMode: .fit)
        }
    }
}

// MARK: - ドット絵

enum ObjectCardSprites {
    static let apple = PixelSprite(
        rows: [
            "....................",
            ".........KKKKKKK....",
            "........KaabbbbbK...",
            "........KabccbbbbK..",
            ".......KKaKbbbbbK...",
            ".....KKdeeedKKKK....",
            "....KdddddddddK.....",
            "...KdfdddddddddK....",
            "..KdfffdddddddddK...",
            "..KdfffdddddddddK...",
            "..KdfffdddddddddK...",
            ".KdddfdddddddedddK..",
            "..KdddddddddeeedK...",
            "..KddddddddeeeeeK...",
            "..KddddddddeeeeeK...",
            "...KdddddddeeeeeK...",
            "....KdddddddeeeK....",
            ".....KKdddddKeK.....",
            ".......KKKKK.K......",
            "....................",
        ],
        palette: ["K": 0x3A2A2A, "a": 0x6B4423, "b": 0x39A85B, "c": 0x2C7F44, "d": 0xE24A3C, "e": 0xB8322A, "f": 0xFF9C8C]
    )

    static let gorilla = PixelSprite(
        rows: [
            ".........K..........",
            "......KKKaKKK.......",
            ".....KaaaaaaaK......",
            "....KaaaaaaaaaK.....",
            "...KbbbbbbbbbbaK....",
            "..KabbbbbbbbbbaaK...",
            ".KaaaccddddccaaaaK..",
            "KaaaaceddddecdaaaK..",
            ".KaaadddfffdddaaaK..",
            "..KaaddfefefddaaK...",
            "...KadddfffdddaK....",
            "....KdddddddddK.....",
            "...KKKdeeeeedKKK....",
            "..KbbaadddddaabbK...",
            ".KabbaaaaaaaaabbaK..",
            "KaabbaaaaaaaaabbaaK.",
            ".KaaaaaaaaaaaaaaaK..",
            "..KKaaaaaaaaaaaKK...",
            "....KKKKKaKKKKK.....",
            ".........K..........",
        ],
        palette: ["K": 0x3A2A2A, "a": 0x5A5F6B, "b": 0x3E4049, "c": 0xFFFFFF, "d": 0x8C7F78, "e": 0x2B2B33, "f": 0x5E534E]
    )

    static let seaOtter = PixelSprite(
        rows: [
            "....................",
            ".........K..........",
            "....KKKKKaKKKKK.....",
            "...KaaaaaaaaaaaK....",
            "...KaaaaaaaaaaaK....",
            "...KaaaaaaaaaaaK....",
            "...KaabaaaaabaaK....",
            "...KaaacccccaaaK....",
            "...KaaccbbbccaaK....",
            "...KaacccbcccaaK....",
            "....KacccdcccaK.....",
            "...KKaaaeeeaaaKK....",
            "..KaaaaefefeaaaaK...",
            ".KaaaaaaeeeaaaaaaK..",
            "KaaacccccccccccaaaK.",
            ".KaaacccccccccaaaK..",
            "..KaaaaaacaaaaaaK...",
            ".KgggaaaaaaaaggggK..",
            "..KKKKKKKKKKKKKKK...",
            "....................",
        ],
        palette: ["K": 0x3A2A2A, "a": 0x9A6A3A, "b": 0x2B2B33, "c": 0xF7E8C8, "d": 0x6B4423, "e": 0xF4A6B7, "f": 0xE06C8B, "g": 0xBFE3F5]
    )

    static let koala = PixelSprite(
        rows: [
            "....................",
            "...KK.........KK....",
            "..KaaKK.....KKaaK...",
            ".KaaaaaKKKKKaaaaaK..",
            "KabbbbaaaaaaabbbbaK.",
            "KabbbaaaaaaaaabbbaK.",
            "KabbaaaaaaaaaaabbaK.",
            ".KaaacaaaaaaacaaaK..",
            "..KaacaacccaacaaK...",
            "..KaaaaadccaaaaaK...",
            ".KaaaaacccccaaaaaK..",
            "..KaaaacccccaaaaK...",
            "..KaaaeeccceeaaaK...",
            "..KaaeeeccceeeaaK...",
            "...KaaeedddeeaaK....",
            "....KaaeeeeeaaK.....",
            ".....KKaaeaaKK......",
            ".......KKKKK........",
            "....................",
            "....................",
        ],
        palette: ["K": 0x3A2A2A, "a": 0x9AA3AD, "b": 0xF4A6B7, "c": 0x2B2B33, "d": 0x5A5F6B, "e": 0xD8DDE3]
    )

    static let camel = PixelSprite(
        rows: [
            "....................",
            "...............K....",
            ".............KKaKK..",
            "............KbbbbbK.",
            "....K....KK.KbbbbcK.",
            "...KbK..KbbK.KbbKK..",
            "..KbbbKKbbbbKbbK....",
            ".KbbbbbKbbbbbbbK....",
            ".KbbbbbbbbbbbKbK....",
            ".KKbbbbbbbbbbbK.....",
            "KcbbbbbbbbbbbK......",
            "KcbcccccccccbbK.....",
            "KcbbbbbbbbbbbK......",
            "KcKccbccbccbccK.....",
            "KcKccKccKccKccK.....",
            ".KKccKccKccKccK.....",
            "..KccKccKccKccK.....",
            "..KccKccKccKccK.....",
            "...KK.KK.KK.KK......",
            "....................",
        ],
        palette: ["K": 0x3A2A2A, "a": 0x2B2B33, "b": 0xD9B382, "c": 0xB98B4E]
    )

    static let rabbit = PixelSprite(
        rows: [
            ".....KK.....KK......",
            "....KaaK...KaaK.....",
            "....KaaK...KaaK.....",
            "...KaaaaK.KaaaaK....",
            "...KabbaK.KabbaK....",
            "...KabbaK.KabbaK....",
            "...KabbaK.KabbaK....",
            "...KabbaKKKabbaK....",
            "....KaaaaaaaaaK.....",
            "....KaaaaaaaaaK.....",
            "...KaaaaaaaaaaaK....",
            "..KaaacaaaaacaaaK...",
            "..KaaacaaaaacaaaK...",
            ".KKaaaaaaaaaaaaaKK..",
            "KdddbbaaeeeaabbdddK.",
            ".KKabbaaeaeaabbaKK..",
            "...KaaaaaaaaaaaK....",
            "....KaaaaaaaaaK.....",
            ".....KKaaaaaKK......",
            ".......KKKKK........",
        ],
        palette: ["K": 0x3A2A2A, "a": 0xFFFFFF, "b": 0xF4A6B7, "c": 0x2B2B33, "d": 0xD8DDE3, "e": 0xE06C8B]
    )

    static let guitar = PixelSprite(
        rows: [
            ".......KKKKK........",
            "......KaaaaaK.......",
            "......KaaaaaK.......",
            "......KaabaaK.......",
            ".......KcbcK........",
            ".......KcbcK........",
            ".......KcbcK........",
            "......KddbddK.......",
            ".....KdddbdddK......",
            ".....KdddbdddK......",
            ".....KdddbdddK......",
            ".....KdddbdddK......",
            "....KdedcbcdddK.....",
            "...KdedcabacdddK....",
            "...KdddcabacdddK....",
            "...KdddcabacdddK....",
            "....KdddcbcdddK.....",
            ".....KdccbccdK......",
            "......KKKdKKK.......",
            ".........K..........",
        ],
        palette: ["K": 0x3A2A2A, "a": 0x2B2B33, "b": 0xD8DDE3, "c": 0x6B4423, "d": 0x9A6A3A, "e": 0xD9A05B]
    )

    static let drum = PixelSprite(
        rows: [
            "....................",
            "....K...........K...",
            "...KaKK.......KKaK..",
            "....KbbK.....KbbK...",
            ".....KKbK...KbKK....",
            "......KKbKKKbKK.....",
            "....KKcccbbbcccKK...",
            "...KccdddbdbdddccK..",
            "..KecdddddddddddcK..",
            "..KfccdddddddddcfK..",
            "..KfgecgccgccgcefK..",
            "..KfeeeeeeeeeeeefK..",
            "..KfeeeeeeeeeeeefK..",
            "..KfegeegeegeegefK..",
            "..KfeeeeeeeeeeeefK..",
            "..KfeeeeeeeeeeeefK..",
            "...KeeeeeeeeeeeeeK..",
            "....KKKeeeeeeeKKK...",
            ".......KKKKKKK......",
            "....................",
        ],
        palette: ["K": 0x3A2A2A, "a": 0xD9B382, "b": 0x6B4423, "c": 0xF7E8C8, "d": 0xEBD6A8, "e": 0xE24A3C, "f": 0xB8322A, "g": 0xF2C230]
    )

    static let kitten = PixelSprite(
        rows: [
            "..K.............K...",
            ".KaK...........KaK..",
            ".KaaK.........KaaK..",
            ".KabaKKKKKKKKKabaK..",
            ".KabbaaaccaaaabbaK..",
            ".KabacaaccaaacabaK..",
            ".KaaacaaaaaaacaaaK..",
            ".KaaaaaaaaaaaaaaaK..",
            ".KaadedaaaaadedaaK..",
            ".KaadddafffadddaaK..",
            ".KaaaafffgfffaaaaK..",
            "..KaaaffdfdffaaaK...",
            "..KaaafffffffaaaK...",
            "...KaaaafffaaaaKK...",
            "....KKaaaaaaaKgggK..",
            ".....KaaaaaaahhgggK.",
            ".....KaaaaaaagghggK.",
            ".....KaaaaaaaggghhK.",
            "......KKKaKKKKgggK..",
            ".........K....KKK...",
        ],
        palette: ["K": 0x3A2A2A, "a": 0xF08A2E, "b": 0xF4A6B7, "c": 0xC96A1E, "d": 0x2B2B33, "e": 0xFFFFFF, "f": 0xF7E8C8, "g": 0xE06C8B, "h": 0xFFD1DC]
    )

    static let glass = PixelSprite(
        rows: [
            "...........KK.......",
            "..........KaaK......",
            "..........KaaK......",
            "...KKKKKKKKaKKKK....",
            "..KbbbbbbbaabbbbK...",
            "..KbcbbbbbaabbbbK...",
            "..KbcbbbbbaabbbbK...",
            "..KbcbbbbababbbbK...",
            "..KbcbbbbaabbbbbK...",
            "..KdcddddaadddddK...",
            "...KcddcdddddddK....",
            "...KcddddddddddK....",
            "...KcdddddcddddK....",
            "...KcddddddddddK....",
            "...KcddddddddddK....",
            "...KdddddddddddK....",
            "..KeeeeeeeeeeeeeK...",
            "..KeeeeeeeeeeeeeK...",
            "...KKKKKKKKKKKKK....",
            "....................",
        ],
        palette: ["K": 0x3A2A2A, "a": 0xE24A3C, "b": 0xBFE3F5, "c": 0xFFFFFF, "d": 0x3596D4, "e": 0xD8DDE3]
    )

    static let squirrel = PixelSprite(
        rows: [
            "..K....K....K.K.....",
            ".KaK..KaK.KKaKaK....",
            ".KaK..KaKKaaaaaaK...",
            ".KaaKKaaKaaabaaaaK..",
            ".KaaaaaaKaabbbaaaK..",
            "KaaaaaaKaaabbbaaaaK.",
            "KaaaaaaaaaabbbaaaK..",
            "KaacaaaaaaabbbaaaK..",
            "KcaaaaaaaabbbbbaaK..",
            ".KaaaaaaaaabbbaaaK..",
            ".KaaadddaaabbbaaaK..",
            ".KeeeddddaabbbaaaK..",
            ".KeeeddddaabbbaaK...",
            ".KeeeddddaaabaaaK...",
            ".KaadddddaaaaaaK....",
            "..KaaaaddaKKaKK.....",
            "...KaaadfffKK.......",
            "...KaaafffffK.......",
            "....KKKKfffK........",
            "........KKK.........",
        ],
        palette: ["K": 0x3A2A2A, "a": 0x9A6A3A, "b": 0xC08A57, "c": 0x2B2B33, "d": 0xF7E8C8, "e": 0xD9B382, "f": 0x6B4423]
    )

    static let watermelon = PixelSprite(
        rows: [
            "....................",
            "....................",
            "....................",
            ".KKKKKKKKKKKKKKKKK..",
            "KaaaaaaaaaaaaaaaaaK.",
            "KabcccccccccccccbaK.",
            "KabcccccccccccccbaK.",
            ".KabcccccdcccccbaK..",
            ".KabcdcccdcccdcbaK..",
            "..KabdcccccccdbaK...",
            "..KaabbccdccbbaaK...",
            "...KKaabbdbbaaKK....",
            ".....KKaaaaaKK......",
            "......KdKKKdK.......",
            "......KdK.KdK.......",
            ".......K...K........",
            "....................",
            "....................",
            "....................",
            "....................",
        ],
        palette: ["K": 0x3A2A2A, "a": 0x2C7F44, "b": 0xFFFFFF, "c": 0xE24A3C, "d": 0x2B2B33]
    )

    static let turtle = PixelSprite(
        rows: [
            "....................",
            "....................",
            "....................",
            ".......KKKKK........",
            ".....KKaaaaaKK......",
            "....KaaaaaaaaaK.....",
            "...KaaabccbbaaaK....",
            "..KaaabbccbbbaaaKKK.",
            "..KaabbbccbbbbaccdcK",
            "..KaacccccccccaccccK",
            "..KaabbbccbbbbaccccK",
            "..KaaabbccbbbaaaKKK.",
            ".KcaaaabccbbaaaaK...",
            "KcKcccaaaaaacccaK...",
            ".KKcccaaaaaacccaK...",
            "..KcccKKKKKKcccK....",
            "...KKK......KKK.....",
            "....................",
            "....................",
            "....................",
        ],
        palette: ["K": 0x3A2A2A, "a": 0x39A85B, "b": 0x2C7F44, "c": 0x8DD16B, "d": 0x2B2B33]
    )

    static let eyeglasses = PixelSprite(
        rows: [
            "....................",
            "....................",
            "....................",
            ".K................K.",
            "KaK..............KaK",
            "KaK..KK.......KK.KaK",
            ".KaKKaaKK...KKaaKaK.",
            ".KaaaaaaaK.KaaaaaaK.",
            "..KabcccaaKaabcccaK.",
            ".KabcccccaaabcccccaK",
            ".KaccccccaKaccccccaK",
            ".KaccccccaKaccccccaK",
            "..KaccccaaKaaccccaK.",
            "..KaaaaaaK.KaaaaaaK.",
            "...KKaaKK...KKaaKK..",
            ".....KK.......KK....",
            "....................",
            "....................",
            "....................",
            "....................",
        ],
        palette: ["K": 0x3A2A2A, "a": 0x2B2B33, "b": 0xFFFFFF, "c": 0xBFE3F5]
    )

    static let cat = PixelSprite(
        rows: [
            "...K...........K....",
            "..KaK.........KaK...",
            "..KabKK..K..KKbaK...",
            "..KabbaKKaKKabbaK...",
            "..KabbaaccaaabbaK...",
            "..KabcaaccaaacbaK...",
            "..KaacaaaaaaacaaK...",
            "..KaaaaaaaaaaaaaK...",
            ".KKaaadaaaaadaaaKK..",
            "KeeeaadaaaaadaaeeeK.",
            ".KKKaaaaafaaaaaKKK..",
            "....KaaadadaaaK.....",
            "....KKaaaaaaaKK..K..",
            "...KaaaaeeeaaaaKKaK.",
            "...KaaaeeeeeaaaKaaK.",
            "...KaaaeeeeeaaaKaaK.",
            "...KaaaaeeeaaaaaaK..",
            "....KKaaaaaaaKKKK...",
            "......KKKKKKK.......",
            "....................",
        ],
        palette: ["K": 0x3A2A2A, "a": 0x9AA3AD, "b": 0xF4A6B7, "c": 0x5A5F6B, "d": 0x2B2B33, "e": 0xD8DDE3, "f": 0xE06C8B]
    )

    static let spinningTop = PixelSprite(
        rows: [
            "........KK..........",
            ".......KaaK.........",
            ".......KaaK.........",
            ".......KaaK.........",
            "......KaaaaK........",
            ".......KKKKK........",
            "....KKKbbbbbKKK.....",
            "...KbbbbbbbbbbbK....",
            "..KbbccbbbbbbbbbK...",
            ".KbdddddddddddddbK..",
            ".KedddddddddddddeK..",
            "..KeeeeeeeeeeeeeK...",
            "...KeeeeeeeeeeeK....",
            "....KeeeeeeeeeK.....",
            ".....KeeeeeeeK......",
            "......KeeeeeK.......",
            ".......KeeeK........",
            "........KeK.........",
            "........KaK.........",
            ".........K..........",
        ],
        palette: ["K": 0x3A2A2A, "a": 0x6B4423, "b": 0x3596D4, "c": 0xFFFFFF, "d": 0xF2C230, "e": 0xE24A3C]
    )

    static let pillow = PixelSprite(
        rows: [
            "....................",
            "....................",
            "..........K.........",
            "..K...KKKKaKKKK.....",
            ".KbKKKaaaaaaaaaKK...",
            "KbKaaaaaaaaaaaaaaK..",
            "KbaacaacaacaacaacaK.",
            ".KadcaacaacaacaacaK.",
            ".KadcaacaacaacaacaK.",
            ".KaacaacaacaacaacaaK",
            ".KaacaacaacaacaacaK.",
            ".KaacaacaacaacaacaK.",
            ".KaacaacaacaacaacbbK",
            "..KaaaaaaaaaaaaaaKbK",
            "...KKKaaaaaaaaaKK.K.",
            "......KKKKaKKKK.....",
            "..........K.........",
            "....................",
            "....................",
            "....................",
        ],
        palette: ["K": 0x3A2A2A, "a": 0xBFE3F5, "b": 0xF2C230, "c": 0x9CCBE8, "d": 0xFFFFFF]
    )

    static let ostrich = PixelSprite(
        rows: [
            "............KKK.....",
            "...........KabaK....",
            "..........KaaaacK...",
            "...........KaaaKcK..",
            "........K..KaaK.K...",
            "....KKKKbKKKaaK.....",
            "...KdbbbdbbbaaK.....",
            "..KdddbdbbbbaaK.....",
            ".KdddddbbbbbaaK.....",
            ".KdddddbbbbbbbK.....",
            ".KdddddbbbbbbK......",
            "..KdddbbbbbbbK......",
            "...KdbbbbbbbK.......",
            "....KKKKaKaK........",
            ".......KaKaK........",
            ".......KaKaK........",
            ".......KaKaK........",
            ".......KaKaKK.......",
            "......KaaaaaaK......",
            ".......KKKKKK.......",
        ],
        palette: ["K": 0x3A2A2A, "a": 0xE8B4A0, "b": 0x2B2B33, "c": 0xF08A2E, "d": 0xFFFFFF]
    )

    static let handFan = PixelSprite(
        rows: [
            ".......KKKKK........",
            ".....KKaaaaaKK......",
            "....KaaaaaaaaaK.....",
            "...KaaabbbbbaaaK....",
            "..KaacbbbbbbbcaaK...",
            ".KaaabbbaaabbbaaaK..",
            ".KaabbbaaaaabbbaaK..",
            ".KaabbbaaaaabbbaaK..",
            ".KaabbbaaaaabbbaaK..",
            ".KaabbbaaaaabbbaaK..",
            ".KaaabbbaaabbbaaaK..",
            "..KaacbbbbbbbcaaK...",
            "...KaaabbbbbaaaK....",
            "....KaaddddaaaK.....",
            ".....KKddddaKK......",
            ".......KeeKK........",
            ".......KeeK.........",
            ".......KeeK.........",
            ".......KeeK.........",
            "........KK..........",
        ],
        palette: ["K": 0x3A2A2A, "a": 0xE24A3C, "b": 0xFFFFFF, "c": 0xF2C230, "d": 0xB98B4E, "e": 0xD9B382]
    )

    static let crocodile = PixelSprite(
        rows: [
            "....................",
            "....................",
            "....................",
            "....................",
            ".....KK.KK.KKK......",
            "....KaaKaaKaabK.....",
            "....KaaKaaKaacKKKKK.",
            "...KdddddddddddddddK",
            "..KddddddddddddddddK",
            ".KdddddddddddddededK",
            "KdddfffffffffffdedK.",
            ".KKKKaaKKKKaaKKKKK..",
            "....KaaK..KaaK......",
            "....KaaK..KaaK......",
            ".....KK....KK.......",
            "....................",
            "....................",
            "....................",
            "....................",
            "....................",
        ],
        palette: ["K": 0x3A2A2A, "a": 0x2C7F44, "b": 0x2B2B33, "c": 0xF2C230, "d": 0x39A85B, "e": 0xFFFFFF, "f": 0x8DD16B]
    )
}
