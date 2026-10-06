// ゲーム画面の「操作の段」モック生成器（#1834）。
// macOS 上で `swiftc -O mock.swift -o mockbin && ./mockbin <出力ディレクトリ>` で
// iPhone 17（402×874pt）と iPhone SE（375×667pt）を横に並べた PNG（@2x）を書き出す。
// アプリのビルドには一切使わない使い捨て。色・角丸・丸ゴシックは Core/Theme.swift のライト側の値を写している。
// 盤・札は本物ではなく、段の見え方を比べるための簡略図。
import AppKit
import SwiftUI

// MARK: - Theme（Core/Theme.swift のライト値）

func hex(_ v: UInt32, _ a: Double = 1) -> Color {
    Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: a)
}

enum T {
    static let background = hex(0xFFF6EC)
    static let surface = hex(0xFFFFFF)
    static let ink = hex(0x4A3B33)
    static let inkSub = hex(0x9A8A80)
    static let fillMuted = hex(0x9A8A80)
    static let coral = hex(0xFF6F61)
    static let teal = hex(0x22C3BE)
    static let purple = hex(0x8C7BE0)
    static let yellow = hex(0xFFC24B)
    // Theme.Fill（文字 onAccent を載せて AA を満たす面色）
    static let fillCoral = hex(0xFF8A7E)
    static let fillTeal = hex(0x22C3BE)
    static let fillPurple = hex(0xB3A6F0)
    static let fillYellow = hex(0xFFC24B)
    static let onAccent = hex(0x4A3B33)
    static let shadow = Color.black.opacity(0.08)
    static let corner: CGFloat = 20
    static let cornerSmall: CGFloat = 12
    static let pad: CGFloat = 16
}

extension View {
    func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> some View {
        font(.system(size: size, weight: weight, design: .rounded))
    }
    func popCard(fill: Color = T.surface, corner: CGFloat = T.corner) -> some View {
        background(
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(fill)
                .shadow(color: T.shadow, radius: 10, x: 0, y: 6)
        )
    }
}

// MARK: - 端末

struct Device {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let statusHeight: CGFloat   // ステータスバー（セーフエリア上端）
    let bottomInset: CGFloat    // ホームインジケータ
    let corner: CGFloat
    static let iPhone17 = Device(name: "iPhone 17（402×874pt）", width: 402, height: 874, statusHeight: 59, bottomInset: 34, corner: 54)
    static let se = Device(name: "iPhone SE 第3世代（375×667pt）", width: 375, height: 667, statusHeight: 20, bottomInset: 0, corner: 0)
}

// MARK: - 操作の段の仕様

enum Role { case undo, hint, skip, primary, declaration, destructive }

extension Role {
    var fill: Color {
        switch self {
        case .primary, .destructive: T.fillCoral
        case .undo: T.fillTeal
        case .hint: T.fillYellow
        case .skip: T.fillMuted
        case .declaration: T.fillPurple
        }
    }
    var foreground: Color { self == .skip ? .white : T.onAccent }
    /// 案B（面の無い段）で使う差し色。
    var tint: Color {
        switch self {
        case .primary, .destructive: T.coral
        case .undo: hex(0x169E9A)
        case .hint: hex(0xD99A12)
        case .skip: T.inkSub
        case .declaration: T.purple
        }
    }
}

/// 回数・広告の見せ方。たたき台 6「広告が出るボタンには ▶、無料の間は あと◯回」。
enum Badge { case free(Int), ad, none }

struct Action: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let role: Role
    var badge: Badge = .none
    var enabled = true
    /// チェック付きの切り替え（メモ・旗モード・拡大）。nil なら普通の操作。
    var toggled: Bool? = nil
}

enum RowStyle: String { case current = "現状", a = "A", b = "B", c = "C" }

/// いまの「⋯」の行（GameOverflowBar）。左端に表示だけの文字、右端に丸 44pt。
struct RowCurrent: View {
    var caption: String?
    /// 上下の余白。盤ゲーム 5 本は 1pt（`BoardGameControlMetrics.rowVerticalPadding`）、ナンプレは 4pt、他は既定の 8pt。
    var verticalPadding: CGFloat = 8
    var body: some View {
        HStack(spacing: 8) {
            if let caption { Text(caption).rounded(12, .bold).foregroundStyle(T.inkSub) }
            Spacer(minLength: 0)
            MoreButton()
        }
        .frame(minHeight: 44)
        .padding(.vertical, verticalPadding)
    }
}

// MARK: - 案A: 役割の色で塗ったカプセルを等幅に並べる（いまの GameButtonStyle.capsule の延長）

struct RowA: View {
    let actions: [Action]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(actions) { a in
                let on = a.toggled ?? true
                HStack(spacing: 6) {
                    Image(systemName: a.toggled == true ? "checkmark.circle.fill" : a.icon).font(.system(size: 16, weight: .bold))
                    VStack(alignment: .leading, spacing: -1) {
                        Text(a.title).rounded(14, .bold)
                        badgeText(a.badge)
                    }
                }
                .foregroundStyle(!a.enabled ? Color.white : (on ? a.role.foreground : T.ink))
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    Capsule().fill(!a.enabled ? T.fillMuted : (on ? a.role.fill : Color.clear))
                        .overlay(Capsule().strokeBorder(T.inkSub.opacity(a.toggled == false ? 0.7 : 0), lineWidth: 1.5))
                )
                .opacity(a.enabled ? 1 : 0.55)
            }
            MoreButton()
        }
        .frame(minHeight: 44)
        .padding(.vertical, 8)
    }
    @ViewBuilder func badgeText(_ b: Badge) -> some View {
        switch b {
        case .free(let n): Text("あと\(n)回").rounded(10, .bold).opacity(0.85)
        case .ad: HStack(spacing: 2) { Image(systemName: "play.rectangle.fill").font(.system(size: 9)); Text("広告を見て").rounded(10, .bold) }.opacity(0.9)
        case .none: EmptyView()
        }
    }
}

