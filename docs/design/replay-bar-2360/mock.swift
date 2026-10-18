// 終局後の「同じ条件でもう一回」「設定を変える」（`GameReplayBar`）の結果画面モック生成器（#2360）。
// macOS 上で `swiftc -O mock.swift -o <出力先>/mockbin && <出力先>/mockbin <出力ディレクトリ>` で、
// 対象ゲームごとに「今／案1／案2／案3」を iPhone 17（402×874pt）と iPhone SE（375×667pt）で並べた PNG（@2x）と、
// 盤の一辺・カードの高さ・余りの実測値（measure.json）を書き出す。
// アプリのビルドには一切使わない使い捨て。色・角丸・丸ゴシックは Core/Theme.swift のライト側の値を写している。
// 盤・札は本物ではなく、ボタンの大きさと盤の縮み方を比べるための簡略図。
//
// 各案の定義（pt は既定の文字サイズ・iOS の実測に合わせた値）:
//   今   : カプセル 28.5pt（文字 + 上下 6pt）・押せる範囲もカプセルと同じ 28.5pt・カード = 28.5 + 8×2 = 44.5pt
//   案1  : 見た目は今のまま。ボタンの枠だけ 44pt にして `contentShape` で受け、カードの縦余白 8 → 0 で外寸 44pt（−0.5pt）
//          （`BoardGameControlCapsuleStyle`（#711）・ナンプレの `contentMinHeight: 44` と同じ組み方。枠の外へはみ出させる
//          負の padding は macOS のプローブで反応しないと実測済みのため使わない）
//   案2  : カプセル自体を 44pt（上下 13.75pt）。並びは今のまま（左に記録・右に 2 ボタン）。カード = 44 + 8×2 = 60pt（+15.5pt）
//   案3  : カプセル 44pt の 2 ボタンを等幅で全幅に。記録の行はカードの上段に移す（記録の無い画面は 60pt、ある画面は 82pt）
import AppKit
import Foundation
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
    static let fillCoral = hex(0xFF8A7E)
    static let fillTeal = hex(0x22C3BE)
    static let fillPurple = hex(0xB3A6F0)
    static let onAccent = hex(0x4A3B33)
    static let tealText = hex(0x167B78)
    static let coralText = hex(0xC93D2E)
    static let yellowText = hex(0x976400)
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
                .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
        )
    }
}

// MARK: - 端末

struct Device {
    let key: String
    let name: String
    let width: CGFloat
    let height: CGFloat
    let statusHeight: CGFloat   // ステータスバー（セーフエリア上端）
    let bottomInset: CGFloat    // ホームインジケータ
    let corner: CGFloat
    static let iPhone17 = Device(key: "ip17", name: "iPhone 17（402×874pt）", width: 402, height: 874, statusHeight: 59, bottomInset: 34, corner: 54)
    static let se = Device(key: "se3", name: "iPhone SE 第3世代（375×667pt）", width: 375, height: 667, statusHeight: 20, bottomInset: 0, corner: 0)

    /// ナビバー（44pt）と `Theme.pad`（上下 16pt）を除いた、中身に使える高さ。
    var contentHeight: CGFloat { height - statusHeight - 44 - bottomInset - T.pad * 2 }
    var contentWidth: CGFloat { width - T.pad * 2 }
}

// MARK: - 案

enum Variant: String, CaseIterable {
    case current, a1, a2, a3

    var title: String {
        switch self {
        case .current: "今"
        case .a1: "案1 見た目そのまま・押せる範囲だけ 44pt"
        case .a2: "案2 ボタン自体を 44pt・並びはそのまま"
        case .a3: "案3 44pt ボタンを等幅で全幅・記録は上段"
        }
    }
    var short: String {
        switch self {
        case .current: "今"
        case .a1: "案1"
        case .a2: "案2"
        case .a3: "案3"
        }
    }
    /// カプセルの見た目の高さ（iOS 実測: 14pt の文字 16.5 + 上下 6）。
    var capsuleHeight: CGFloat { self == .current || self == .a1 ? 28.5 : 44 }
    /// 押せる範囲の高さ。
    var hitHeight: CGFloat { self == .current ? 28.5 : 44 }
    /// 全幅・等幅にするか。
    var fillsWidth: Bool { self == .a3 }
}

/// 今の `GameReplayBar` に渡している引数（呼び出し側ごとに違う）。
struct ReplaySpec {
    /// 記録ラベル（`leading`）。nil なら `EmptyView`（記録は帯に同居している）。
    var record: String? = nil
    var newBest = false
    /// ナンプレだけ渡している `contentMinHeight: 44`（行の高さを数字パッドの 1 ボタンに揃える）。
    var contentMinHeight: CGFloat? = nil
    /// カードの縦余白（既定 8・ナンプレ 4）。
    var verticalPadding: CGFloat = 8

    /// 案ごとのカードの外寸（pt）。描画と measure.json の両方がこの値を使う。
    func cardHeight(_ v: Variant) -> CGFloat {
        let content = max(v.capsuleHeight, contentMinHeight ?? 0)
        switch v {
        case .current:
            return content + verticalPadding * 2
        case .a1:
            // 枠 44pt をボタンの中に入れ、縦余白は 0 に詰める（ナンプレのように contentMinHeight を渡している画面は今のまま）。
            return max(44, contentMinHeight ?? 0) + (contentMinHeight == nil ? 0 : verticalPadding * 2)
        case .a2:
            return max(44, contentMinHeight ?? 0) + verticalPadding * 2
        case .a3:
            return max(44, contentMinHeight ?? 0) + verticalPadding * 2 + (record == nil ? 0 : 16 + 6)
        }
    }
    func innerVerticalPadding(_ v: Variant) -> CGFloat {
        v == .a1 && contentMinHeight == nil ? 0 : verticalPadding
    }
}

// MARK: - 「もう一回」「設定を変える」のカード

/// 押せる範囲を示す印（赤 = 44pt 未満、緑 = 44pt 以上）。
struct HitArea: View {
    let height: CGFloat
    var body: some View {
        let ok = height >= 44
        let tint = ok ? T.tealText : T.coralText
        Rectangle().fill(tint.opacity(0.14))
            .overlay(Rectangle().strokeBorder(tint, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])))
            .frame(height: height)
            .allowsHitTesting(false)
    }
}

