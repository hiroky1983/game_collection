import SwiftUI
import Core

/// 盤を「おじさんの家の間取り」に見せる表（#2250・会長決定 2026-10-21「区画は家の部屋」）。
///
/// 部屋の番号（`CatPuzzle.rooms` の値）に、名前・床の柄・色・クリアで猫がくつろぐ姿を当てる。
/// 家の見た目は会長がこだわる所なので、**色・柄・名前・姿はこの 1 か所で変えられる**ようにしてある
/// （盤の描画は `CatPuzzleBoardCanvas` がこの表を読むだけ）。
///
/// 線の強さの順は **壁（部屋の境目）＞マスの区切り（タップの単位）＞床の柄** に固定する
/// （会長 QA 2026-10-21: 床の柄がマスを細かく区切って「タイルが個別に押せる」ように見えた）。
enum CatPuzzleHouse {
    /// 床の柄。描き方は `CatPuzzleFloorPainter`。どの柄も **1 マス＝柄の 1 単位** に揃え、
    /// マスの中を細かく区切る線は引かない。
    enum Floor: CaseIterable, Sendable {
        /// 畳（横の細い筋）。
        case tatami
        /// フローリング（縦の板の継ぎ目と、互い違いの木口）。
        case planks
        /// タイル（1 マスに 1 枚。目地はマスの区切りと一致する）。
        case tile
        /// カーペット（点の織り目）。
        case carpet
        /// 土間・石（1 マスに 1 つの丸い石）。
        case stone
    }

    /// 部屋 1 つぶんの見た目。
    struct Room: Sendable {
        let name: String
        let floor: Floor
        /// 床の色（ライト / ダーク）。
        let tint: Color
        /// 床の柄の線の濃さ（0〜1。柄ごとの見え方の差をここで吸収する）。
        let patternStrength: Double
        /// クリアで猫がくつろぐ姿。
        let clearPose: CatPuzzleArt.Pose
    }

    /// 部屋の並び。盤の大きさが 6 なら先頭 6 部屋、9 なら 9 部屋全部を使う。
    /// 名前は表示のたびに引く（言語切り替えに追従）。
    ///
    /// 色は「部屋ごとにはっきり違う・楽しい」色味にしつつ、ライトは明るめ（L≈80〜88%）・ダークは
    /// 暗め（L≈30〜38%）に揃え、グレーと白の猫・×の印が埋もれない明度差を保つ。
    static var rooms: [Room] {
        [
            Room(name: tr("居間"), floor: .tatami,
                 tint: Color(light: 0xD7E08C, dark: 0x4C5A2E), patternStrength: 1.0, clearPose: .sleep),
            Room(name: tr("押し入れ"), floor: .planks,
                 tint: Color(light: 0xF2D3A0, dark: 0x5B4830), patternStrength: 0.9, clearPose: .sitUp),
            Room(name: tr("寝室"), floor: .carpet,
                 tint: Color(light: 0xFFC1C9, dark: 0x6A3946), patternStrength: 1.0, clearPose: .belly),
            Room(name: tr("書斎"), floor: .planks,
                 tint: Color(light: 0xC8B8F4, dark: 0x453B6E), patternStrength: 1.0, clearPose: .sitSide),
            Room(name: tr("お風呂"), floor: .tile,
                 tint: Color(light: 0xA3DEEA, dark: 0x2B5B68), patternStrength: 1.0, clearPose: .faceWow),
            Room(name: tr("台所"), floor: .tile,
                 tint: Color(light: 0xFFCB7E, dark: 0x6C4A1F), patternStrength: 1.0, clearPose: .pounce),
            Room(name: tr("玄関"), floor: .stone,
                 tint: Color(light: 0xD3C6B3, dark: 0x4E463B), patternStrength: 1.0, clearPose: .stretch),
            Room(name: tr("縁側"), floor: .planks,
                 tint: Color(light: 0xE6AE6A, dark: 0x60431F), patternStrength: 1.0, clearPose: .sitFront),
            Room(name: tr("廊下"), floor: .tile,
                 tint: Color(light: 0xB6E3C6, dark: 0x2F5A44), patternStrength: 1.0, clearPose: .sleep),
        ]
    }

    /// 部屋の番号から見た目を引く（番号が表より大きければ折り返す）。
    static func room(_ index: Int) -> Room {
        let table = rooms
        return table[((index % table.count) + table.count) % table.count]
    }