// MARK: - 案B: 面を塗らず、アイコン上・文字下（タブバー型）。段は盤より目立たせない

struct RowB: View {
    let actions: [Action]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(actions) { a in
                VStack(spacing: 3) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: a.icon).font(.system(size: 22, weight: .semibold))
                            .frame(width: 44, height: 28)
                            .background(
                                Capsule().fill(a.toggled == true ? a.role.tint.opacity(0.18) : Color.clear)
                            )
                        if case .ad = a.badge {
                            Image(systemName: "play.fill").font(.system(size: 7, weight: .black))
                                .foregroundStyle(.white).frame(width: 14, height: 14)
                                .background(Circle().fill(T.coral)).offset(x: 2, y: -4)
                        }
                    }
                    Text(label(a)).rounded(11, .bold)
                }
                .foregroundStyle(a.enabled ? a.role.tint : T.inkSub)
                .opacity(a.enabled ? 1 : 0.4)
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            VStack(spacing: 3) {
                Image(systemName: "ellipsis.circle").font(.system(size: 22, weight: .semibold)).frame(width: 44, height: 28)
                Text("その他").rounded(11, .bold)
            }
            .foregroundStyle(T.inkSub)
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: T.cornerSmall, style: .continuous).fill(T.surface).shadow(color: T.shadow, radius: 6, y: 3))
    }
    func label(_ a: Action) -> String {
        switch a.badge {
        case .free(let n): "\(a.title)・あと\(n)"
        case .ad, .none: a.title
        }
    }
}

// MARK: - 案C: 広告の出る 1 つを大きく（主役）、残りはアイコンだけの丸 48pt

struct RowC: View {
    let actions: [Action]
    var body: some View {
        let hero = actions.first { if case .none = $0.badge { return false } else { return true } } ?? actions[0]
        let rest = actions.filter { $0.id != hero.id }
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: hero.icon).font(.system(size: 18, weight: .bold))
                Text(hero.title).rounded(16, .bold)
                Spacer(minLength: 4)
                switch hero.badge {
                case .free(let n):
                    Text("あと\(n)回").rounded(12, .bold)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.55)))
                case .ad:
                    HStack(spacing: 3) { Image(systemName: "play.rectangle.fill").font(.system(size: 12)); Text("広告").rounded(12, .bold) }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.55)))
                case .none: EmptyView()
                }
            }
            .foregroundStyle(hero.enabled ? hero.role.foreground : Color.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Capsule().fill(hero.enabled ? hero.role.fill : T.fillMuted))
            ForEach(rest) { a in
                let on = a.toggled ?? true
                Image(systemName: a.icon).font(.system(size: 18, weight: .bold))
                    .foregroundStyle(!a.enabled ? Color.white : (on ? a.role.foreground : T.ink))
                    .frame(width: 48, height: 48)
                    .background(
                        Circle().fill(!a.enabled ? T.fillMuted : (on ? a.role.fill : Color.clear))
                            .overlay(Circle().strokeBorder(T.inkSub.opacity(a.toggled == false ? 0.7 : 0), lineWidth: 1.5))
                    )
                    .overlay(alignment: .topTrailing) {
                        if case .ad = a.badge {
                            Image(systemName: "play.fill").font(.system(size: 7, weight: .black))
                                .foregroundStyle(.white).frame(width: 14, height: 14)
                                .background(Circle().fill(T.coral))
                        }
                    }
                    .opacity(a.enabled ? 1 : 0.55)
            }
            MoreButton()
        }
        .frame(minHeight: 44)
        .padding(.vertical, 6)
    }
}

/// いまの「⋯」（丸 44pt・fillMuted・白）。
struct MoreButton: View {
    var body: some View {
        Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(T.fillMuted))
    }
}

@ViewBuilder func actionRow(_ style: RowStyle, _ actions: [Action], caption: String?, currentPadding: CGFloat = 8) -> some View {
    switch style {
    case .current: RowCurrent(caption: caption, verticalPadding: currentPadding)
    case .a: RowA(actions: actions)
    case .b: RowB(actions: actions)
    case .c: RowC(actions: actions)
    }
}

// MARK: - 盤の置き換え（本物の盤ではなく、段の見え方を比べるための簡略図）