struct ReplayBar: View {
    let variant: Variant
    let spec: ReplaySpec
    /// 押せる範囲の寸法ラベルを出すか（左の列だけに出して繰り返しを避ける）。
    var showsHitLabel = true

    var body: some View {
        Group {
            if variant.fillsWidth {
                VStack(spacing: 6) {
                    if let record = spec.record {
                        recordLabel(record)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 16)
                    }
                    HStack(spacing: 8) {
                        ViewThatFits(in: .horizontal) {
                            capsule("同じ条件でもう一回", fill: T.fillCoral, fg: T.onAccent, labeled: true)
                            capsule("もう一回", fill: T.fillCoral, fg: T.onAccent, labeled: true)
                        }
                        capsule("設定を変える", fill: T.fillMuted, fg: .white, labeled: false)
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    row("同じ条件でもう一回")
                    row("もう一回")
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, spec.innerVerticalPadding(variant))
        .popCard(corner: T.cornerSmall)
    }

    private func row(_ replayTitle: String) -> some View {
        HStack(spacing: 8) {
            if let record = spec.record {
                recordLabel(record).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            capsule(replayTitle, fill: T.fillCoral, fg: T.onAccent, labeled: true)
            capsule("設定を変える", fill: T.fillMuted, fg: .white, labeled: false)
        }
        .frame(minHeight: spec.contentMinHeight)
    }

    private func recordLabel(_ text: String) -> some View {
        HStack(spacing: 8) {
            if spec.newBest {
                Text("自己ベスト更新！").rounded(11, .bold).foregroundStyle(T.onAccent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(T.fillCoral))
            }
            Text(text).rounded(13, .semibold).foregroundStyle(T.inkSub)
        }
    }

    private func capsule(_ title: String, fill: Color, fg: Color, labeled: Bool) -> some View {
        let layoutHeight = max(variant.hitHeight, spec.contentMinHeight ?? 0)
        return Text(title).rounded(14).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(fg)
            .padding(.horizontal, 12)
            .frame(maxWidth: variant.fillsWidth ? .infinity : nil)
            .frame(height: variant.capsuleHeight)
            .background(Capsule().fill(fill))
            .frame(minHeight: layoutHeight)
            .overlay(HitArea(height: variant.hitHeight))
            .overlay(alignment: variant.fillsWidth ? .bottomLeading : .topLeading) {
                if labeled && showsHitLabel {
                    Text("押せる範囲 \(fmt(variant.hitHeight))pt")
                        .rounded(8, .bold).foregroundStyle(variant.hitHeight >= 44 ? T.tealText : T.coralText)
                        .padding(.horizontal, 3).background(Capsule().fill(T.background.opacity(0.9)))
                        .fixedSize()
                        .offset(y: variant.fillsWidth ? 11 : -11)
                }
            }
    }
}

func fmt(_ v: CGFloat) -> String {
    let r = (v * 10).rounded() / 10
    return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
}

// MARK: - 共通の部品

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
    let title: String; let fill: Color; var text: Color = T.onAccent
    var body: some View {
        Text(title).rounded(14, .bold).foregroundStyle(text)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Capsule().fill(fill))
    }
}

struct ResultLabel: View {
    let text: String; var icon = "flag.checkered"; var color = T.coralText
    var body: some View {
        Label(text, systemImage: icon).rounded(16).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
    }
}

struct RecordText: View {
    let text: String; var newBest = false
    var body: some View {
        HStack(spacing: 8) {
            if newBest {
                Text("自己ベスト更新！").rounded(11, .bold).foregroundStyle(T.onAccent)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(T.fillCoral))
            }
            Text(text).rounded(13, .semibold).foregroundStyle(T.inkSub)
        }.lineLimit(1)
    }
}

/// `RecommendationCard.heightPlaceholder`（36 + 10×2 = 56pt）。カードが出ていなくても同じ高さを占める。
struct RecommendationPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: T.cornerSmall, style: .continuous)
            .strokeBorder(T.inkSub.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .overlay(Text("レコメンド／難易度の階段の枠（ひな形 56pt・出ないこともある）").rounded(9, .bold).foregroundStyle(T.inkSub.opacity(0.8)))
            .frame(height: 56)
    }
}

/// 余白。目印（破線と文字）を描いて、どれだけ空いているかを見せる。
struct GapMarker: View {
    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            ZStack {
                Path { p in p.move(to: CGPoint(x: g.size.width / 2, y: 1)); p.addLine(to: CGPoint(x: g.size.width / 2, y: h - 1)) }
                    .stroke(T.coral.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                if h >= 22 {
                    Text("広告までの余り \(fmt(h))pt").rounded(10, .bold).foregroundStyle(T.coral)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(T.background))
                } else if h >= 9 {
                    Text("\(fmt(h))pt").rounded(8, .bold).foregroundStyle(T.coral)
                        .padding(.horizontal, 3).background(Capsule().fill(T.background))
                }
            }
        }
        .frame(maxHeight: .infinity)
        .frame(minHeight: 0)
    }
}

