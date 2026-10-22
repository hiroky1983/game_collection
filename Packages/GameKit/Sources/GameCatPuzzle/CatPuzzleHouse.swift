import SwiftUI
import Core

/// 盤を「おじさんの家の間取り」に見せる表（#2250・会長決定 2026-10-21「区画は家の部屋」）。
/// 見た目はドールハウス風の見下ろし（家具・ドア・窓・庭。会長決裁 2026-10-22「色合いはドールハウスでいい」）。
///
/// 部屋の番号（`CatPuzzle.rooms` の値）に、名前・床の柄・色・家具・クリアで猫がくつろぐ姿を当てる。
/// 家の見た目は会長がこだわる所なので、**色・柄・名前・家具・姿はこの 1 か所で変えられる**ようにしてある
/// （盤の描画は `CatPuzzleBoardCanvas` がこの表を読むだけ。家具・ドア・窓の置き場所は `CatPuzzleHouseLayout`）。
///
/// 線の強さの順は **壁（部屋の境目）＞マスの区切り（タップの単位）＞床の柄** に固定する
/// （会長 QA 2026-10-21: 床の柄がマスを細かく区切って「タイルが個別に押せる」ように見えた）。
/// マスの区切りは家具の上にも引く（会長 2026-10-22「グリッドが若干見えづらい」→ モックより一段はっきり）。
enum CatPuzzleHouse {
    /// 床の柄。描き方は `CatPuzzleFloorPainter`。どの柄も **1 マス＝柄の 1 単位** に揃え、
    /// マスの中を細かく区切る線は引かない。
    enum Floor: CaseIterable, Sendable {
        /// 畳（1 マス＝1 帖。縁と細い筋、向きは市松）。
        case tatami
        /// フローリング（縦の板の継ぎ目と、互い違いの木口・薄い木目）。
        case planks
        /// タイル（1 マスに 1 枚。目地はマスの区切りと一致する）。
        case tile
        /// カーペット（点の織り目）。
        case carpet
        /// 土間・石（1 マスに 1 つの丸い石）。
        case stone
    }

    /// 部屋に置く小物（描き方は `CatPuzzleFurniturePainter`）。
    enum Furniture: Hashable, Sendable {
        /// こたつ（布団＋天板＋みかん）。
        case kotatsu
        /// 押し入れ（棚板と畳んだ布団）。
        case oshiire
        /// 布団（枕＋掛け布団）。
        case futon
        /// 本棚＋文机。
        case shelf
        /// 浴槽＋桶。
        case bath
        /// 流し台＋コンロ。
        case kitchen
        /// 沓脱石と靴。
        case genkan
        /// 座布団＋湯のみ。
        case engawa

        /// 正方形（2×2 / 1×1）に置く小物か。それ以外は 2×1 / 1×2 / 1×1。
        var isSquare: Bool { self == .kotatsu || self == .engawa }
    }

    /// 部屋 1 つぶんの見た目。
    struct Room: Sendable {
        let name: String
        let floor: Floor
        /// 床の色（ライト / ダーク）。
        let tint: Color
        /// 床の柄の線の濃さ（0〜1。柄ごとの見え方の差をここで吸収する）。
        let patternStrength: Double
        let furniture: Furniture
        /// クリアで猫がくつろぐ姿。
        let clearPose: CatPuzzleArt.Pose
    }

    /// 部屋の並び。盤の大きさが 6 なら先頭 6 部屋、8 なら 8 部屋全部を使う。
    /// 名前は表示のたびに引く（言語切り替えに追従）。
    ///
    /// 色は「部屋ごとにはっきり違う・楽しい」色味にしつつ、ライトは明るめ（L≈80〜88%）・ダークは
    /// 暗め（L≈30〜38%）に揃え、グレーと白の猫・×の印が埋もれない明度差を保つ。
    static var rooms: [Room] {
        [
            Room(name: tr("居間"), floor: .tatami,
                 tint: Color(light: 0xD7E08C, dark: 0x4C5A2E), patternStrength: 1.0, furniture: .kotatsu, clearPose: .sleep),
            Room(name: tr("押し入れ"), floor: .planks,
                 tint: Color(light: 0xF2D3A0, dark: 0x5B4830), patternStrength: 0.9, furniture: .oshiire, clearPose: .sitUp),
            Room(name: tr("寝室"), floor: .carpet,
                 tint: Color(light: 0xFFC1C9, dark: 0x6A3946), patternStrength: 1.0, furniture: .futon, clearPose: .belly),
            Room(name: tr("書斎"), floor: .planks,
                 tint: Color(light: 0xC8B8F4, dark: 0x453B6E), patternStrength: 1.0, furniture: .shelf, clearPose: .sitSide),
            Room(name: tr("お風呂"), floor: .tile,
                 tint: Color(light: 0xA3DEEA, dark: 0x2B5B68), patternStrength: 1.0, furniture: .bath, clearPose: .faceWow),
            Room(name: tr("台所"), floor: .tile,
                 tint: Color(light: 0xFFCB7E, dark: 0x6C4A1F), patternStrength: 1.0, furniture: .kitchen, clearPose: .pounce),
            Room(name: tr("玄関"), floor: .stone,
                 tint: Color(light: 0xD3C6B3, dark: 0x4E463B), patternStrength: 1.0, furniture: .genkan, clearPose: .stretch),
            Room(name: tr("縁側"), floor: .planks,
                 tint: Color(light: 0xE6AE6A, dark: 0x60431F), patternStrength: 1.0, furniture: .engawa, clearPose: .sitFront),
        ]
    }