struct ShogiBoard: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            let cell = s / 9
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(hex(0xF2D9A6))
                Path { p in
                    for i in 0...9 {
                        p.move(to: CGPoint(x: CGFloat(i) * cell, y: 0)); p.addLine(to: CGPoint(x: CGFloat(i) * cell, y: s))
                        p.move(to: CGPoint(x: 0, y: CGFloat(i) * cell)); p.addLine(to: CGPoint(x: s, y: CGFloat(i) * cell))
                    }
                }.stroke(hex(0x6B4A2B).opacity(0.8), lineWidth: 1)
                ForEach(Array(pieces.enumerated()), id: \.offset) { _, pc in
                    Text(pc.2).font(.system(size: cell * 0.5, weight: .bold)).foregroundStyle(hex(0x2B2634))
                        .frame(width: cell * 0.82, height: cell * 0.86)
                        .background(RoundedRectangle(cornerRadius: 3).fill(hex(0xFBE7B8)).shadow(color: .black.opacity(0.2), radius: 1, y: 1))
                        .rotationEffect(pc.3 ? .degrees(180) : .zero)
                        .position(x: (CGFloat(pc.0) + 0.5) * cell, y: (CGFloat(pc.1) + 0.5) * cell)
                }
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
    var pieces: [(Int, Int, String, Bool)] {
        var p: [(Int, Int, String, Bool)] = []
        for x in 0..<9 { p.append((x, 2, "歩", true)); p.append((x, 6, "歩", false)) }
        let back = ["香", "桂", "銀", "金", "王", "金", "銀", "桂", "香"]
        for (i, k) in back.enumerated() { p.append((i, 0, k, true)); p.append((i, 8, k == "王" ? "玉" : k, false)) }
        p.append((1, 1, "飛", true)); p.append((7, 1, "角", true)); p.append((7, 7, "飛", false)); p.append((1, 7, "角", false))
        p.removeAll { $0.0 == 6 && $0.1 == 6 }; p.append((6, 5, "歩", false))
        p.removeAll { $0.0 == 2 && $0.1 == 2 }; p.append((2, 3, "歩", true))
        return p
    }
}

struct GoBoard: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            let n = 9
            let cell = s / CGFloat(n)
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(hex(0xF2D9A6))
                Path { p in
                    for i in 0..<n {
                        let v = (CGFloat(i) + 0.5) * cell
                        p.move(to: CGPoint(x: v, y: cell / 2)); p.addLine(to: CGPoint(x: v, y: s - cell / 2))
                        p.move(to: CGPoint(x: cell / 2, y: v)); p.addLine(to: CGPoint(x: s - cell / 2, y: v))
                    }
                }.stroke(hex(0x6B4A2B).opacity(0.8), lineWidth: 1)
                ForEach(Array(stones.enumerated()), id: \.offset) { _, st in
                    Circle().fill(st.2 ? hex(0x222222) : .white)
                        .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                        .frame(width: cell * 0.9, height: cell * 0.9)
                        .position(x: (CGFloat(st.0) + 0.5) * cell, y: (CGFloat(st.1) + 0.5) * cell)
                }
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
    var stones: [(Int, Int, Bool)] {
        [(2, 2, true), (6, 2, false), (2, 6, false), (6, 6, true), (4, 4, true), (3, 4, false), (4, 3, false), (5, 4, false), (4, 5, true), (3, 3, true), (5, 5, false), (2, 4, true)]
    }
}

struct CardFace: View {
    var rank = "A"; var red = false; var faceDown = false; var w: CGFloat = 40
    var body: some View {
        let h = w * 1.4
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: w * 0.12).fill(faceDown ? hex(0x5B7FD6) : .white)
                .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
            if faceDown {
                RoundedRectangle(cornerRadius: w * 0.08).stroke(.white.opacity(0.7), lineWidth: 1.5).padding(w * 0.1)
            } else {
                Text(rank).font(.system(size: w * 0.34, weight: .bold)).foregroundStyle(red ? hex(0xD43C2C) : hex(0x2B2634)).padding(w * 0.1)
            }
        }
        .frame(width: w, height: h)
    }
}