struct Banner: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(hex(0xE6E0DA))
            HStack(spacing: 6) {
                Image(systemName: "megaphone.fill").font(.system(size: 13))
                Text("広告バナー（50pt・いまと同じ位置）").rounded(11, .bold)
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
                .frame(width: device.width, height: device.contentHeight + T.pad * 2)
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

// MARK: - 盤（簡略図）

struct ShogiBoard: View {
    let side: CGFloat
    var body: some View {
        let cell = (side - 8) / 9
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hex(0xF2D9A6))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(hex(0x8B5E34), lineWidth: 4))
            Path { p in
                for i in 0...9 {
                    p.move(to: CGPoint(x: 4 + CGFloat(i) * cell, y: 4)); p.addLine(to: CGPoint(x: 4 + CGFloat(i) * cell, y: side - 4))
                    p.move(to: CGPoint(x: 4, y: 4 + CGFloat(i) * cell)); p.addLine(to: CGPoint(x: side - 4, y: 4 + CGFloat(i) * cell))
                }
            }.stroke(hex(0x6B4A2B).opacity(0.8), lineWidth: 1)
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, pc in
                Text(pc.2).font(.system(size: cell * 0.5, weight: .bold)).foregroundStyle(hex(0x2B2634))
                    .frame(width: cell * 0.82, height: cell * 0.86)
                    .background(RoundedRectangle(cornerRadius: 3).fill(hex(0xFBE7B8)).shadow(color: .black.opacity(0.2), radius: 1, y: 1))
                    .rotationEffect(pc.3 ? .degrees(180) : .zero)
                    .position(x: 4 + (CGFloat(pc.0) + 0.5) * cell, y: 4 + (CGFloat(pc.1) + 0.5) * cell)
            }
        }
        .frame(width: side, height: side)
    }
    /// 終局（詰み）の局面らしく、玉のまわりに駒を寄せた並び。
    var pieces: [(Int, Int, String, Bool)] {
        var p: [(Int, Int, String, Bool)] = []
        for x in [0, 1, 2, 5, 7, 8] { p.append((x, 2, "歩", true)) }
        for x in [0, 1, 3, 4, 6, 7, 8] { p.append((x, 6, "歩", false)) }
        p += [(0, 0, "香", true), (8, 0, "香", true), (1, 0, "桂", true), (7, 0, "桂", true), (2, 0, "銀", true), (6, 0, "金", true),
              (4, 0, "玉", true), (7, 1, "角", true), (1, 1, "飛", true), (3, 1, "金", false), (5, 1, "銀", false), (4, 2, "龍", false),
              (0, 8, "香", false), (8, 8, "香", false), (1, 8, "桂", false), (7, 8, "桂", false), (2, 8, "銀", false), (6, 8, "銀", false),
              (3, 8, "金", false), (5, 8, "金", false), (4, 8, "王", false), (1, 7, "角", false), (5, 5, "歩", false)]
        return p
    }
}

struct ChessBoard: View {
    let side: CGFloat
    var body: some View {
        let cell = (side - 8) / 8
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hex(0xEBD9B4))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(hex(0x6E4B2A), lineWidth: 4))
            ForEach(0..<64, id: \.self) { i in
                let r = i / 8, c = i % 8
                if (r + c) % 2 == 1 {
                    Rectangle().fill(hex(0xA9784F)).frame(width: cell, height: cell)
                        .offset(x: 4 + CGFloat(c) * cell, y: 4 + CGFloat(r) * cell)
                }
            }
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, pc in
                Text(pc.2).font(.system(size: cell * 0.72))
                    .foregroundStyle(pc.3 ? .black : .white)
                    .shadow(color: .black.opacity(pc.3 ? 0 : 0.6), radius: 0.8)
                    .position(x: 4 + (CGFloat(pc.0) + 0.5) * cell, y: 4 + (CGFloat(pc.1) + 0.5) * cell)
            }
        }
        .frame(width: side, height: side)
    }
    var pieces: [(Int, Int, String, Bool)] {
        [(4, 0, "♚", true), (3, 1, "♟", true), (5, 1, "♟", true), (6, 2, "♞", true), (0, 1, "♟", true), (1, 2, "♟", true),
         (4, 2, "♕", false), (5, 3, "♗", false), (3, 6, "♙", false), (4, 6, "♙", false), (6, 6, "♙", false), (0, 6, "♙", false),
         (2, 7, "♖", false), (6, 7, "♔", false), (7, 6, "♙", false), (2, 3, "♟", true), (7, 1, "♜", true)]
    }
}

struct OthelloBoard: View {
    let side: CGFloat
    var body: some View {
        let cell = side / 8
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: T.corner, style: .continuous)
                .fill(LinearGradient(colors: [hex(0x2E9A5B), hex(0x227A47)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            Path { p in
                for i in 1..<8 {
                    p.move(to: CGPoint(x: CGFloat(i) * cell, y: 6)); p.addLine(to: CGPoint(x: CGFloat(i) * cell, y: side - 6))
                    p.move(to: CGPoint(x: 6, y: CGFloat(i) * cell)); p.addLine(to: CGPoint(x: side - 6, y: CGFloat(i) * cell))
                }
            }.stroke(Color.black.opacity(0.35), lineWidth: 1)
            ForEach(0..<64, id: \.self) { i in
                let r = i / 8, c = i % 8
                let black = ((i * 7) % 5) != 0
                Circle().fill(black ? hex(0x1A1A1A) : hex(0xF0ECD8))
                    .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                    .frame(width: cell * 0.8, height: cell * 0.8)
                    .position(x: (CGFloat(c) + 0.5) * cell, y: (CGFloat(r) + 0.5) * cell)
            }
        }
        .frame(width: side, height: side)
    }
}

struct LineBoard: View {
    let side: CGFloat
    let n: Int
    let stones: [(Int, Int, Bool)]
    var body: some View {
        let pad = side * 0.06
        let sp = (side - pad * 2) / CGFloat(n - 1)
        ZStack {
            RoundedRectangle(cornerRadius: T.corner, style: .continuous).fill(hex(0xDEB568))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
            Path { p in
                for i in 0..<n {
                    let v = pad + CGFloat(i) * sp
                    p.move(to: CGPoint(x: v, y: pad)); p.addLine(to: CGPoint(x: v, y: side - pad))
                    p.move(to: CGPoint(x: pad, y: v)); p.addLine(to: CGPoint(x: side - pad, y: v))
                }
            }.stroke(hex(0x4A3B33).opacity(0.75), lineWidth: 1)
            ForEach(Array(stones.enumerated()), id: \.offset) { _, st in
                Circle().fill(st.2 ? hex(0x18140E) : hex(0xF0E8D0))
                    .overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 0.5))
                    .frame(width: sp * 0.9, height: sp * 0.9)
                    .position(x: pad + CGFloat(st.0) * sp, y: pad + CGFloat(st.1) * sp)
            }
        }
        .frame(width: side, height: side)
    }
}

let gomokuStones: [(Int, Int, Bool)] = [
    (5, 7, true), (6, 7, true), (7, 7, true), (8, 7, true), (9, 7, true),   // 五連（黒）
    (5, 6, false), (6, 8, false), (7, 6, false), (8, 8, false), (9, 6, false), (4, 7, false), (6, 6, true), (8, 6, true), (7, 8, false), (7, 5, true),
]
let goStones: [(Int, Int, Bool)] = [
    (2, 2, true), (6, 2, false), (2, 6, false), (6, 6, true), (4, 4, true), (3, 4, false), (4, 3, false), (5, 4, false), (4, 5, true),
    (3, 3, true), (5, 5, false), (2, 4, true), (6, 4, true), (1, 3, true), (7, 5, false), (5, 2, false), (3, 6, false), (1, 6, false),
]

