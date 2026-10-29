import SwiftUI
import Core

/// ハノイの塔のプレイ画面（#2003）。柱をタップして取り、別の柱をタップして置く。
public struct HanoiView: View {
    private let services: GameServices
    @State private var model: HanoiModel
    /// 最後に選んだ円盤の枚数（次に開いたときの初期値）。
    @AppStorage("hanoiDisks") private var preferredDisks = HanoiLogic.defaultDisks
    @State private var showConfirmReset = false
    /// 枚数の切り替えで、確認のあとに始める枚数。
    @State private var pendingDisks: Int?

    public init(services: GameServices) {
        self.services = services
        let saved = UserDefaults.standard.object(forKey: "hanoiDisks") as? Int
        _model = State(initialValue: HanoiModel(services: services, disks: saved ?? HanoiLogic.defaultDisks))
    }

    public var body: some View {
        VStack(spacing: 12) {
            header
            diskPicker
            // 盤は残りの高さを Spacer と山分けしない（操作の段が増えた分だけ盤が縮むのを防ぐ）。
            board
                .gameClearCard(isPresented: model.isSolved, title: clearTitle, details: clearDetails)
                .layoutPriority(1)
            messageLine
            // 初回だけ出す 1 行（以降は `?` ボタンからいつでも読める）。
            HowToPlayHint(.hanoi, playLog: services.playLog)
            RecommendationArea(services: services, isFinished: model.isSolved)
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .padding()
        .gameChrome(title: tr("ハノイの塔"), review: services.review,
                    newGame: GameChromeNewGame(.solo) { requestNewGame(disks: nil) })
        .howToPlay(HowToPlayGuide.hanoi.illustrated(HanoiHowToFigures.items))
        .dialogs { anchor in
            anchor.confirmationDialog(tr("新規ゲームを始めますか？"), isPresented: $showConfirmReset, titleVisibility: .visible) {
                Button(tr("終了して新規ゲーム"), role: .destructive) { startNewGame(disks: pendingDisks) }
                Button(tr("キャンセル"), role: .cancel) { pendingDisks = nil }
            } message: {
                Text(tr("途中で終了すると、いまの盤面と手数が失われます。"))
            }
        }
        // 同じ理由が続いても毎回読み上げる（`rejection` の値は変わらないので、断った回数の変化で拾う）。
        .onChange(of: model.rejectionCount) { _, _ in
            guard let reason = model.rejection else { return }
            AccessibilityNotification.Announcement(HanoiAccessibility.message(for: reason)).post()
        }
        // 画面を離れたら・背面に回ったら計時を止め、戻ったら再開する（#375・#1734。`gameTimerLifecycle`・#1857）。
        .gameTimerLifecycle(
            pause: { model.pauseTimer() },
            resume: { model.resumeTimerIfNeeded() }
        )
        .task { model.resumeTimerIfNeeded() }
    }

    // MARK: - 上の段

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("手数"))
                    .scaledFont(12, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.inkSubText)
                Text("\(model.moves)")
                    .scaledFont(30, weight: .heavy, design: .rounded, maxScale: 1.2).monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            Text(tr("最少 %lld手", model.minimumMoves))
                .scaledFont(13, weight: .bold, design: .rounded)
                .foregroundStyle(Theme.inkSubText)
            Spacer()
            GameClockLabel(RecordFormat.time(model.elapsedSeconds), elapsedSeconds: model.elapsedSeconds)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
        .accessibilityElement(children: .combine)
    }

    /// 円盤の枚数（難易度）。押すとその枚数で始め直す（途中なら確認を挟む）。
    private var diskPicker: some View {
        HStack(spacing: 6) {
            Text(tr("円盤"))
                .scaledFont(13, weight: .bold, design: .rounded)
                .foregroundStyle(Theme.inkSubText)
            ForEach(Array(HanoiLogic.diskRange), id: \.self) { count in
                let isCurrent = count == model.disks
                Button {
                    guard !isCurrent else { return }
                    requestNewGame(disks: count)
                } label: {
                    Text(verbatim: "\(count)")
                        .scaledFont(17, weight: .heavy, design: .rounded, maxScale: 1.3)
                        .foregroundStyle(isCurrent ? Theme.onAccent : Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                                .fill(isCurrent ? Theme.Fill.teal : Theme.fillMuted)
                        )
                }
                .buttonStyle(.pop)
                .accessibilityLabel(tr("円盤%lld枚", count))
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
    }

    // MARK: - 盤

    private var board: some View {
        GeometryReader { geo in
            let columnWidth = geo.size.width / CGFloat(HanoiLogic.pegCount)
            // 円盤 1 枚の厚み。最大 7 枚 + 取った 1 枚の浮き + 台の余白が入る高さから決める。
            let diskHeight = min(30, (geo.size.height - 24) / CGFloat(HanoiLogic.diskRange.upperBound + 2))
            HStack(spacing: 0) {
                ForEach(0..<HanoiLogic.pegCount, id: \.self) { peg in
                    HanoiPegColumn(
                        disks: model.pegs[peg],
                        totalDisks: model.disks,
                        isSelected: model.selectedPeg == peg,
                        columnWidth: columnWidth,
                        diskHeight: diskHeight
                    )
                    .frame(width: columnWidth, height: geo.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { withGameAnimation { model.tap(peg: peg) } }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(HanoiAccessibility.pegLabel(
                        peg: peg, disks: model.pegs[peg], isSelected: model.selectedPeg == peg))
                    .accessibilityHint(model.selectedPeg == nil
                                       ? tr("いちばん上の円盤を取ります")
                                       : tr("取った円盤をここに置きます"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { withGameAnimation { model.tap(peg: peg) } }
                }
            }
            .background(alignment: .bottom) {
                // 台。
                RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous)
                    .fill(Theme.fillStrong)
                    .frame(height: 12)
                    .padding(.horizontal, 4)
            }
            .gameAnimation(.easeInOut(duration: 0.15), value: model.pegs)
            .gameAnimation(.easeOut(duration: 0.1), value: model.selectedPeg)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
        )
        .aspectRatio(1.25, contentMode: .fit)
    }

    /// 盤の下の 1 行。断った理由か、解き終えたら記録。高さは常に確保して盤が跳ねないようにする。
    private var messageLine: some View {
        ZStack {
            if model.isSolved {
                RecordLabel(model.recordResult)
            } else if let reason = model.rejection {
                Label(HanoiAccessibility.message(for: reason), systemImage: "exclamationmark.triangle.fill")
                    .scaledFont(14, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.coralText)
                    .multilineTextAlignment(.center)
                    // 読み上げは `onChange` の通知で 1 回だけ伝える。
                    .accessibilityHidden(true)
            } else {
                Text(model.selectedPeg == nil ? tr("柱をタップして円盤を取ろう") : tr("置きたい柱をタップしよう"))
                    .scaledFont(14, weight: .semibold, design: .rounded)
                    .foregroundStyle(Theme.inkSubText)
            }
        }
        .frame(minHeight: 36)
    }

    // MARK: - クリア

    private var clearTitle: String {
        model.moves == model.minimumMoves ? tr("最少手数でクリア！") : tr("クリア！")
    }

    private var clearDetails: [String] {
        [
            tr("最少 %1$lld手に対して %2$lld手", model.minimumMoves, model.moves),
            tr("タイム %@", RecordFormat.time(model.elapsedSeconds)),
        ]
    }

    // MARK: - 新規ゲーム

    /// 途中の盤面があるときだけ確認を挟む。`disks` が nil なら同じ枚数で始め直す。
    private func requestNewGame(disks: Int?) {
        if model.hasProgressToLose {
            pendingDisks = disks
            showConfirmReset = true
        } else {
            startNewGame(disks: disks)
        }
    }

    private func startNewGame(disks: Int?) {
        if let disks { preferredDisks = disks }
        pendingDisks = nil
        withGameAnimation { model.newGame(disks: disks) }
    }
}

/// 柱 1 本（棒と、積まれた円盤）。取っている円盤は棒の上に浮かせて見せる。
struct HanoiPegColumn: View {
    let disks: [Int]
    let totalDisks: Int
    let isSelected: Bool
    let columnWidth: CGFloat
    let diskHeight: CGFloat

    var body: some View {
        let resting = isSelected ? Array(disks.dropLast()) : disks
        let lifted = isSelected ? disks.last : nil
        ZStack(alignment: .bottom) {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(Theme.teal.opacity(0.14))
                    .padding(.horizontal, 3)
            }
            // 棒。
            Capsule()
                .fill(Theme.inkSub.opacity(0.45))
                .frame(width: 8, height: diskHeight * CGFloat(totalDisks + 1))
                .padding(.bottom, 12)
            VStack(spacing: 2) {
                ForEach(Array(resting.reversed()), id: \.self) { size in
                    HanoiDisk(size: size, totalDisks: totalDisks, maxWidth: columnWidth - 8, height: diskHeight)
                }
            }
            .padding(.bottom, 12)
            if let lifted {
                VStack {
                    HanoiDisk(size: lifted, totalDisks: totalDisks, maxWidth: columnWidth - 8, height: diskHeight)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 3)
                        .padding(.top, 4)
                    Spacer(minLength: 0)
                }
                .transition(.opacity)
            }
        }
    }
}

/// 円盤 1 枚。大きさは**幅と数字の両方**で見せる（色だけに頼らない）。
struct HanoiDisk: View {
    let size: Int
    let totalDisks: Int
    let maxWidth: CGFloat
    let height: CGFloat

    /// 最小の円盤は柱の幅の約 3 割、最大は柱いっぱい。
    static func width(size: Int, totalDisks: Int, maxWidth: CGFloat) -> CGFloat {
        let minWidth = maxWidth * 0.3
        guard totalDisks > 1 else { return maxWidth }
        return minWidth + (maxWidth - minWidth) * CGFloat(size - 1) / CGFloat(totalDisks - 1)
    }

    static func color(size: Int) -> Color {
        Theme.Fill.palette[(size - 1) % Theme.Fill.palette.count]
    }

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Self.color(size: size))
            .overlay {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .strokeBorder(.black.opacity(0.12), lineWidth: 1)
            }
            .frame(width: Self.width(size: size, totalDisks: totalDisks, maxWidth: maxWidth), height: height)
            .overlay {
                Text(verbatim: "\(size)")
                    .font(.system(size: height * 0.62, weight: .heavy, design: .rounded)) // fixed-size: 円盤の厚みに比例させる数字（図形のジオメトリに従う）
                    .foregroundStyle(Theme.onAccent)
            }
    }
}