/// ソリティア（クロンダイク）の卓。
struct SolitaireTable: View {
    var body: some View {
        GeometryReader { g in
            let cw = (g.size.width - 8 * 6 - 16) / 7
            let ch = cw * 1.4
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    CardFace(faceDown: true, w: cw)
                    CardFace(rank: "7♦", red: true, w: cw)
                    Spacer(minLength: 0)
                    ForEach(0..<4, id: \.self) { i in
                        if i == 0 { CardFace(rank: "A♠", w: cw) } else {
                            RoundedRectangle(cornerRadius: cw * 0.12).stroke(.white.opacity(0.5), lineWidth: 1.5).frame(width: cw, height: ch)
                        }
                    }
                }
                HStack(alignment: .top, spacing: 6) {
                    ForEach(0..<7, id: \.self) { col in
                        ZStack(alignment: .top) {
                            ForEach(0..<(col + 1), id: \.self) { k in
                                CardFace(rank: ["K♣", "Q♥", "J♠", "10♦", "9♣", "8♥", "7♠"][k % 7], red: k % 2 == 1, faceDown: k < col, w: cw)
                                    .offset(y: CGFloat(k) * (k < col ? ch * 0.22 : ch * 0.3))
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
        }
        .background(RoundedRectangle(cornerRadius: T.cornerSmall, style: .continuous).fill(hex(0x2E8B57)))
    }
}

/// 麻雀ソリティア（二角取り）の牌の山。
struct MahjongSolitaireBoard: View {
    let glyphs = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "東", "南", "西", "北", "白", "發", "中", "①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨"]
    var body: some View {
        GeometryReader { g in
            let cols = 8, rows = 7
            let tw = min((g.size.width - 16) / CGFloat(cols), (g.size.height - 16) / CGFloat(rows) / 1.3)
            let th = tw * 1.3
            let ox = (g.size.width - tw * CGFloat(cols)) / 2, oy = (g.size.height - th * CGFloat(rows)) / 2
            ZStack(alignment: .topLeading) {
                ForEach(0..<(cols * rows), id: \.self) { i in
                    let c = i % cols, r = i / cols
                    let skip = (r == 0 || r == rows - 1) && (c == 0 || c == cols - 1) || (r == 3 && (c == 0 || c == cols - 1))
                    if !skip {
                        ZStack {
                            RoundedRectangle(cornerRadius: 3).fill(hex(0xFFFDF7)).shadow(color: .black.opacity(0.25), radius: 1, y: 1.5)
                            Text(glyphs[(i * 7) % glyphs.count]).font(.system(size: tw * 0.5, weight: .bold))
                                .foregroundStyle([hex(0x2B2634), hex(0xD43C2C), hex(0x1F7A3A)][(i * 3) % 3])
                        }
                        .frame(width: tw - 2, height: th - 2)
                        .offset(x: ox + CGFloat(c) * tw, y: oy + CGFloat(r) * th)
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: T.cornerSmall, style: .continuous).fill(hex(0x2E8B57)))
    }
}

/// 大富豪の場（相手の手・場札・自分の手札）。
struct DaifugoTable: View {
    var body: some View {
        GeometryReader { g in
            let cw = min(44, (g.size.width - 16) / 9)
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { i in
                        VStack(spacing: 2) {
                            HStack(spacing: -cw * 0.55) { ForEach(0..<5, id: \.self) { _ in CardFace(faceDown: true, w: cw * 0.6) } }
                            Text(["CPU 1・7枚", "CPU 2・9枚", "CPU 3・4枚"][i]).rounded(10, .bold).foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
                Spacer(minLength: 0)
                VStack(spacing: 4) {
                    Text("場：8のペア").rounded(11, .bold).foregroundStyle(.white.opacity(0.85))
                    HStack(spacing: 6) { CardFace(rank: "8♠", w: cw); CardFace(rank: "8♥", red: true, w: cw) }
                }
                Spacer(minLength: 0)
                HStack(spacing: -cw * 0.45) {
                    ForEach(0..<9, id: \.self) { i in
                        CardFace(rank: ["3♦", "5♣", "9♥", "9♠", "10♦", "J♣", "Q♥", "K♠", "2♣"][i], red: i == 0 || i == 2 || i == 4 || i == 6, w: cw)
                            .offset(y: i == 2 || i == 3 ? -10 : 0)
                    }
                }
            }
            .padding(8)
        }
        .background(RoundedRectangle(cornerRadius: T.cornerSmall, style: .continuous).fill(hex(0x2E8B57)))
    }
}

/// 神経衰弱の札のグリッド（6×5。2 枚めくれてミスマッチ中）。
struct ConcentrationGrid: View {
    var body: some View {
        GeometryReader { g in
            let cols = 5, rows = 6
            let cw = min((g.size.width - CGFloat(cols - 1) * 6) / CGFloat(cols), (g.size.height - CGFloat(rows - 1) * 6) / CGFloat(rows) / 1.4)
            let gridW = cw * CGFloat(cols) + 6 * CGFloat(cols - 1)
            let gridH = cw * 1.4 * CGFloat(rows) + 6 * CGFloat(rows - 1)
            VStack(spacing: 6) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 6) {
                        ForEach(0..<cols, id: \.self) { c in
                            let i = r * cols + c
                            if i == 7 { CardFace(rank: "🍎", w: cw) }
                            else if i == 18 { CardFace(rank: "🍇", w: cw) }
                            else if i == 3 || i == 12 { Color.clear.frame(width: cw, height: cw * 1.4) }
                            else { CardFace(faceDown: true, w: cw) }
                        }
                    }
                }
            }
            .frame(width: gridW, height: gridH)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// ナンプレの盤＋数字キーパッド。
struct SudokuBoard: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            let cell = s / 9
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(.white)
                Path { p in
                    for i in 0...9 where i % 3 != 0 {
                        p.move(to: CGPoint(x: CGFloat(i) * cell, y: 0)); p.addLine(to: CGPoint(x: CGFloat(i) * cell, y: s))
                        p.move(to: CGPoint(x: 0, y: CGFloat(i) * cell)); p.addLine(to: CGPoint(x: s, y: CGFloat(i) * cell))
                    }
                }.stroke(T.inkSub.opacity(0.5), lineWidth: 0.8)
                Path { p in
                    for i in stride(from: 0, through: 9, by: 3) {
                        p.move(to: CGPoint(x: CGFloat(i) * cell, y: 0)); p.addLine(to: CGPoint(x: CGFloat(i) * cell, y: s))
                        p.move(to: CGPoint(x: 0, y: CGFloat(i) * cell)); p.addLine(to: CGPoint(x: s, y: CGFloat(i) * cell))
                    }
                }.stroke(T.ink, lineWidth: 2)
                // 選択中のマス
                RoundedRectangle(cornerRadius: 2).fill(T.teal.opacity(0.25)).frame(width: cell, height: cell)
                    .position(x: 4.5 * cell, y: 2.5 * cell)
                ForEach(0..<81, id: \.self) { i in
                    let v = (i * 7 + i / 9 * 3) % 10
                    if v != 0 && (i * 31) % 5 != 0 && i != 22 {
                        Text("\(v)").font(.system(size: cell * 0.55, weight: (i % 3 == 0) ? .regular : .bold))
                            .foregroundStyle((i % 3 == 0) ? T.teal : T.ink)
                            .position(x: (CGFloat(i % 9) + 0.5) * cell, y: (CGFloat(i / 9) + 0.5) * cell)
                    }
                }
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// いまのナンプレのキーパッド（2 段＋消しゴム）。
struct SudokuKeypad: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) { ForEach(1...5, id: \.self) { key("\($0)") } }
            HStack(spacing: 6) {
                ForEach(6...9, id: \.self) { key("\($0)") }
                Image(systemName: "eraser.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(T.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white).shadow(color: T.shadow, radius: 3, y: 2))
            }
        }
    }
    func key(_ s: String) -> some View {
        Text(s).rounded(20, .bold).foregroundStyle(T.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white).shadow(color: T.shadow, radius: 3, y: 2))
    }
}

/// チャリンコおじさんの場面（コースの下にバナー）。
struct RunnerScene: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [hex(0x8FD3F4), hex(0xDDF3FF)], startPoint: .top, endPoint: .bottom)
            VStack {
                Spacer()
                Rectangle().fill(hex(0x79B94A)).frame(height: 40)
                Rectangle().fill(hex(0x9A7B55)).frame(height: 14)
            }
            Ellipse().fill(.white.opacity(0.9)).frame(width: 60, height: 30).offset(x: -90, y: -70)
            Ellipse().fill(.white.opacity(0.9)).frame(width: 80, height: 34).offset(x: 90, y: -100)
            // おじさん（簡略）
            VStack(spacing: 0) {
                Circle().fill(hex(0xF2C8A0)).frame(width: 22, height: 22)
                RoundedRectangle(cornerRadius: 4).fill(hex(0x3E4E80)).frame(width: 20, height: 24)
                HStack(spacing: 6) { Circle().stroke(hex(0x2B2634), lineWidth: 3).frame(width: 18, height: 18); Circle().stroke(hex(0x2B2634), lineWidth: 3).frame(width: 18, height: 18) }
            }.offset(x: -80, y: 36)
            // 障害物
            RoundedRectangle(cornerRadius: 3).fill(hex(0x9696A2)).frame(width: 22, height: 30).offset(x: 110, y: 46)
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: T.cornerSmall, style: .continuous))
    }
}

