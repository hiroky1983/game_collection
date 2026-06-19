import SwiftUI
import Core

public struct SudokuView: View {
    @State private var model: SudokuModel
    private let services: GameServices
    @State private var showNewGame: Bool
    @State private var showCompletion = false
    @Environment(\.dismiss) private var dismiss

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: SudokuModel(services: services))
        _showNewGame = State(initialValue: !services.snapshots.exists(for: "sudoku"))
    }

    public var body: some View {
        VStack(spacing: 10) {
            statusBar
            if model.isGenerating {
                generatingView
            } else if model.hasGame {
                sudokuGrid
                numberPad
            } else {
                noGameView
            }
            Spacer(minLength: 8)
            BannerSlot(ads: services.ads)
        }
        .padding(Theme.pad)
        .popBackground()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        #endif
        .tint(Theme.purple)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Label("戻る", systemImage: "chevron.left") }
            }
            ToolbarItem(placement: .principal) {
                Text("数独")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showNewGame = true } label: {
                    Label("新規", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showNewGame) {
            SudokuNewGameSheet { difficulty in
                showNewGame = false
                Task { await model.newGame(difficulty: difficulty) }
            } onCancel: {
                showNewGame = false
            }
        }
        .overlay {
            if showCompletion { completionOverlay }
        }
        .onChange(of: model.isComplete) { _, complete in
            if complete { showCompletion = true }
        }
        .task {
            model.resumeTimerIfNeeded()
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            let labels = ["かんたん", "ふつう", "むずかしい"]
            Text(labels[max(0, min(2, model.difficulty))])
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(diffColor))

            Spacer()

            let errors = model.errorCells.count
            if errors > 0 {
                Label("\(errors)ミス", systemImage: "xmark.circle.fill")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.coral)
            }

            let t = model.elapsedSeconds
            Text(timeString(t))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.inkSub)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private var diffColor: Color {
        switch model.difficulty {
        case 0:  return Theme.teal
        case 1:  return Theme.yellow
        default: return Theme.coral
        }
    }

    private func timeString(_ s: Int) -> String {
        s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: - Generating View

    private var generatingView: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("パズルを生成中…")
                .font(Theme.body(15))
                .foregroundStyle(Theme.inkSub)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - No Game View

    private var noGameView: some View {
        VStack(spacing: 16) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.purple.opacity(0.6))
            Text("新規パズルをはじめましょう")
                .font(Theme.body(16))
                .foregroundStyle(Theme.inkSub)
            Button { showNewGame = true } label: {
                Text("スタート").font(Theme.body(16)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.purple)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sudoku Grid

    private var sudokuGrid: some View {
        GeometryReader { geo in
            let size     = geo.size.width
            let cellSize = size / 9

            let errors      = model.errorCells
            let highlighted = model.highlightedCells
            let sameDigit   = model.sameDigitCells
            let hints       = model.hintedCells
            let sel         = model.selected

            ZStack(alignment: .topLeading) {
                // ── 1. Cell backgrounds ──
                Canvas { ctx, sz in
                    let cs = sz.width / 9
                    for i in 0..<81 {
                        let r = i / 9, c = i % 9
                        let rect = CGRect(x: CGFloat(c) * cs, y: CGFloat(r) * cs,
                                         width: cs, height: cs)
                        let bg: Color
                        if sel == i {
                            bg = Theme.purple.opacity(0.28)
                        } else if errors.contains(i) {
                            bg = Theme.coral.opacity(0.14)
                        } else if hints.contains(i) {
                            bg = Theme.teal.opacity(0.18)
                        } else if sameDigit.contains(i) {
                            bg = Theme.purple.opacity(0.12)
                        } else if highlighted.contains(i) {
                            bg = Color(hex: 0xF0E8D0).opacity(0.9)
                        } else {
                            bg = Theme.surface
                        }
                        ctx.fill(Path(rect), with: .color(bg))
                    }
                }

                // ── 2. Cell content ──
                VStack(spacing: 0) {
                    ForEach(0..<9, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<9, id: \.self) { col in
                                let idx = row * 9 + col
                                cellContent(index: idx, cellSize: cellSize)
                                    .frame(width: cellSize, height: cellSize)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.select(index: idx) }
                            }
                        }
                    }
                }

                // ── 3. Grid lines ──
                Canvas { ctx, sz in
                    let cs = sz.width / 9
                    // Thin cell lines
                    let thin = GraphicsContext.Shading.color(
                        Color(hex: 0x9A8A80).opacity(0.35))
                    for i in 0...9 {
                        let p = CGFloat(i) * cs
                        var v = Path(); v.move(to: .init(x: p, y: 0))
                                        v.addLine(to: .init(x: p, y: sz.height))
                        ctx.stroke(v, with: thin, lineWidth: 0.5)
                        var h = Path(); h.move(to: .init(x: 0, y: p))
                                        h.addLine(to: .init(x: sz.width, y: p))
                        ctx.stroke(h, with: thin, lineWidth: 0.5)
                    }
                    // Thick box lines
                    let thick = GraphicsContext.Shading.color(Theme.ink.opacity(0.8))
                    for i in [0, 3, 6, 9] {
                        let p   = CGFloat(i) * cs
                        let lw: CGFloat = (i == 0 || i == 9) ? 2 : 1.8
                        var v = Path(); v.move(to: .init(x: p, y: 0))
                                        v.addLine(to: .init(x: p, y: sz.height))
                        ctx.stroke(v, with: thick, lineWidth: lw)
                        var h = Path(); h.move(to: .init(x: 0, y: p))
                                        h.addLine(to: .init(x: sz.width, y: p))
                        ctx.stroke(h, with: thick, lineWidth: lw)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    @ViewBuilder
    private func cellContent(index: Int, cellSize: CGFloat) -> some View {
        let value    = model.board[index]
        let isGiven  = model.given[index]
        let isError  = model.errorCells.contains(index)
        let isHinted = model.hintedCells.contains(index)

        if value != 0 {
            Text("\(value)")
                .font(.system(
                    size: cellSize * 0.54,
                    weight: isGiven ? .bold : .semibold,
                    design: .rounded))
                .foregroundStyle(
                    isGiven  ? Theme.ink
                    : isError  ? Theme.coral
                    : isHinted ? Theme.teal
                    : Theme.purple)
        } else {
            let cellNotes = model.notes[index]
            if cellNotes.contains(true) {
                let ns = cellSize * 0.27
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(0..<3, id: \.self) { row in
                        GridRow {
                            ForEach(0..<3, id: \.self) { col in
                                let d = row * 3 + col + 1
                                Text(cellNotes[d - 1] ? "\(d)" : " ")
                                    .font(.system(size: ns, weight: .medium,
                                                  design: .rounded))
                                    .foregroundStyle(Theme.inkSub)
                                    .frame(maxWidth: .infinity,
                                           maxHeight: .infinity)
                            }
                        }
                    }
                }
                .padding(cellSize * 0.04)
            }
        }
    }

    // MARK: - Number Pad

    private var numberPad: some View {
        VStack(spacing: 8) {
            // Digits 1–9
            HStack(spacing: 6) {
                ForEach(1...9, id: \.self) { d in
                    digitButton(d)
                }
            }

            // Controls
            HStack(spacing: 8) {
                controlButton(
                    icon: model.noteMode ? "pencil.circle.fill" : "pencil.circle",
                    label: "メモ",
                    accent: Theme.purple,
                    active: model.noteMode
                ) { model.toggleNoteMode() }

                controlButton(
                    icon: "delete.left",
                    label: "消す",
                    accent: Theme.inkSub,
                    active: false
                ) { model.enter(digit: 0) }

                controlButton(
                    icon: "lightbulb.fill",
                    label: "ヒント\(model.remainingHints)",
                    accent: Theme.yellow,
                    active: model.canHint
                ) { Task { await model.requestHint() } }
                .disabled(!model.canHint)
            }
        }
    }

    private func digitButton(_ d: Int) -> some View {
        Button { model.enter(digit: d) } label: {
            Text("\(d)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .aspectRatio(0.85, contentMode: .fit)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                        .fill(Theme.surface)
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2))
        }
        .buttonStyle(.plain)
    }

    private func controlButton(
        icon: String, label: String, accent: Color,
        active: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(Theme.body(13))
            .foregroundStyle(active ? accent : Theme.inkSub)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(active ? accent.opacity(0.14) : Theme.surface)
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Completion Overlay

    private var completionOverlay: some View {
        ZStack {
            Color.black.opacity(0.42).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("🎉")
                    .font(.system(size: 56))
                Text("クリア！")
                    .font(Theme.title(28))
                    .foregroundStyle(Theme.ink)
                Label(timeString(model.elapsedSeconds), systemImage: "clock.fill")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.teal)
                Button {
                    showCompletion = false
                    showNewGame    = true
                } label: {
                    Text("次のパズル")
                        .font(Theme.body(18))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.purple, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Button { showCompletion = false } label: {
                    Text("閉じる")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.inkSub)
                }
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
            .padding(.horizontal, 28)
        }
    }
}

// MARK: - New Game Sheet

struct SudokuNewGameSheet: View {
    let onStart: (Int) -> Void
    let onCancel: () -> Void
    @State private var difficulty = 1

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                section("難易度") {
                    VStack(spacing: 10) {
                        chooser(title: "かんたん",   subtitle: "30〜35マス空き",
                                selected: difficulty == 0, accent: Theme.teal)   { difficulty = 0 }
                        chooser(title: "ふつう",     subtitle: "40〜45マス空き",
                                selected: difficulty == 1, accent: Theme.yellow) { difficulty = 1 }
                        chooser(title: "むずかしい", subtitle: "46〜50マス空き",
                                selected: difficulty == 2, accent: Theme.coral)  { difficulty = 2 }
                    }
                }
                Spacer()
                Button { onStart(difficulty) } label: {
                    Text("スタート").font(Theme.body(18)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.purple)
            }
            .padding(Theme.pad)
            .popBackground()
            .navigationTitle("新規パズル")
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
                         selected: Bool, accent: Color,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.body(17))
                        .foregroundStyle(selected ? .white : Theme.ink)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(selected ? .white.opacity(0.85) : Theme.inkSub)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(selected ? accent : Theme.surface)
                    .shadow(color: .black.opacity(selected ? 0.15 : 0.06), radius: 6, y: 3))
        }
        .buttonStyle(.plain)
    }
}