struct MinesBoard: View {
    let side: CGFloat
    let n = 9
    var body: some View {
        let cell = side / CGFloat(n)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: T.cornerSmall, style: .continuous).fill(hex(0xD9D2CA))
            ForEach(0..<(n * n), id: \.self) { i in
                let r = i / n, c = i % n
                let mine = [3, 11, 20, 27, 38, 45, 52, 61, 70, 77].contains(i)
                let covered = mine
                let num = (i * 7 + r) % 4
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(covered ? hex(0xBFB5AA) : hex(0xF7F1E9))
                    if covered {
                        Image(systemName: "flag.fill").font(.system(size: cell * 0.45)).foregroundStyle(T.coral)
                    } else if num > 0 {
                        Text("\(num)").font(.system(size: cell * 0.5, weight: .bold))
                            .foregroundStyle([T.ink, hex(0x2E6FD6), hex(0x2E8B57), T.coralText][num])
                    }
                }
                .frame(width: cell - 2, height: cell - 2)
                .offset(x: CGFloat(c) * cell + 1, y: CGFloat(r) * cell + 1)
            }
        }
        .frame(width: side, height: side)
    }
}

struct SudokuBoard: View {
    let side: CGFloat
    var body: some View {
        let cell = side / 9
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(.white)
            Path { p in
                for i in 0...9 where i % 3 != 0 {
                    p.move(to: CGPoint(x: CGFloat(i) * cell, y: 0)); p.addLine(to: CGPoint(x: CGFloat(i) * cell, y: side))
                    p.move(to: CGPoint(x: 0, y: CGFloat(i) * cell)); p.addLine(to: CGPoint(x: side, y: CGFloat(i) * cell))
                }
            }.stroke(T.inkSub.opacity(0.5), lineWidth: 0.8)
            Path { p in
                for i in stride(from: 0, through: 9, by: 3) {
                    p.move(to: CGPoint(x: CGFloat(i) * cell, y: 0)); p.addLine(to: CGPoint(x: CGFloat(i) * cell, y: side))
                    p.move(to: CGPoint(x: 0, y: CGFloat(i) * cell)); p.addLine(to: CGPoint(x: side, y: CGFloat(i) * cell))
                }
            }.stroke(T.ink, lineWidth: 2)
            ForEach(0..<81, id: \.self) { i in
                let r = i / 9, c = i % 9
                let v = ((r * 3 + r / 3 + c) % 9) + 1
                Text("\(v)").font(.system(size: cell * 0.55, weight: (i % 3 == 0) ? .regular : .bold))
                    .foregroundStyle((i % 3 == 0) ? T.ink : T.tealText)
                    .position(x: (CGFloat(c) + 0.5) * cell, y: (CGFloat(r) + 0.5) * cell)
            }
        }
        .frame(width: side, height: side)
    }
}

struct CardFace: View {
    var rank = "A"; var red = false; var faceDown = false; var w: CGFloat = 40; var h: CGFloat? = nil
    var body: some View {
        let hh = h ?? w * 1.4
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: w * 0.12).fill(faceDown ? hex(0x5B7FD6) : .white)
                .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
            if faceDown {
                RoundedRectangle(cornerRadius: w * 0.08).stroke(.white.opacity(0.7), lineWidth: 1.5).padding(w * 0.1)
            } else {
                Text(rank).font(.system(size: w * 0.34, weight: .bold)).foregroundStyle(red ? hex(0xD43C2C) : hex(0x2B2634)).padding(w * 0.1)
            }
        }
        .frame(width: w, height: hh)
    }
}

/// 神経衰弱の札（終局なので全部そろって表）。
struct ConcentrationGrid: View {
    var body: some View {
        GeometryReader { g in
            let cols = 5, rows = 6, spacing: CGFloat = 6
            let widthLimit = (g.size.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
            let heightLimit = (g.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            let cw = max(1, min(widthLimit, heightLimit * 0.75 / 1.3))
            let ch = max(1, min(heightLimit, cw / 0.75 * 1.3))
            let emoji = ["🍎", "🍇", "🍊", "🍓", "🍒", "🍋", "🍉", "🥝", "🍑", "🍍", "🫐", "🍈", "🥭", "🍐", "🌰"]
            VStack(spacing: spacing) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: spacing) {
                        ForEach(0..<cols, id: \.self) { c in
                            let i = r * cols + c
                            CardFace(rank: emoji[(i * 7) % emoji.count], w: cw, h: ch).opacity(0.85)
                        }
                    }
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .top)
        }
    }
}

/// カードしりとりの札の盤（6 列 × 5 行・30 枚）。`ShiritoriCardTile` の組み方（絵 + 2 + 読み 10pt、余白 3/2）を写し、
/// 絵の一辺 `art` を外から渡す（実装では `aspectRatio(1, .fit)` の絵が、幅に収まらなければ高さで縮む）。
struct ShiritoriGrid: View {
    let art: CGFloat
    let words = ["りんご", "ごりら", "らっぱ", "ぱんだ", "だるま", "まくら", "らくだ", "だいこん", "ねこ", "こま", "まり", "りす", "すいか", "かさ", "さる",
                 "るす", "すし", "しか", "かめ", "めだか", "かに", "にわとり", "りか", "からす", "すずめ", "めがね", "ねずみ", "みかん", "かき", "きつね"]
    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(0..<6, id: \.self) { c in
                        let i = r * 6 + c
                        let taken = i % 3 != 2
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 6).fill(taken ? hex(0xEDE6DF) : hex(0xFFE3A3))
                                .overlay(Text(String(words[i].prefix(1))).font(.system(size: art * 0.5, weight: .bold)).foregroundStyle(taken ? T.inkSub : T.ink))
                                .frame(width: art, height: art)
                                .padding(3)
                            Text(taken ? words[i] : " ").rounded(10, .bold).foregroundStyle(T.ink).lineLimit(1).minimumScaleFactor(0.5)
                                .frame(height: 12)
                        }
                        .padding(.horizontal, 2).padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(taken ? (i % 2 == 0 ? T.teal : T.coral) : T.inkSub.opacity(0.3), lineWidth: taken ? 2 : 1)))
                        .opacity(taken ? 0.55 : 1)
                        .overlay(alignment: .topTrailing) {
                            if taken {
                                Image(systemName: i % 2 == 0 ? "person.fill" : "cpu").font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(T.onAccent).padding(3)
                                    .background(Circle().fill(i % 2 == 0 ? T.teal : T.coral)).offset(x: 3, y: -3)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .popCard(corner: T.cornerSmall)
    }
    /// 札の絵を除いた固定ぶんの高さ: 1 札あたり 3+3+2+12+3+3 = 26 × 5 行 + 行間 6×4 + 上下 10×2。
    static let fixedHeight: CGFloat = 26 * 5 + 24 + 20
    static func height(art: CGFloat) -> CGFloat { art * 5 + fixedHeight }
}