// MARK: - 画面の骨格（ヘッダー → 帯 → 盤 → 段 → 余白 → 広告）

struct StatusBarCard<L: View, R: View>: View {
    @ViewBuilder var leading: () -> L
    @ViewBuilder var trailing: () -> R
    var body: some View {
        HStack(spacing: 8) { leading(); Spacer(minLength: 8); trailing() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(minHeight: 44)
            .popCard(corner: T.cornerSmall)
    }
}

struct TurnBadge: View {
    let title: String; let fill: Color
    var body: some View {
        Text(title).rounded(14, .bold).foregroundStyle(T.onAccent)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Capsule().fill(fill))
    }
}

/// 段と広告のあいだの余白。目印（破線と文字）を描いて、どれだけ空いているかを見せる。
struct GapMarker: View {
    let minimum: CGFloat
    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            ZStack {
                Path { p in p.move(to: CGPoint(x: g.size.width / 2, y: 1)); p.addLine(to: CGPoint(x: g.size.width / 2, y: h - 1)) }
                    .stroke(T.coral.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                if h >= 24 {
                    Text("段と広告の間隔 \(Int(h.rounded()))pt").rounded(10, .bold).foregroundStyle(T.coral)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(T.background))
                } else {
                    Text("\(Int(h.rounded()))pt").rounded(9, .bold).foregroundStyle(T.coral)
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(T.background))
                }
            }
        }
        .frame(maxHeight: .infinity)
        .frame(minHeight: minimum)
    }
}

struct Banner: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(hex(0xE6E0DA))
            HStack(spacing: 6) {
                Image(systemName: "megaphone.fill").font(.system(size: 13))
                Text("広告バナー（高さ 50pt・いまと同じ位置）").rounded(11, .bold)
            }.foregroundStyle(T.inkSub)
        }
        .frame(height: 50)
    }
}

struct NavBar: View {
    let title: String
    var body: some View {
        ZStack {
            HStack {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold)).foregroundStyle(T.coral).padding(.leading, 12)
                Spacer()
                HStack(spacing: 18) {
                    Image(systemName: "questionmark.circle")
                    Image(systemName: "plus.circle.fill")
                }.font(.system(size: 20, weight: .medium)).foregroundStyle(T.coral).padding(.trailing, 14)
            }
            Text(title).rounded(20, .bold).foregroundStyle(T.ink)
        }
        .frame(height: 44)
    }
}