    /// 部屋の番号から見た目を引く（番号が表より大きければ折り返す）。
    static func room(_ index: Int) -> Room {
        let table = rooms
        return table[((index % table.count) + table.count) % table.count]
    }

    /// 壁の線の太さ（部屋どうしの境目）。
    static let wallWidth: CGFloat = 5
    /// 外周の壁の太さ。
    static let outerWallWidth: CGFloat = 8
    /// 外周の壁の角の丸み・部屋の札（木の看板）の角・木の扉の角（本番の盤での pt。遊び方の図では縮める）。
    static let outerWallCorner: CGFloat = 3
    static let signCorner: CGFloat = 3
    static let doorLeafCorner: CGFloat = 1.5
    /// マスの区切り（タップの単位）の線の太さ。壁より細く、床の柄よりはっきり濃く引く。
    /// モック（1.5pt・不透明度 0.45）より一段はっきり（会長 2026-10-22「若干見えづらい」）。
    static let gridWidth: CGFloat = 1.75
    /// マスの区切りの線の濃さ（ライト / ダーク。`gridColor` の不透明度）。
    static let gridOpacity: Double = 0.55
    static let gridOpacityDark: Double = 0.42
    /// マスの区切りの線（こげ茶 / 生成り）。家具の上にも引く。
    static let gridColor = Color(light: 0x3C281E, dark: 0xF4ECE5, lightAlpha: gridOpacity, darkAlpha: gridOpacityDark)
    /// 床の柄の線の濃さの上限（`Theme.ink` の不透明度）。マスの区切りの半分以下に抑える。
    static let patternMaxOpacity: Double = 0.26

    /// ×（いない印）の色。床の上で読めるよう `Theme.ink`（こげ茶 / 生成り）で描き、
    /// 下に `Theme.surface`（白 / 暗色）の縁取りを敷く。色だけに頼らず太い × の形でも分かる。
    static let crossColor: Color = Theme.ink
    static let crossHalo: Color = Theme.surface

    /// ドールハウスの色（モック `house.js` の doll 案。ダークは床の暗さに合わせて明るい側へ寄せる）。
    enum Palette {
        /// 壁（こげ茶）と、壁の上面のハイライト（少し立体に見せる細い線）。
        static let wall = Color(light: 0x5E4030, dark: 0xC4A484)
        static let wallHighlight = Color(light: 0x8C6A50, dark: 0xE2C9AA)
        /// 家具・扉の輪郭。
        static let outline = Color(light: 0x3E2A20, dark: 0x2A1A12)
        /// 扉の軌跡（点線）。床の上で読める色。
        static let doorArc = Color(light: 0x3E2A20, dark: 0xF4ECE5)
        /// 木の扉・敷居・玄関戸。
        static let doorLeaf = Color(hex: 0xB07A4A)
        static let threshold = Color(light: 0xE8D3B4, dark: 0xD9BE98)
        static let entranceDoor = Color(hex: 0xC98A4B)
        /// 窓（水色のガラスと白い枠）。
        static let glass = Color(light: 0xBFE7F4, dark: 0x8FC6D8)
        static let windowFrame = Color(light: 0xFFFFFF, dark: 0xF0EAE2)
        /// 庭（盤の外側の芝生・草・花）。
        static let grass = Color(light: 0xBFD98F, dark: 0x3E5A2C)
        static let grassBlade = Color(light: 0x6FA64A, dark: 0x8CC266)
        static let flowerYellow = Color(hex: 0xFFF1A8)
        static let flowerPink = Color(hex: 0xFFB6C8)
        /// 部屋の札（木の看板・釘・文字）。
        static let sign = Color(hex: 0x8B5A2B)
        static let signEdge = Color(hex: 0x3E2A20)
        static let signNail = Color(hex: 0xF1D9AE)
        static let signText = Color(hex: 0xFFF6EC)
        /// 畳の縁。
        static let tatamiEdge = Color(light: 0x5E6A3A, dark: 0x8A9A5A)
    }
}