/// オセロの終局オーバーレイ（暗幕 + 素材のカード。閉じるボタンは無い）。
struct OthelloResultOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 12) {
                VStack(spacing: 12) {
                    Image(systemName: "trophy.fill").font(.system(size: 40)).foregroundStyle(T.yellow)
                    Text("あなたの勝ち！").rounded(24, .bold).foregroundStyle(T.teal)
                    HStack(spacing: 10) {
                        Circle().fill(hex(0x1A1A1A)).frame(width: 22, height: 22)
                        Text("38").rounded(30, .black).foregroundStyle(T.ink)
                        Text("–").rounded(22).foregroundStyle(T.inkSub)
                        Text("26").rounded(30, .black).foregroundStyle(T.ink)
                        Circle().fill(hex(0xF0ECD8)).overlay(Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1)).frame(width: 22, height: 22)
                    }
                }
                RecordText(text: "通算 12勝 5敗")
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.9)))
        }
        .clipShape(RoundedRectangle(cornerRadius: T.corner))
    }
}

// MARK: - ゲームごとの画面

enum Game: String, CaseIterable {
    case shogi, chess, othello, gomoku, go, sudoku, minesweeper, concentration, shiritori

    var title: String {
        switch self {
        case .shogi: "将棋"
        case .chess: "チェス"
        case .othello: "オセロ"
        case .gomoku: "五目並べ"
        case .go: "囲碁"
        case .sudoku: "ナンプレ"
        case .minesweeper: "マインスイーパー"
        case .concentration: "神経衰弱"
        case .shiritori: "カードしりとり"
        }
    }

    /// 今の `GameReplayBar` の呼び出し方。
    var spec: ReplaySpec {
        switch self {
        case .shogi, .chess, .othello, .gomoku, .go, .shiritori: ReplaySpec()
        case .minesweeper: ReplaySpec(record: "ベスト 0:48", newBest: true)
        case .sudoku: ReplaySpec(record: "ベスト 6:40", contentMinHeight: 44, verticalPadding: 4)
        case .concentration: ReplaySpec()
        }
    }

    /// 盤の上下の並びの間隔（各 View の `VStack(spacing:)`）。
    var spacing: CGFloat {
        switch self {
        case .shogi, .chess: 4
        case .gomoku: 6
        case .concentration: 10
        default: 8
        }
    }

    /// 盤の一辺が決まる仕組みを持つ（正方形・`aspectRatio(1)` + `layoutPriority(1)`。しりとりは札の絵の一辺）か。
    var hasSquareBoard: Bool {
        switch self {
        case .concentration: false
        default: true
        }
    }
}

/// 盤の一辺・余りを、実装の `VStack` の構成から数えた結果（描画と measure.json が同じ値を使う）。
struct Metrics {
    let cardHeight: CGFloat
    /// 盤の一辺（正方形の盤だけ）。
    let boardSide: CGFloat
    /// 盤の幅の上限（これに届いていれば幅で決まっている）。
    let boardMaxWidth: CGFloat
    /// 操作エリアと広告のあいだに残る余り。
    let slack: CGFloat
    var widthLimited: Bool { boardSide >= boardMaxWidth - 0.01 }

    static func compute(_ game: Game, _ device: Device, _ variant: Variant) -> Metrics {
        let card = game.spec.cardHeight(variant)
        let H = device.contentHeight
        let W = device.contentWidth
        let s = game.spacing
        // 間隔の数は `VStack` の要素数 − 1。余りを吸う `Spacer(minLength: 0)` も要素なので、その前後にも間隔が入る。
        var fixed: CGFloat
        var maxW = W
        switch game {
        case .shogi, .chess:
            // 帯 44・持ち駒 52×2・検討ナビ 38 + 4 + カード・Spacer・広告 50。7 要素 → 間隔 6 つ。
            fixed = 44 + 52 * 2 + (38 + 4 + card) + 50 + 6 * s
        case .othello:
            // 帯 44・Spacer・盤（左右の余白を削って画面幅いっぱい）・操作エリア（カード + 8 + レコメンド枠 56）・Spacer・広告 50。6 要素 → 間隔 5 つ。
            maxW = device.width
            fixed = 44 + (card + 8 + 56) + 50 + 5 * s
        case .gomoku:
            // 帯 44・盤（左右の余白の半分まで広げる）・プレイヤー行 30・操作エリア・Spacer・広告 50。6 要素 → 間隔 5 つ。
            maxW = W + T.pad
            fixed = 44 + 30 + (card + 8 + 56) + 50 + 5 * s
        case .go:
            // 帯 44・石の行 30×2・盤・操作エリア・Spacer・広告 50。7 要素 → 間隔 6 つ。
            fixed = 44 + 30 * 2 + (card + 8 + 56) + 50 + 6 * s
        case .minesweeper:
            // 帯 44・盤・操作エリア・Spacer・広告 50。5 要素 → 間隔 4 つ。
            fixed = 44 + (card + 8 + 56) + 50 + 4 * s
        case .sudoku:
            // 操作エリアは「数字パッド 94 + 8 + 「⋯」の行 52 = 154」のひな形と終局後の構成（カード + 8 + 56）の高い方。
            fixed = 44 + max(154, card + 8 + 56) + 50 + 4 * s
        case .shiritori:
            // 帯 58（44 + 6 + 時間バー 8）・結果カード 89・札の盤・もう一回・Spacer・広告 50。6 要素 → 間隔 5 つ
            // （`RecommendationSlot` はカードが無ければ何も置かず、間隔も増えない）。
            // 札の絵（`ObjectCardArt`・`aspectRatio(1, .fit)`）が唯一の伸び縮みする要素で、幅に収まらなければ高さで縮む。
            let avail = H - (58 + 89 + card + 50 + 5 * s)
            let artByWidth = (W - 16 - 30) / 6 - 6
            let artByHeight = (avail - ShiritoriGrid.fixedHeight) / 5
            let art = min(artByWidth, artByHeight)
            return Metrics(cardHeight: card, boardSide: art, boardMaxWidth: artByWidth,
                           slack: max(0, avail - ShiritoriGrid.height(art: art)))
        case .concentration:
            fixed = 0
        }
        guard game.hasSquareBoard else {
            return Metrics(cardHeight: card, boardSide: 0, boardMaxWidth: 0, slack: 0)
        }
        let avail = H - fixed
        let side = min(maxW, avail)
        return Metrics(cardHeight: card, boardSide: side, boardMaxWidth: maxW, slack: max(0, avail - side))
    }
}