    /// 壁の線の太さ（部屋どうしの境目）。外周はこの 1.5 倍。
    static let wallWidth: CGFloat = 3.5
    /// マスの区切り（タップの単位）の線の太さ。壁より細く、床の柄よりはっきり濃く引く。
    /// 会長 2026-10-22「グリッドが若干見えづらい」で一段はっきりさせた値（#2678）を、盤を元の形に戻したあとも残す。
    static let gridWidth: CGFloat = 1.75
    /// マスの区切りの線の濃さ（ライト / ダーク。`gridColor` の不透明度）。
    static let gridOpacity: Double = 0.55
    static let gridOpacityDark: Double = 0.42
    /// マスの区切りの線（こげ茶 / 生成り）。
    static let gridColor = Color(light: 0x3C281E, dark: 0xF4ECE5, lightAlpha: gridOpacity, darkAlpha: gridOpacityDark)
    /// 床の柄の線の濃さの上限（`Theme.ink` の不透明度）。マスの区切りの 1/3 以下に抑える。
    static let patternMaxOpacity: Double = 0.09

    /// ×（いない印）の色。床の上で読めるよう `Theme.ink`（こげ茶 / 生成り）で描き、
    /// 下に `Theme.surface`（白 / 暗色）の縁取りを敷く。色だけに頼らず太い × の形でも分かる。
    static let crossColor: Color = Theme.ink
    static let crossHalo: Color = Theme.surface

    /// 盤の色（#2678 のドールハウス案の色合い。盤の形は元に戻したが色は残す・会長 QA build 47）。
    enum Palette {
        /// 壁（こげ茶 / ダークは床の暗さに合わせて明るい側へ寄せた木の色）。
        static let wall = Color(light: 0x5E4030, dark: 0xC4A484)
    }
}

/// 床の柄の描き方。1 マスずつ描いても隣のマスとつながって見えるよう、マスの格子に揃えた柄にする。
/// どの柄もマスの区切りの線（`CatPuzzleHouse.gridColor`）より明らかに薄く・細く描く。
enum CatPuzzleFloorPainter {
    static func draw(_ floor: CatPuzzleHouse.Floor, in rect: CGRect, strength: Double, context: inout GraphicsContext, ink: Color) {
        let s = rect.width
        let cap = CatPuzzleHouse.patternMaxOpacity
        var path = Path()
        var width: CGFloat = 0.8
        var alpha = cap * 0.7 * strength
        switch floor {
        case .tatami:
            // 横の細い筋（畳の目）。縦には区切らない。
            let step = s / 5
            var y = rect.minY + step
            while y < rect.maxY - step / 2 {
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += step
            }
            alpha = cap * 0.8 * strength
        case .planks:
            // 縦の板の継ぎ目 2 本と、互い違いの短い木口。
            for i in 1..<3 {
                let x = rect.minX + s * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            let col = Int((rect.minX / max(s, 1)).rounded())
            for i in 0..<3 {
                let x0 = rect.minX + s * CGFloat(i) / 3
                let y = rect.minY + s * ((i + col) % 2 == 0 ? 0.3 : 0.7)
                path.move(to: CGPoint(x: x0, y: y))
                path.addLine(to: CGPoint(x: x0 + s / 3, y: y))
            }
            alpha = cap * strength
        case .tile:
            // 1 マスに 1 枚のタイル。面を少し明るくして、マスの区切りが目地に見えるようにする
            // （2×2 の目地はマスを細かく割って見えたので廃止）。
            let inset = s * 0.07
            let face = Path(roundedRect: rect.insetBy(dx: inset, dy: inset), cornerRadius: s * 0.04)
            context.fill(face, with: .color(Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.30 * strength, darkAlpha: 0.10 * strength)))
            return
        case .carpet:
            // 点の織り目。
            let step = s / 4
            let r = max(0.7, s * 0.02)
            for i in 0..<4 {
                for j in 0..<4 {
                    let c = CGPoint(x: rect.minX + step * (CGFloat(i) + 0.5), y: rect.minY + step * (CGFloat(j) + 0.5))
                    path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                }
            }
            context.fill(path, with: .color(ink.opacity(cap * strength)))
            return
        case .stone:
            // 1 マスに 1 つの丸い石（面で描く。線で囲まない）。
            let inset = s * 0.1
            path.addRoundedRect(in: rect.insetBy(dx: inset, dy: inset), cornerSize: CGSize(width: s * 0.3, height: s * 0.3))
            context.fill(path, with: .color(ink.opacity(cap * 0.8 * strength)))
            return
        }
        context.stroke(path, with: .color(ink.opacity(alpha)), lineWidth: width)
    }
}
