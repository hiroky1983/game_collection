import SwiftUI
import Core

/// 2048 のプレイ画面。スワイプで操作し、盤面変化をアニメーションする。
public struct Game2048View: View {
    @State private var model: Game2048Model
    @Environment(\.dismiss) private var dismiss

    public init(services: GameServices) {
        _model = State(initialValue: Game2048Model(services: services))
    }

    public var body: some View {
        VStack(spacing: 20) {
            header
            boardView
            Label("スワイプで動かそう", systemImage: "hand.draw.fill")
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkSub)
        }
        .padding()
        .popBackground()
        .navigationTitle("2048")
        #if os(iOS)
        .navigationBarBackButtonHidden(true)
        #endif
        .tint(Theme.coral)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                // 途中退室（盤面は自動保存され、ハブの「続きから」で再開できる）。
                Button { dismiss() } label: { Label("戻る", systemImage: "chevron.left") }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { withAnimation { model.newGame() } } label: {
                    Label("リセット", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("スコア")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                Text("\(model.score)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .popCard(corner: Theme.cornerSmall)
    }

    private var boardView: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 8
            let n = Game2048Logic.size
            let tileSize = (geo.size.width - spacing * CGFloat(n + 1)) / CGFloat(n)
            ZStack {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color(hex: 0xE7C9A8))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
                VStack(spacing: spacing) {
                    ForEach(0..<n, id: \.self) { r in
                        HStack(spacing: spacing) {
                            ForEach(0..<n, id: \.self) { c in
                                TileView(value: model.board[r][c], size: tileSize)
                            }
                        }
                    }
                }
                .padding(spacing)
            }
            .overlay {
                if model.gameOver {
                    gameOverOverlay
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.easeInOut(duration: 0.12), value: model.board)
        .contentShape(Rectangle())
        .gesture(swipeGesture)
    }

    private var gameOverOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.55))
            VStack(spacing: 12) {
                Text("ゲームオーバー").font(.title2.bold()).foregroundStyle(.white)
                Button("もう一度") { withAnimation { model.newGame() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let direction: Direction = abs(dx) > abs(dy)
                    ? (dx > 0 ? .right : .left)
                    : (dy > 0 ? .down : .up)
                withAnimation(.easeInOut(duration: 0.12)) {
                    model.move(direction)
                }
            }
    }
}

/// 1 タイル。値に応じて配色する。
struct TileView: View {
    let value: Int
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                if value > 0 {
                    Text("\(value)")
                        .font(.system(size: fontSize, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.4)
                        .foregroundStyle(value <= 4 ? Color(white: 0.35) : .white)
                        .padding(2)
                }
            }
            .id(value) // 値変化時に出現アニメを効かせる
            .transition(.scale.combined(with: .opacity))
    }

    private var fontSize: CGFloat { value >= 1024 ? size * 0.28 : size * 0.38 }

    private var color: Color {
        switch value {
        case 0:     return Color(hex: 0xD8C3A2)
        case 2:     return Color(red: 0.93, green: 0.89, blue: 0.85)
        case 4:     return Color(red: 0.93, green: 0.88, blue: 0.78)
        case 8:     return Color(red: 0.95, green: 0.69, blue: 0.47)
        case 16:    return Color(red: 0.96, green: 0.58, blue: 0.39)
        case 32:    return Color(red: 0.96, green: 0.49, blue: 0.37)
        case 64:    return Color(red: 0.96, green: 0.37, blue: 0.23)
        case 128:   return Color(red: 0.93, green: 0.81, blue: 0.45)
        case 256:   return Color(red: 0.93, green: 0.80, blue: 0.38)
        case 512:   return Color(red: 0.93, green: 0.78, blue: 0.31)
        case 1024:  return Color(red: 0.93, green: 0.77, blue: 0.25)
        default:    return Color(red: 0.93, green: 0.76, blue: 0.18)
        }
    }
}