struct Screen: View {
    let game: Game
    let device: Device
    let variant: Variant
    var showsHitLabel = true

    var metrics: Metrics { Metrics.compute(game, device, variant) }

    var body: some View {
        Phone(device: device, title: game.title) {
            switch game {
            case .shogi, .chess: boardGameWithHands
            case .othello: othello
            case .gomoku: gomoku
            case .go: go
            case .minesweeper: minesweeper
            case .sudoku: sudoku
            case .concentration: concentration
            case .shiritori: shiritori
            }
        }
    }

    var replay: ReplayBar { ReplayBar(variant: variant, spec: game.spec, showsHitLabel: showsHitLabel) }

    // 将棋・チェス: 帯 → 持ち駒 → 盤 → 持ち駒 → 検討ナビ + もう一回 → 余り → 広告
    var boardGameWithHands: some View {
        let m = metrics
        return VStack(spacing: game.spacing) {
            StatusBarCard { ResultLabel(text: game == .shogi ? "あなたの勝ち（詰み）" : "あなたの勝ち（チェックメイト）") } trailing: { RecordText(text: "通算 12勝 5敗") }
            handRow(game == .shogi ? "CPU の持ち駒" : "CPU が取った駒", game == .shogi ? "歩 歩 香" : "♙ ♙ ♘")
            Group {
                if game == .shogi { ShogiBoard(side: m.boardSide) } else { ChessBoard(side: m.boardSide) }
            }
            .frame(maxWidth: .infinity)
            handRow(game == .shogi ? "あなたの持ち駒" : "あなたが取った駒", game == .shogi ? "角 歩 歩" : "♜ ♟ ♟")
            VStack(spacing: 4) {
                reviewNav
                replay
            }
            GapMarker()
            Banner()
        }
    }