struct Phone<Content: View>: View {
    let device: Device
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("9:41").rounded(15, .semibold).padding(.leading, 28)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "cellularbars"); Image(systemName: "wifi"); Image(systemName: "battery.100percent")
                }.font(.system(size: 13, weight: .semibold)).padding(.trailing, 20)
            }
            .foregroundStyle(T.ink)
            .frame(height: device.statusHeight, alignment: device.statusHeight > 30 ? .center : .bottom)
            NavBar(title: title)
            content()
                .padding(T.pad)
            if device.bottomInset > 0 {
                Capsule().fill(T.ink.opacity(0.9)).frame(width: 140, height: 5)
                    .frame(height: device.bottomInset, alignment: .center)
            }
        }
        .frame(width: device.width, height: device.height)
        .background(T.background)
        .clipShape(RoundedRectangle(cornerRadius: device.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: device.corner, style: .continuous).stroke(hex(0x2B2634), lineWidth: 3))
    }
}

// MARK: - グループごとの画面

enum Group {
    case shogi, go, solitaire, mahjongSolitaire, sudoku, daifugo, concentration, runner
}

struct Screen: View {
    let device: Device
    let group: Group
    let style: RowStyle
    let actions: [Action]
    let gapMinimum: CGFloat

    var body: some View {
        Phone(device: device, title: title) {
            VStack(spacing: 6) {
                status
                boardArea
                extraRow
                if group == .daifugo && style != .current {
                    // 大富豪は進行ボタン（出す・パス）が段の位置を占める。補助操作は投了だけなので「⋯」に残る
                    EmptyView()
                } else {
                    actionRow(style, actions, caption: caption, currentPadding: currentRowPadding)
                }
                GapMarker(minimum: gapMinimum)
                Banner()
            }
        }
    }

    var title: String {
        switch group {
        case .shogi: "将棋"
        case .go: "囲碁"
        case .solitaire: "ソリティア"
        case .mahjongSolitaire: "麻雀ソリティア"
        case .sudoku: "ナンプレ"
        case .daifugo: "大富豪"
        case .concentration: "神経衰弱"
        case .runner: "チャリンコおじさん"
        }
    }

    /// いまの「⋯」の行の上下余白（release/v1.1.10 の実値）。
    var currentRowPadding: CGFloat {
        switch group {
        case .shogi, .go: 1      // BoardGameControlMetrics.rowVerticalPadding → 行は 46pt
        case .sudoku: 4          // SudokuView: verticalPadding: 4 → 52pt
        default: 8               // GameOverflowBar の既定 → 60pt
        }
    }

    var caption: String? {
        switch group {
        case .solitaire: "3枚めくり"
        default: nil
        }
    }

    @ViewBuilder var status: some View {
        switch group {
        case .shogi, .go, .concentration:
            StatusBarCard { TurnBadge(title: "あなたの番", fill: T.fillTeal) } trailing: {
                Text(group == .go ? "黒 12 ／ 白 10" : group == .concentration ? "あなた 4 ／ CPU 3" : "24手").rounded(14, .bold).foregroundStyle(T.inkSub)
            }
        case .solitaire:
            StatusBarCard { Text("38手").rounded(14, .bold).foregroundStyle(T.ink) } trailing: { Text("04:12").rounded(14, .bold).foregroundStyle(T.inkSub) }
        case .mahjongSolitaire:
            StatusBarCard { Text("残り 52 枚").rounded(14, .bold).foregroundStyle(T.ink) } trailing: { Text("02:30").rounded(14, .bold).foregroundStyle(T.inkSub) }
        case .sudoku:
            StatusBarCard { Text("残り 31").rounded(14, .bold).foregroundStyle(T.ink) } trailing: { Text("ミス 1/3 ・ ふつう ・ 06:40").rounded(13, .bold).foregroundStyle(T.inkSub) }
        case .daifugo:
            StatusBarCard { TurnBadge(title: "あなたの番", fill: T.fillTeal) } trailing: { Text("2局目 ／ 革命なし").rounded(14, .bold).foregroundStyle(T.inkSub) }
        case .runner:
            StatusBarCard { Text("1-2 ／ 1,240 m").rounded(14, .bold).foregroundStyle(T.ink) } trailing: { Text("スピード ×1.4").rounded(14, .bold).foregroundStyle(T.inkSub) }
        }
    }

    @ViewBuilder var boardArea: some View {
        switch group {
        case .shogi:
            VStack(spacing: 4) {
                handRow("CPU の持ち駒", "歩 歩 香")
                ShogiBoard().layoutPriority(1)
                handRow("あなたの持ち駒", "角 歩")
            }.layoutPriority(1)
        case .go:
            VStack(spacing: 4) {
                handRow("CPU（白）のアゲハマ", "3")
                GoBoard().layoutPriority(1)
                handRow("あなた（黒）のアゲハマ", "5")
            }.layoutPriority(1)
        case .solitaire: SolitaireTable().layoutPriority(1)
        case .mahjongSolitaire: MahjongSolitaireBoard().layoutPriority(1)
        case .sudoku: SudokuBoard().layoutPriority(1)
        case .daifugo: DaifugoTable().layoutPriority(1)
        case .concentration: ConcentrationGrid().layoutPriority(1)
        case .runner: RunnerScene().layoutPriority(1)
        }
    }

    func handRow(_ label: String, _ pieces: String) -> some View {
        HStack {
            Text(label).rounded(11, .bold).foregroundStyle(T.inkSub)
            Spacer()
            Text(pieces).rounded(14, .bold).foregroundStyle(T.ink)
        }
        .padding(.horizontal, 10).frame(minHeight: 30)
        .popCard(corner: 8)
    }

