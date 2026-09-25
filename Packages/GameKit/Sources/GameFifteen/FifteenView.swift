import SwiftUI
import Core

/// 15 パズルのプレイ画面。タイルをタップして空白へスライドする。
public struct FifteenView: View {
    private let services: GameServices
    @State private var model: FifteenModel
    @State private var showConfirmReset = false

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: FifteenModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 14) {
            header
            boardView
            // 初回だけ出す 1 行（以降は `?` ボタンからいつでも読める）。
            HowToPlayHint(.fifteen, playLog: services.playLog)
            RecommendationArea(services: services, isFinished: model.isSolved)
            Spacer()
            BannerSlot(ads: services.ads)
        }
        .padding()
        .gameChrome(title: "15パズル", review: services.review) {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if model.hasProgressToLose {
                        showConfirmReset = true
                    } else {
                        withGameAnimation { model.newGame() }
                    }
                } label: {
                    Label("リセット", systemImage: "arrow.clockwise")
                }
            }
        }
        .howToPlay(.fifteen)
        .confirmationDialog("新規ゲームを始めますか？", isPresented: $showConfirmReset, titleVisibility: .visible) {
            Button("終了して新規ゲーム", role: .destructive) { withGameAnimation { model.newGame() } }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("途中で終了すると、いまの盤面と手数が失われます。")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("手数")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                Text("\(model.moves)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    private var boardView: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let n = FifteenLogic.size
            let side = (geo.size.width - spacing * CGFloat(n + 1)) / CGFloat(n)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.fillMuted)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
                // タイルは値ごとに 1 枚で、位置だけをオフセットで動かす（スライドの動きが出る）。
                ForEach(1..<FifteenLogic.cellCount, id: \.self) { value in
                    if let index = model.tiles.firstIndex(of: value) {
                        FifteenTile(value: value, side: side, isHome: index == value - 1)
                            .offset(
                                x: spacing + CGFloat(index % n) * (side + spacing),
                                y: spacing + CGFloat(index / n) * (side + spacing)
                            )
                            .onTapGesture { model.tap(at: index) }
                            .accessibilityElement()
                            .accessibilityLabel(FifteenAccessibility.cellLabel(index: index, value: value))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { withGameAnimation { model.tap(at: index) } }
                    }
                }
            }
            .gameAnimation(.easeInOut(duration: 0.12), value: model.tiles)
            .overlay {
                if model.isSolved { solvedOverlay }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var solvedOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(.black.opacity(0.55))
            VStack(spacing: 12) {
                Text("クリア！").font(.title2.bold()).foregroundStyle(.white)
                Text("\(model.moves)手で揃えました")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                RecordLabel(model.recordResult, textColor: .white.opacity(0.85))
                Button("もう一度") { withGameAnimation { model.newGame() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Fill.coral)
            }
        }
    }
}

/// 1 タイル。正しい位置にあるタイルは色を変えて、揃っていく手応えを出す。
struct FifteenTile: View {
    let value: Int
    let side: CGFloat
    let isHome: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isHome ? Theme.Fill.teal : Theme.Fill.yellow)
            .frame(width: side, height: side)
            .overlay {
                Text(verbatim: "\(value)")
                    .font(.system(size: side * 0.42, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Theme.onAccent)
            }
            .contentShape(Rectangle())
    }
}