    var reviewNav: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                Image(systemName: "backward.frame.fill").frame(width: 44, height: 28)
                Text("84/84手").rounded(14).monospacedDigit().foregroundStyle(T.ink)
                Image(systemName: "forward.frame.fill").frame(width: 44, height: 28).foregroundStyle(T.inkSub.opacity(0.5))
            }
            .foregroundStyle(T.ink)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16).padding(.vertical, 5)
        .popCard(corner: T.cornerSmall)
    }

    func handRow(_ label: String, _ pieces: String) -> some View {
        HStack {
            Text(label).rounded(11, .bold).foregroundStyle(T.inkSub).frame(width: 38 + 60, alignment: .leading)
            Text(pieces).rounded(16, .bold).foregroundStyle(T.ink)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 2)
        .frame(minHeight: 52)
        .popCard(corner: T.cornerSmall)
    }

    /// `GameControlArea`: 終局後は「もう一回」のカード + 8 + レコメンド枠（ひな形 56pt）。
    var controlArea: some View {
        VStack(spacing: 8) {
            replay
            RecommendationPlaceholder()
        }
    }

    var othello: some View {
        let m = metrics
        return VStack(spacing: game.spacing) {
            StatusBarCard { TurnBadge(title: "終局", fill: T.fillMuted, text: .white) } trailing: {
                HStack(spacing: 5) {
                    Circle().fill(hex(0x1A1A1A)).frame(width: 13, height: 13)
                    Text("38").rounded(15, .black).foregroundStyle(T.ink)
                    Text("–").rounded(13).foregroundStyle(T.inkSub)
                    Text("26").rounded(15, .black).foregroundStyle(T.ink)
                    Circle().fill(hex(0xF0ECD8)).overlay(Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1)).frame(width: 13, height: 13)
                }
            }
            Spacer(minLength: 0)
            OthelloBoard(side: m.boardSide)
                .overlay { OthelloResultOverlay() }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, -T.pad)
            controlArea
            GapMarker()
            Banner()
        }
    }

    var gomoku: some View {
        let m = metrics
        return VStack(spacing: game.spacing) {
            StatusBarCard { ResultLabel(text: "あなたの勝ち！") } trailing: {
                RecordText(text: "通算 8勝 2敗")
                Text("37手").rounded(13).foregroundStyle(T.inkSub)
            }
            LineBoard(side: m.boardSide, n: 15, stones: gomokuStones)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, -T.pad / 2)
            HStack(spacing: 8) {
                stoneChip(black: true, "あなた", "黒・先手", you: true)
                Spacer(minLength: 0)
                stoneChip(black: false, "CPU", "白・後手", you: false)
            }
            .padding(.horizontal, 12).frame(minHeight: 30).popCard(corner: T.cornerSmall)
            controlArea
            GapMarker()
            Banner()
        }
    }

    func stoneChip(black: Bool, _ who: String, _ side: String, you: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(black ? hex(0x18140E) : hex(0xF0E8D0)).overlay(Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1)).frame(width: 18, height: 18)
            Text(who).rounded(13, .bold).foregroundStyle(you ? T.teal : T.inkSub)
            Text(side).rounded(13, .regular).foregroundStyle(T.inkSub)
        }
    }

    func stoneRow(black: Bool, you: Bool, captured: Int) -> some View {
        HStack(spacing: 8) {
            Circle().fill(black ? hex(0x18140E) : hex(0xF0E8D0)).overlay(Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1)).frame(width: 18, height: 18)
            Text(you ? "あなた" : "CPU").rounded(13, .bold).foregroundStyle(you ? T.teal : T.inkSub)
            Text(black ? "黒・先番" : "白・後番").rounded(13, .regular).foregroundStyle(T.inkSub)
            Spacer()
            Text("取った石 \(captured)").rounded(12, .regular).foregroundStyle(T.inkSub)
        }
        .frame(minHeight: 30).padding(.horizontal, 12).popCard(corner: T.cornerSmall)
    }

    var go: some View {
        let m = metrics
        return VStack(spacing: game.spacing) {
            StatusBarCard { ResultLabel(text: "黒 3目半勝ち") } trailing: {
                RecordText(text: "通算 5勝 4敗")
                Text("112手").rounded(13).foregroundStyle(T.inkSub)
            }
            stoneRow(black: false, you: false, captured: 3)
            LineBoard(side: m.boardSide, n: 9, stones: goStones).frame(maxWidth: .infinity)
            stoneRow(black: true, you: true, captured: 5)
            controlArea
            GapMarker()
            Banner()
        }
    }

    var minesweeper: some View {
        let m = metrics
        return VStack(spacing: game.spacing) {
            StatusBarCard { ResultLabel(text: "クリア！", color: T.teal) } trailing: {
                Text("048").font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(T.ink)
            }
            MinesBoard(side: m.boardSide).frame(maxWidth: .infinity)
            controlArea
            GapMarker()
            Banner()
        }
    }

    var sudoku: some View {
        let m = metrics
        return VStack(spacing: game.spacing) {
            StatusBarCard {
                ResultLabel(text: "クリア！", color: T.teal)
                Text("ふつう").rounded(11, .bold).foregroundStyle(T.onAccent).padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(T.fillTeal))
            } trailing: {
                Text("6:40").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(T.ink)
            }
            SudokuBoard(side: m.boardSide).frame(maxWidth: .infinity)
            // 操作エリア: 数字パッドのひな形（154pt）が高さを持ち、終局後の構成はその中に上詰めで入る。
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: T.cornerSmall, style: .continuous)
                    .strokeBorder(T.purple.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(height: 154)
                    .overlay(alignment: .bottom) {
                        Text("数字パッド + 「⋯」の行のひな形 154pt（プレイ中の高さ。終局後もこの高さを確保）").rounded(8, .bold)
                            .foregroundStyle(T.purple).padding(.bottom, 4)
                    }
                controlArea
            }
            .frame(height: max(154, m.cardHeight + 8 + 56), alignment: .top)
            GapMarker()
            Banner()
        }
    }

    /// 神経衰弱: 札は盤いっぱい。結果は暗幕の上のカードで、「もう一回」もその中。盤の大きさは案で変わらない。
    var concentration: some View {
        ZStack {
            VStack(spacing: game.spacing) {
                StatusBarCard {
                    scoreChip("あなた", 8, T.fillTeal)
                } trailing: {
                    scoreChip("CPU", 7, T.fillCoral)
                }
                ConcentrationGrid()
                Banner()
            }
            Color.black.opacity(0.45).padding(-T.pad).padding(.top, -44)
            VStack(spacing: 12) {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: "trophy.fill").font(.system(size: 52)).foregroundStyle(T.yellow)
                        Text("あなたの勝ち！").rounded(26, .black).foregroundStyle(T.teal)
                    }
                    HStack(spacing: 20) {
                        VStack { Text("あなた").rounded(13).foregroundStyle(T.inkSub); Text("8").rounded(36, .heavy).foregroundStyle(T.tealText) }
                        Text("–").rounded(24, .heavy).foregroundStyle(T.inkSub)
                        VStack { Text("CPU").rounded(13).foregroundStyle(T.inkSub); Text("7").rounded(36, .heavy).foregroundStyle(T.coralText) }
                    }
                    RecordText(text: "通算 6勝 3敗")
                    replay
                }
                .padding(28)
                .popCard()
                RecommendationPlaceholder()
            }
            .padding(.horizontal, 32)
        }
    }

    func scoreChip(_ label: String, _ score: Int, _ fill: Color) -> some View {
        HStack(spacing: 6) {
            Text(label).rounded(13, .bold)
            Text("\(score)").rounded(16, .heavy)
        }
        .foregroundStyle(T.onAccent)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(fill.opacity(0.35)))
    }

    /// カードしりとり: 帯（+ 時間バー）→ 結果カード → 札の盤 → もう一回 → レコメンド枠 → 余り → 広告
    var shiritori: some View {
        VStack(spacing: game.spacing) {
            VStack(spacing: 6) {
                StatusBarCard {
                    TurnBadge(title: "終了", fill: T.fillMuted, text: .white)
                    Label("1ゲーム目", systemImage: "number").rounded(13).foregroundStyle(T.inkSub)
                } trailing: {
                    Text("10枚").rounded(12, .bold).foregroundStyle(T.onAccent).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(T.fillPurple))
                }
                HStack(spacing: 8) {
                    Image(systemName: "timer").font(.system(size: 12, weight: .bold)).foregroundStyle(T.inkSub)
                    Capsule().fill(T.inkSub.opacity(0.2)).frame(height: 8)
                    Text("0:00").rounded(12, .bold).foregroundStyle(T.inkSub).frame(minWidth: 52, alignment: .trailing)
                }
                .padding(.horizontal, 12)
            }
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill").font(.system(size: 20)).foregroundStyle(T.yellow)
                    Text("10枚そろえて勝ち！").rounded(16, .black).foregroundStyle(T.teal)
                    Spacer(minLength: 0)
                }
                Text("あなた 10枚 ／ CPU 7枚（10枚先取）").rounded(12).foregroundStyle(T.inkSub).frame(maxWidth: .infinity, alignment: .leading)
                RecordText(text: "通算 4勝 2敗").frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .popCard(corner: T.cornerSmall)
            ShiritoriGrid(art: metrics.boardSide)
            replay
            // `RecommendationSlot` はひな形を持たず、カードが出るときだけ 56pt を占める（ここでは出ていない状態）。
            GapMarker()
            Banner()
        }
    }
}

// MARK: - 出力