    @ViewBuilder var extraRow: some View {
        switch group {
        case .sudoku: SudokuKeypad()
        case .daifugo:
            // いまの大富豪の操作行（パス・出す・⋯）。段の案を当てるなら、この行がそのまま段になる
            HStack(spacing: 12) {
                Text("パス").rounded(16, .bold).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 44).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(T.fillMuted))
                Text("2枚出す").rounded(16, .bold).foregroundStyle(T.onAccent).frame(maxWidth: .infinity, minHeight: 44).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(T.fillCoral))
                if style == .current {
                    Image(systemName: "ellipsis.circle").font(.system(size: 17, weight: .semibold)).foregroundStyle(T.coral).frame(width: 44, height: 44)
                } else {
                    MoreButton()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: T.cornerSmall)
        case .runner:
            if style == .current {
                HStack { Spacer(); Image(systemName: "pause.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(T.onAccent).frame(width: 34, height: 34).background(Circle().fill(T.fillCoral)) }
            } else {
                EmptyView()
            }
        default: EmptyView()
        }
    }
}

// MARK: - 出力

struct Sheet: View {
    let caption: String
    let sub: String
    let screens: [AnyView]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(caption).rounded(22, .heavy).foregroundStyle(T.ink)
            Text(sub).rounded(13, .semibold).foregroundStyle(T.inkSub).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 28) {
                ForEach(Array(screens.enumerated()), id: \.offset) { _, s in s }
            }
        }
        .padding(24)
        .frame(width: 402 + 375 + 28 + 48)
        .background(hex(0xEDE4DA))
    }
}

@MainActor
func render(_ view: some View, to url: URL) {
    let r = ImageRenderer(content: view)
    r.scale = 2
    guard let cg = r.cgImage else { fatalError("render failed: \(url.lastPathComponent)") }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote", url.lastPathComponent, cg.width, "x", cg.height)
}

@MainActor
func sheet(_ dir: URL, _ name: String, _ caption: String, _ sub: String, _ group: Group, _ style: RowStyle, _ actions: [Action], gap: CGFloat = 8) {
    let v = Sheet(caption: caption, sub: sub, screens: [
        AnyView(VStack(spacing: 8) { Screen(device: .iPhone17, group: group, style: style, actions: actions, gapMinimum: gap); Text(Device.iPhone17.name).rounded(12, .bold).foregroundStyle(T.inkSub) }),
        AnyView(VStack(spacing: 8) { Screen(device: .se, group: group, style: style, actions: actions, gapMinimum: gap); Text(Device.se.name).rounded(12, .bold).foregroundStyle(T.inkSub) }),
    ])
    render(v, to: dir.appendingPathComponent(name))
}

// 操作の並び（調査表の結果を元にしたグループ別の構成。並びは たたき台 4「戻す → 助ける → 進める → ⋯」）
let shogiActions: [Action] = [
    // 待ったは 1 局 1 回無料で、2 回目から毎回広告（使い切った状態を描く）
    Action(title: "待った", icon: "arrow.uturn.backward", role: .undo, badge: .ad),
    // ヒントは無料 3 回 → 広告で 1 回ずつ最大 5 回（無料が残っている状態を描く）
    Action(title: "ヒント", icon: "lightbulb.fill", role: .hint, badge: .free(3)),
]
let goActions: [Action] = [
    Action(title: "待った", icon: "arrow.uturn.backward", role: .undo, badge: .free(1)),
    // 囲碁にヒントは無く、代わりにパスが入る。CPU の手番は押せない（薄くする）
    Action(title: "パス", icon: "forward.fill", role: .skip),
]
let solitaireActions: [Action] = [
    // 戻すは無料 3 回 → 広告 1 本で 3 回補充
    Action(title: "戻す", icon: "arrow.uturn.backward", role: .undo, badge: .free(2)),
    // ジョーカーは手持ちが無いと押せない（薄い状態を描く。補充は手詰まりの幕だけ）
    Action(title: "ジョーカー", icon: "questionmark.app.fill", role: .declaration, enabled: false),
]
let mahjongSolitaireActions: [Action] = [
    Action(title: "戻す", icon: "arrow.uturn.backward", role: .undo),
    // ヒント・並べ替えはどちらも毎回広告
    Action(title: "ヒント", icon: "lightbulb.fill", role: .hint, badge: .ad),
    Action(title: "並べ替え", icon: "shuffle", role: .primary, badge: .ad),
]
let sudokuActions: [Action] = [
    Action(title: "戻す", icon: "arrow.uturn.backward", role: .undo),
    // メモは切り替え（オンの状態を描く）
    Action(title: "メモ", icon: "pencil.tip", role: .declaration, toggled: true),
    // ヒントは毎回広告で 1 局 3 回まで
    Action(title: "ヒント", icon: "lightbulb.fill", role: .hint, badge: .ad),
]
let concentrationActions: [Action] = [
    // 待ったはミスマッチの猶予中だけ押せる。1 局 1 回無料 → 以後は広告
    Action(title: "待った", icon: "arrow.uturn.backward", role: .undo, badge: .free(1)),
]
let runnerActions: [Action] = [
    Action(title: "一時停止", icon: "pause.fill", role: .skip),
]