/// 床の柄の描き方。1 マスずつ描いても隣のマスとつながって見えるよう、マスの格子に揃えた柄にする。
/// どの柄もマスの区切りの線（`CatPuzzleHouse.gridColor`）より明らかに薄く・細く描く。
enum CatPuzzleFloorPainter {
    static func draw(_ floor: CatPuzzleHouse.Floor, in rect: CGRect, row: Int, col: Int, strength: Double, context: inout GraphicsContext, ink: Color) {
        let s = rect.width
        let a = CatPuzzleHouse.patternMaxOpacity * strength
        var path = Path()
        switch floor {
        case .tatami:
            // 1 マス＝畳 1 帖。縁（へり）を描き、目の向きは市松に変える。
            let horizontal = (row + col) % 2 == 0
            let edge = s * 0.05
            context.stroke(Path(rect.insetBy(dx: edge / 2, dy: edge / 2)),
                           with: .color(CatPuzzleHouse.Palette.tatamiEdge.opacity(0.5)), lineWidth: edge)
            let step = s / 6
            for i in 1..<6 {
                if horizontal {
                    path.move(to: CGPoint(x: rect.minX + edge, y: rect.minY + step * CGFloat(i)))
                    path.addLine(to: CGPoint(x: rect.maxX - edge, y: rect.minY + step * CGFloat(i)))
                } else {
                    path.move(to: CGPoint(x: rect.minX + step * CGFloat(i), y: rect.minY + edge))
                    path.addLine(to: CGPoint(x: rect.minX + step * CGFloat(i), y: rect.maxY - edge))
                }
            }
            context.stroke(path, with: .color(ink.opacity(a * 0.6)), lineWidth: 0.8)
        case .planks:
            // 板 3 枚（縦の継ぎ目 2 本）と互い違いの木口、薄い木目。
            for i in 1..<3 {
                let x = rect.minX + s * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            for i in 0..<3 {
                let x0 = rect.minX + s * CGFloat(i) / 3
                let y = rect.minY + s * ((i + col + row) % 2 == 0 ? 0.3 : 0.7)
                path.move(to: CGPoint(x: x0, y: y))
                path.addLine(to: CGPoint(x: x0 + s / 3, y: y))
            }
            context.stroke(path, with: .color(ink.opacity(a)), lineWidth: 1)
            var grain = Path()
            for i in 0..<3 {
                let x = rect.minX + s * (CGFloat(i) + 0.5) / 3 - s * 0.04
                grain.move(to: CGPoint(x: x, y: rect.minY + s * 0.1))
                grain.addQuadCurve(to: CGPoint(x: x, y: rect.minY + s * 0.6), control: CGPoint(x: x + s * 0.08, y: rect.minY + s * 0.35))
            }
            context.stroke(grain, with: .color(ink.opacity(a * 0.35)), lineWidth: 0.8)
        case .tile:
            // 1 マスに 1 枚のタイル。面を少し明るくして、マスの区切りが目地に見えるようにする
            // （2×2 の目地はマスを細かく割って見えたので廃止）。角に白い照り。
            let inset = s * 0.07
            let face = Path(roundedRect: rect.insetBy(dx: inset, dy: inset), cornerRadius: s * 0.05)
            context.fill(face, with: .color(Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.38 * strength, darkAlpha: 0.12 * strength)))
            var shine = Path()
            shine.move(to: CGPoint(x: rect.minX + s * 0.14, y: rect.minY + s * 0.2))
            shine.addLine(to: CGPoint(x: rect.minX + s * 0.44, y: rect.minY + s * 0.2))
            context.stroke(shine, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        case .carpet:
            // 点の織り目。
            let step = s / 4
            let r = max(0.8, s * 0.025)
            for i in 0..<4 {
                for j in 0..<4 {
                    let c = CGPoint(x: rect.minX + step * (CGFloat(i) + 0.5), y: rect.minY + step * (CGFloat(j) + 0.5))
                    path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                }
            }
            context.fill(path, with: .color(ink.opacity(a * 0.6)))
        case .stone:
            // 1 マスに 1 つの丸い石（面で描く。線で囲まない）。上に薄い照り。
            let inset = s * 0.1
            path.addRoundedRect(in: rect.insetBy(dx: inset, dy: inset), cornerSize: CGSize(width: s * 0.3, height: s * 0.3))
            context.fill(path, with: .color(ink.opacity(a * 0.45)))
            let shineInset = s * 0.16
            context.fill(Path(roundedRect: rect.insetBy(dx: shineInset, dy: shineInset), cornerRadius: s * 0.26),
                         with: .color(Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.25, darkAlpha: 0.08)))
        }
    }
}