struct Sheet: View {
    let game: Game
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(game.title) — 終局後の画面（上: iPhone 17 / 下: iPhone SE 第3世代）").rounded(26, .heavy).foregroundStyle(T.ink)
            Text(note).rounded(13, .semibold).foregroundStyle(T.inkSub).fixedSize(horizontal: false, vertical: true)
            ForEach([Device.iPhone17, Device.se], id: \.key) { device in
                HStack(alignment: .top, spacing: 24) {
                    ForEach(Variant.allCases, id: \.rawValue) { v in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(v.title).rounded(15, .heavy).foregroundStyle(T.ink).frame(width: device.width, alignment: .leading)
                            Screen(game: game, device: device, variant: v, showsHitLabel: true)
                            Text(caption(device, v)).rounded(12, .semibold).foregroundStyle(T.inkSub)
                                .fixedSize(horizontal: false, vertical: true).frame(width: device.width, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(28)
        .frame(width: 402 * 4 + 24 * 3 + 56)
        .background(hex(0xEDE4DA))
    }

    var note: String {
        switch game {
        case .shogi, .chess:
            "盤に重なる結果カード（『盤を見る』で閉じる）は閉じた状態で描いている。検討ナビ（◀ n/N手 ▶）の下に「もう一回」の段が付く 2 段構成。\(game == .chess ? "画面の組み方は将棋と同じ（`ReviewNavBar` を共用）。" : "")盤は幅で決まるか高さで決まるかが端末で変わる（SE は高さ）。"
        case .othello:
            "結果は盤に重なる暗幕のカード（閉じるボタン無し）。盤の下は `GameControlArea` が「もう一回 + 8 + レコメンド枠 56pt」の高さを常に確保する。盤は左右の余白を削って画面幅いっぱい。"
        case .gomoku:
            "勝敗と記録は帯に同居（行を増やさない #148）。盤に重なる結果カードは閉じた状態。盤は左右の余白の半分まで広げている。"
        case .go:
            "勝敗と記録は帯に同居。盤の上下に石の行（30pt）。盤に重なる結果カードは閉じた状態。"
        case .minesweeper:
            "記録は「もう一回」の段の左端（`leading`）。盤の下の空きが大きいのは #2438（レイアウト C 候補）と同じ画面で、案2・案3 はその空きを 15.5／37.5pt 使う。初級（9×9）。"
        case .sudoku:
            "ナンプレだけ今の段が `contentMinHeight: 44`（押せる範囲は既に 44pt）・縦余白 4 で 52pt。数字パッドのひな形 154pt が盤の下の高さを持つので、案2・案3 でも盤は縮まない。クリアのカードは閉じた状態。"
        case .concentration:
            "結果は暗幕の上のカードで、「もう一回」もその中。盤（札）の大きさは案で変わらず、カードが縦に伸びるだけ。SE では今でもカードの中の幅が足りず「もう一回」側が縮む。"
        case .shiritori:
            "札の盤（30 枚）は札の絵（`aspectRatio(1)`）だけが伸び縮みし、幅に収まらないときは高さで縮む（SE は今でも高さで決まっている）。「もう一回」の段が伸びたぶん、SE では札の絵が縮む。時間切れのときはこの段の上に「広告を見て +30 秒」のボタンが 1 本増える。"
        }
    }

    func caption(_ device: Device, _ v: Variant) -> String {
        let m = Metrics.compute(game, device, v)
        let base = Metrics.compute(game, device, .current)
        var s = "カード \(fmt(m.cardHeight))pt"
        if v != .current { s += "（今 \(fmt(base.cardHeight)) → \(delta(m.cardHeight - base.cardHeight))）" }
        if game == .shiritori {
            s += " ／ 札の絵の一辺 \(fmt(m.boardSide))pt"
            if v != .current { s += "（\(delta(m.boardSide - base.boardSide))）" }
            s += m.widthLimited ? "・幅で決まる" : "・高さで決まる"
            s += " ／ 広告までの余り \(fmt(m.slack))pt"
        } else if game.hasSquareBoard {
            s += " ／ 盤の一辺 \(fmt(m.boardSide))pt"
            if v != .current { s += "（\(delta(m.boardSide - base.boardSide))）" }
            s += m.widthLimited ? "・幅で決まる" : "・高さで決まる"
            if let cells = cellCount {
                s += " ／ マス \(fmt(m.boardSide / CGFloat(cells)))pt"
            }
            s += " ／ 広告までの余り \(fmt(m.slack))pt"
        } else {
            s += " ／ 盤は変わらない（カードの中）"
        }
        return s
    }

    var cellCount: Int? {
        switch game {
        case .shogi, .sudoku, .minesweeper, .go: 9
        case .chess, .othello: 8
        case .gomoku: 15
        default: nil
        }
    }

    func delta(_ d: CGFloat) -> String {
        abs(d) < 0.05 ? "±0" : (d > 0 ? "+\(fmt(d))" : "−\(fmt(-d))")
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

MainActor.assumeIsolated {
    let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
    var measure: [String: [String: [String: Any]]] = [:]
    for (i, game) in Game.allCases.enumerated() {
        render(Sheet(game: game), to: dir.appendingPathComponent(String(format: "%02d-%@.png", i + 1, game.rawValue)))
        var perDevice: [String: [String: Any]] = [:]
        for device in [Device.iPhone17, Device.se] {
            var perVariant: [String: Any] = [:]
            for v in Variant.allCases {
                let m = Metrics.compute(game, device, v)
                var row: [String: Any] = ["card_h_pt": Double(m.cardHeight)]
                if game == .shiritori {
                    row["card_art_side_pt"] = Double(m.boardSide)
                    row["board_width_limited"] = m.widthLimited
                    row["slack_to_banner_pt"] = Double(m.slack)
                } else if game.hasSquareBoard {
                    row["board_side_pt"] = Double(m.boardSide)
                    row["board_width_limited"] = m.widthLimited
                    row["slack_to_banner_pt"] = Double(m.slack)
                }
                perVariant[v.rawValue] = row
            }
            perDevice[device.key] = perVariant
        }
        measure[game.rawValue] = perDevice
    }
    let data = try! JSONSerialization.data(withJSONObject: measure, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: dir.appendingPathComponent("measure.json"))
    print("wrote measure.json")
}