MainActor.assumeIsolated {
    let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

    // 現状（比較の基準）
    sheet(dir, "00-current-shogi.png", "現状・対局系（将棋）", "待った・ヒント・投了はすべて右下の「⋯」の中。行の高さは 44 + 1×2 = 46pt（盤ゲーム 5 本）。段を 60pt にすると SE では盤がその差ぶん縮みうる", .shogi, .current, [])
    sheet(dir, "00-current-sudoku.png", "現状・入力系（ナンプレ）", "キーパッドの下に「⋯」だけ（行の高さ 44 + 4×2 = 52pt）。戻す・メモ・拡大・ヒント（広告）・諦めるは「⋯」の中", .sudoku, .current, [])

    // 対局系
    sheet(dir, "01-shogi-A.png", "案A・対局系（将棋：待った → ヒント → ⋯）", "役割の色（待った＝ティール・ヒント＝黄）で塗ったカプセルを等幅で並べ、右端に今の「⋯」。広告が要るときは「▶ 広告を見て」、無料のあいだは「あと◯回」を 2 行目に", .shogi, .a, shogiActions)
    sheet(dir, "02-shogi-B.png", "案B・対局系（将棋）", "面を塗らず、アイコン上・文字下のタブ型を白いカードに載せる。広告が要るときはアイコンの肩に ▶ の赤丸。段が盤より目立たない", .shogi, .b, shogiActions)
    sheet(dir, "03-shogi-C.png", "案C・対局系（将棋）", "回数や広告のある操作 1 つ（ここでは待った）を主役の幅にし、残りはアイコンだけの丸 48pt。押しやすさと広告の入口の目立ちを優先する代わり、ゲームごとに主役が変わる", .shogi, .c, shogiActions)
    sheet(dir, "04-go-A.png", "案A・対局系の変化形（囲碁：待った → パス → ⋯）", "囲碁にヒントは無く、代わりにパスが入る。オセロは待ったと「⋯」だけになる", .go, .a, goActions)

    // ソリティア系
    sheet(dir, "05-solitaire-A.png", "案A・ソリティア系（ソリティア：戻す → ジョーカー → ⋯）", "戻す＝無料 3 回→広告で 3 回補充。ジョーカーは手持ちが無い＝押せない状態（薄く）。「自動で上がる」と「3枚めくり」の表示は「⋯」へ", .solitaire, .a, solitaireActions)
    sheet(dir, "06-solitaire-B.png", "案B・ソリティア系（ソリティア）", "同じ構成をタブ型で。卓（緑）の下に白いカードが 1 枚増える見え方になる", .solitaire, .b, solitaireActions)
    sheet(dir, "07-mahjongsolitaire-A.png", "案A・ソリティア系の最大構成（麻雀ソリティア：戻す → ヒント → 並べ替え → ⋯）", "広告の要る操作が 2 つ並ぶ唯一のゲーム。段に 3 つ＋「⋯」で、SE でも文字が縮まないかを見る。拡大は「⋯」へ", .mahjongSolitaire, .a, mahjongSolitaireActions)
    sheet(dir, "08-mahjongsolitaire-C.png", "案C・ソリティア系の最大構成（麻雀ソリティア）", "主役はヒント（広告）。並べ替えは丸ボタンに ▶ の印だけになり、広告が出ることが読みにくい", .mahjongSolitaire, .c, mahjongSolitaireActions)

    // 入力系
    sheet(dir, "09-sudoku-A.png", "案A・入力系（ナンプレ：戻す → メモ → ヒント → ⋯）", "数字キーパッドは盤の直下に要るので、段はキーパッドの下。メモは切り替え（オン＝チェック付きで塗る）。ヒントは毎回広告・1 局 3 回", .sudoku, .a, sudokuActions)
    sheet(dir, "10-sudoku-B.png", "案B・入力系（ナンプレ）", "キーパッドの白いキーと段の白いカードが同じ見た目に揃う。メモのオンはアイコンの背に薄い色", .sudoku, .b, sudokuActions)

    // カード対戦系
    sheet(dir, "11-daifugo-current.png", "現状・カード対戦系（大富豪）", "進行の操作（パス・出す）が盤の下の行を占めていて、「⋯」には投了しか無い。ポーカー・ブラックジャック・花札・しりとり・四人打ち麻雀も同型（補助操作が無い）", .daifugo, .current, [])
    sheet(dir, "12-daifugo-A.png", "案A・カード対戦系（大富豪）", "段に入れる補助操作が無いため、今の進行ボタンの行に「⋯」の見た目だけを揃える案。段そのものは作らない", .daifugo, .a, [])
    sheet(dir, "13-concentration-A.png", "案A・カード対戦系の例外（神経衰弱：待った → ⋯）", "対戦カード系で唯一、待った（1 局 1 回無料→広告）を持つ。ミスマッチの猶予中だけ押せるので、それ以外は薄い", .concentration, .a, concentrationActions)

    // アクション系
    sheet(dir, "14-runner-current.png", "現状・アクション系（チャリンコおじさん）", "進行中の操作は右寄せの一時停止（34pt）だけ。コンティニュー（広告）はミスの幕、はじめからはヘッダー。2048・15パズル・ブロック崩し・柵越えおじさんも段に置く操作が無い", .runner, .current, [])
    sheet(dir, "15-runner-A.png", "案A・アクション系（チャリンコおじさん：一時停止 → ⋯）", "段の高さと「⋯」の位置だけ他ゲームに揃える案。一時停止 1 つを 44pt のカプセルに。広告の入口（コンティニュー）は幕のままで段には出せない", .runner, .a, runnerActions)
}
