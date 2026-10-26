import Core
import SwiftUI

/// 図入りの遊び方（#2044）で盤ゲームが共通で使う小さな盤。
///
/// 本番の盤は画面の寸法に縛られるため、図には固定寸法の簡素な盤を使う。中身（駒・石・目印）は
/// 各ゲームが `content` で `(行, 列)` ごとに描く。盤の地は `Style` で選ぶ。
public struct RuleMiniBoard<Content: View>: View {
    public enum Style: Sendable {
        /// 将棋: 飴色の地に升目。
        case shogi
        /// チェス: 明暗の市松。
        case checker
        /// オセロ: 緑の地に升目。
        case green
        /// 囲碁・五目並べ: 線の交点に石を置く盤（中身は交点の上に置く）。
        case lines
    }

    private let rows: Int
    private let cols: Int
    private let cell: CGFloat
    private let style: Style
    private let content: (Int, Int) -> Content

    public init(
        rows: Int, cols: Int, cell: CGFloat = 28, style: Style,
        @ViewBuilder content: @escaping (Int, Int) -> Content
    ) {
        self.rows = rows
        self.cols = cols
        self.cell = cell
        self.style = style
        self.content = content
    }

    public var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<cols, id: \.self) { col in
                            // 空のマスでも寸法を保つ（中身が無いと frame ごと畳まれて列がずれる）。
                            ZStack { content(row, col) }
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        .frame(width: cell * CGFloat(cols), height: cell * CGFloat(rows))
        // 交点に石を置く盤は、外周の石が盤からはみ出さないよう縁を足す。
        .padding(style == .lines ? cell * 0.3 : 0)
        .background(style == .lines ? Color(hex: 0xE8C27A) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous))
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .shogi:
            Color(hex: 0xFBE6B6).overlay(grid(color: Color(hex: 0xCDA15B)))
        case .green:
            Color(hex: 0x1C6B36).overlay(grid(color: Color.black.opacity(0.35)))
        case .checker:
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<cols, id: \.self) { col in
                            Rectangle()
                                .fill((row + col).isMultiple(of: 2) ? Color(hex: 0xF0D9B5) : Color(hex: 0xB58863))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
        case .lines:
            Color(hex: 0xE8C27A).overlay(
                Path { path in
                    for row in 0..<rows {
                        let y = (CGFloat(row) + 0.5) * cell
                        path.move(to: CGPoint(x: cell / 2, y: y))
                        path.addLine(to: CGPoint(x: (CGFloat(cols) - 0.5) * cell, y: y))
                    }
                    for col in 0..<cols {
                        let x = (CGFloat(col) + 0.5) * cell
                        path.move(to: CGPoint(x: x, y: cell / 2))
                        path.addLine(to: CGPoint(x: x, y: (CGFloat(rows) - 0.5) * cell))
                    }
                }
                .stroke(Color(hex: 0x6B4A1C).opacity(0.8), lineWidth: 1)
            )
        }
    }

    private func grid(color: Color) -> some View {
        Path { path in
            for row in 0...rows {
                path.move(to: CGPoint(x: 0, y: CGFloat(row) * cell))
                path.addLine(to: CGPoint(x: CGFloat(cols) * cell, y: CGFloat(row) * cell))
            }
            for col in 0...cols {
                path.move(to: CGPoint(x: CGFloat(col) * cell, y: 0))
                path.addLine(to: CGPoint(x: CGFloat(col) * cell, y: CGFloat(rows) * cell))
            }
        }
        .stroke(color, lineWidth: 0.8)
    }
}

/// 図の中の石（碁石・五目の石・オセロの石）。
public struct RuleStone: View {
    public enum Tone: Sendable { case black, white }

    private let tone: Tone
    private let size: CGFloat

    public init(_ tone: Tone, size: CGFloat) {
        self.tone = tone
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(tone == .black
                  ? LinearGradient(colors: [Color(hex: 0x3C3C3C), Color(hex: 0x141414)], startPoint: .top, endPoint: .bottom)
                  : LinearGradient(colors: [Color(hex: 0xFFFDF2), Color(hex: 0xE4DEC6)], startPoint: .top, endPoint: .bottom))
            .overlay(Circle().stroke(Color.black.opacity(tone == .white ? 0.35 : 0.6), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            .frame(width: size * 0.82, height: size * 0.82)
    }
}

/// 盤の上の目印。`tint` はマスを塗る（動けるマス・注目のマス）、`dot` は動けるマスの点、
/// `ring` は「ここ」と示す輪、`cross` は打てない場所の ×。
public enum RuleBoardMark {
    public static func tint(_ color: Color = Theme.coral, opacity: Double = 0.45) -> some View {
        Rectangle().fill(color.opacity(opacity))
    }

    public static func dot(_ color: Color = Theme.coral) -> some View {
        Circle().fill(color.opacity(0.85)).frame(width: 9, height: 9)
    }

    public static func ring(_ color: Color = Theme.coral, size: CGFloat = 22) -> some View {
        Circle().strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: [3, 2])).frame(width: size, height: size)
    }

    public static func cross(_ color: Color = Theme.coralText) -> some View {
        Image(systemName: "xmark")
            .font(.system(size: 13, weight: .black)) // fixed-size: 図の目印（盤の寸法に従う）
            .foregroundStyle(color)
    }
}
