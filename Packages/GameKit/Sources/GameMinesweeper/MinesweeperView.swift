import SwiftUI
import Core

public struct MinesweeperView: View {
    @State private var model: MinesweeperModel
    private let services: GameServices
    @State private var showNewGame = true
    @State private var flagMode = false
    @Environment(\.dismiss) private var dismiss

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: MinesweeperModel())
    }

    public var body: some View {
        VStack(spacing: 10) {
            statusBar
            board
            Spacer(minLength: 8)
            BannerSlot(ads: services.ads)
        }
        .padding(Theme.pad)
        .popBackground()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        #endif
        .tint(Theme.coral)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Label("戻る", systemImage: "chevron.left") }
            }
            ToolbarItem(placement: .principal) {
                Text("マインスイーパー")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showNewGame = true } label: {
                    Label("新規対局", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showNewGame) {
            MinesweeperNewGameSheet { rows, cols, mines in
                model.newGame(rows: rows, cols: cols, mines: mines)
                flagMode = false
                showNewGame = false
            } onCancel: {
                showNewGame = false
            }
        }
        .overlay {
            if model.gameState == .lost {
                continueOverlay
            }
        }
    }

    // MARK: - Continue Overlay

    private var continueOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("💥")
                    .font(.system(size: 52))
                Text("地雷を踏んだ！")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)

                Button {
                    Task {
                        await services.ads.showInterstitial()
                        model.continueAfterAd()
                    }
                } label: {
                    Label("広告を見てコンティニュー", systemImage: "play.rectangle.fill")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.coral, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button { showNewGame = true } label: {
                    Text("あきらめる")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                }
                .buttonStyle(.plain)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 0) {
            Label(String(format: "%02d", max(0, model.remainingMines)),
                  systemImage: "flag.fill")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.coral)
                .frame(minWidth: 70, alignment: .leading)

            Spacer()

            Button {
                model.newGame(rows: model.rows, cols: model.cols, mines: model.totalMines)
                flagMode = false
            } label: {
                Text(stateEmoji).font(.system(size: 28))
            }

            Spacer()

            HStack(spacing: 8) {
                Label(String(format: "%03d", min(model.elapsedSeconds, 999)),
                      systemImage: "clock")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.teal)

                Button { flagMode.toggle() } label: {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(flagMode ? Theme.coral : Theme.surface)
                        )
                        .foregroundStyle(flagMode ? .white : Theme.inkSub)
                }
            }
            .frame(minWidth: 100, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    private var stateEmoji: String {
        switch model.gameState {
        case .won:  return "😎"
        case .lost: return "😵"
        default:    return "🙂"
        }
    }

    // MARK: - Board

    private var board: some View {
        GeometryReader { geo in
            let cellSize = geo.size.width / CGFloat(model.cols)
            ZStack(alignment: .topLeading) {
                Color(hex: 0x777777)
                VStack(spacing: 0) {
                    ForEach(0..<model.rows, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(0..<model.cols, id: \.self) { c in
                                cellView(row: r, col: c, size: cellSize)
                            }
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
    }

    private func cellView(row: Int, col: Int, size: CGFloat) -> some View {
        let cell  = model.cells[row][col]
        let isHit = model.hitMine.map { $0.row == row && $0.col == col } ?? false

        return ZStack {
            Rectangle()
                .fill(cellBg(cell: cell, isHit: isHit))
                .padding(0.7)
            cellContent(cell: cell, isHit: isHit, size: size)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture {
            if flagMode {
                model.toggleFlag(row: row, col: col)
            } else {
                model.tap(row: row, col: col)
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            model.toggleFlag(row: row, col: col)
        }
    }

    private func cellBg(cell: MinesweeperCell, isHit: Bool) -> Color {
        guard cell.isRevealed else { return Color(hex: 0xBDBDBD) }
        return isHit ? Theme.coral : Color(hex: 0xD8D8D8)
    }

    @ViewBuilder
    private func cellContent(cell: MinesweeperCell, isHit: Bool, size: CGFloat) -> some View {
        let iconSize = size * 0.52
        if !cell.isRevealed && cell.isFlagged {
            Image(systemName: "flag.fill")
                .resizable().scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(Theme.coral)
        } else if cell.isRevealed && cell.isMine {
            Image(systemName: isHit ? "burst.fill" : "circle.fill")
                .resizable().scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(isHit ? .white : Color(hex: 0x2A2A2A))
        } else if cell.isRevealed && cell.adjacentMines > 0 {
            Text("\(cell.adjacentMines)")
                .font(.system(size: size * 0.56, weight: .black, design: .rounded))
                .foregroundStyle(numberColor(cell.adjacentMines))
        }
    }

    private func numberColor(_ n: Int) -> Color {
        switch n {
        case 1: return Color(hex: 0x1565C0)
        case 2: return Color(hex: 0x2E7D32)
        case 3: return Theme.coral
        case 4: return Color(hex: 0x0D47A1)
        case 5: return Color(hex: 0xB71C1C)
        case 6: return Color(hex: 0x006064)
        case 7: return Theme.ink
        default: return Color(hex: 0x616161)
        }
    }
}

// MARK: - New Game Sheet

struct MinesweeperNewGameSheet: View {
    let onStart: (Int, Int, Int) -> Void
    let onCancel: () -> Void
    @State private var level = 0

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                section("難易度") {
                    HStack(spacing: 12) {
                        chooser(title: "初級", subtitle: "9×9  10地雷",
                                selected: level == 0, accent: Theme.teal)   { level = 0 }
                        chooser(title: "中級", subtitle: "12×12  25地雷",
                                selected: level == 1, accent: Theme.yellow) { level = 1 }
                        chooser(title: "上級", subtitle: "15×15  40地雷",
                                selected: level == 2, accent: Theme.coral)  { level = 2 }
                    }
                }
                Spacer()
                Button {
                    switch level {
                    case 1: onStart(12, 12, 25)
                    case 2: onStart(15, 15, 40)
                    default: onStart(9, 9, 10)
                    }
                } label: {
                    Text("スタート").font(Theme.body(18)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.coral)
            }
            .padding(Theme.pad)
            .popBackground()
            .navigationTitle("新規対局")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.body(15)).foregroundStyle(Theme.inkSub)
            content()
        }
    }

    private func chooser(title: String, subtitle: String,
                         selected: Bool, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title).font(Theme.title(22)).foregroundStyle(selected ? .white : Theme.ink)
                Text(subtitle).font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? .white.opacity(0.9) : Theme.inkSub)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(selected ? accent : Theme.surface)
                    .shadow(color: .black.opacity(selected ? 0.15 : 0.06), radius: 6, y: 3)
            )
        }
        .buttonStyle(.plain)
    }
}
