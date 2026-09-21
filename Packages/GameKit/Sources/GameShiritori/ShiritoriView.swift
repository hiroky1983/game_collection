import SwiftUI
import Core

public struct ShiritoriView: View {
    @State private var model: ShiritoriModel
    @State private var showSetup = false
    private let services: GameServices

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: ShiritoriModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 8) {
            statusBar
            if model.phase == .result {
                resultCard
                    .transition(.opacity)
            } else {
                currentArea
                    .transition(.opacity)
            }
            boardArea
            HowToPlayHint(.shiritori, playLog: services.playLog)
            actionArea
            RecommendationSlot(services: services, isFinished: model.phase == .result)
            BannerSlot(ads: services.ads)
        }
        .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
        .padding(Theme.pad)
        .gameChrome(title: "カードしりとり", review: services.review) {
            ToolbarItem(placement: .primaryAction) {
                Button { model.pause(); showSetup = true } label: {
                    Label("新規ゲーム", systemImage: "plus.circle.fill")
                }
            }
        }
        // 読んでいる間に時間を取られないよう止める。札をタップすると再開する。
        .howToPlay(.shiritori, onPresent: { model.pause() }) { ShiritoriRuleSheet() }
        .sheet(isPresented: $showSetup) {
            ShiritoriSetupSheet(quota: model.quota) { quota in
                model.startGame(quota: quota)
                showSetup = false
            } onCancel: { showSetup = false }
        }
        .task {
            // 開いた直後は難易度を選ばせる。
            if model.phase == .idle { showSetup = true }
        }
        .task(id: model.isPlayerTurn) {
            // CPU の手番。画面を離れたらこのタスクごと取り消される（非構造化の Task にすると、
            // 離脱後に手が着地して幽霊の対局記録を書く）。
            await model.runCPUTurnIfNeeded()
        }
        .task {
            // 制限時間を進める。減るのはプレイヤーの手番のあいだだけ（モデルが判定する）。
            // 裏に回っていた間の時間をまとめて取られないよう、1 回に進める幅は 0.5 秒までにする。
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                let now = ContinuousClock.now
                let parts = last.duration(to: now).components
                last = now
                let elapsed = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
                model.tick(min(elapsed, 0.5))
            }
        }
    }

    // MARK: - ステータス

    private var statusBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Label("\(max(model.gameNumber, 1))ゲーム目", systemImage: "number")
                    .themeBody(13)
                    .foregroundStyle(Theme.inkSub)
                Spacer()
                Text(model.quota.label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.Fill.purple))
            }
            timeBar
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private var timeBar: some View {
        let seconds = Int(model.timeRemaining.rounded(.up))
        let ratio = min(1, max(0, model.timeRemaining / ShiritoriTime.initial))
        let urgent = model.timeRemaining <= 10 && model.phase == .playing
        return HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(urgent ? Theme.coral : Theme.inkSub)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.inkSub.opacity(0.2))
                    Capsule().fill(urgent ? Theme.coral : Theme.teal)
                        .frame(width: proxy.size.width * ratio)
                }
            }
            .frame(height: 8)
            Text(model.isPaused ? "一時停止" : "\(seconds)びょう")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(urgent ? Theme.coral : Theme.ink)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.isPaused ? "一時停止中。札をタップすると再開します" : "のこり\(seconds)秒")
    }

    // MARK: - 場の札

    private var currentArea: some View {
        HStack(spacing: 12) {
            Group {
                if let card = model.currentCard {
                    ShiritoriCardTile(card: card, reading: model.currentReading, style: .current)
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.inkSub.opacity(0.15))
                }
            }
            .frame(width: 84, height: 96)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ShiritoriPresentation.currentLabel(card: model.currentCard, reading: model.currentReading))

            VStack(alignment: .leading, spacing: 6) {
                Text(ShiritoriPresentation.prompt(tail: model.requiredTail, isPlayerTurn: model.isPlayerTurn, phase: model.phase))
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(model.isPlayerTurn ? Theme.teal : Theme.inkSub)
                    .lineLimit(2).minimumScaleFactor(0.7)
                Text(model.lastEvent.map(ShiritoriPresentation.eventText) ?? " ")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(isMiss ? Theme.coral : Theme.inkSub)
                    .lineLimit(1).minimumScaleFactor(0.6)
                scoreLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    private var isMiss: Bool { model.lastEvent == .miss }

    private var scoreLine: some View {
        HStack(spacing: 10) {
            Label("あなた \(model.playerCount)", systemImage: "person.fill")
                .foregroundStyle(Theme.teal)
            Label("CPU \(model.cpuCount)", systemImage: "cpu")
                .foregroundStyle(Theme.coral)
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .lineLimit(1).minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("あなた\(model.playerCount)枚、CPU\(model.cpuCount)枚")
    }

    // MARK: - 盤

    private var boardArea: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: ShiritoriBoardLayout.columns),
            spacing: 6
        ) {
            ForEach(Array(model.slots.enumerated()), id: \.element.card.id) { index, slot in
                ShiritoriCardTile(card: slot.card, reading: slot.card.primaryReading,
                                  style: .board(owner: slot.owner, selectable: model.isSelectable(index)))
                    .contentShape(Rectangle())
                    .onTapGesture { select(index) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ShiritoriPresentation.slotLabel(slot))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { select(index) }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .popCard(corner: Theme.cornerSmall)
        .gameAnimation(.easeInOut(duration: 0.15), value: model.slots)
    }

    /// 札を取る。CPU の手番は `.task(id: model.isPlayerTurn)` が進める。
    private func select(_ index: Int) {
        model.select(index)
    }

    // MARK: - 操作

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .idle:
            actionButton("ゲームを始める", color: Theme.Fill.coral) { showSetup = true }
        case .playing:
            EmptyView()
        case .result:
            actionButton("もう一度", color: Theme.Fill.coral) { showSetup = true }
        }
    }

    private func actionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .themeBody(14)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(color, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Theme.onAccent)
        }
        .buttonStyle(.pop)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - リザルト

    private var resultCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: model.didPlayerWin ? "crown.fill" : "flag.checkered")
                    .font(.system(size: 20))
                    .foregroundStyle(model.didPlayerWin ? Theme.yellow : Theme.inkSub)
                Text(ShiritoriPresentation.resultTitle(ending: model.ending ?? .timeUp, didWin: model.didPlayerWin))
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(model.didPlayerWin ? Theme.teal : Theme.ink)
                    .lineLimit(2).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            Text(ShiritoriPresentation.resultDetail(player: model.playerCount, cpu: model.cpuCount, quota: model.quota,
                                                          ending: model.ending ?? .timeUp))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            RecordLabel(model.recordResult)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .popCard(corner: Theme.cornerSmall)
    }
}

// MARK: - 盤の寸法

enum ShiritoriBoardLayout {
    /// 29 枚が 6 列 × 5 行（6・6・6・6・5）に収まる。iPhone SE でも広告枠を含めて縦に収まる本数。
    static let columns = 6
}

// MARK: - 札

struct ShiritoriCardTile: View {
    enum Style: Equatable {
        case current
        case board(owner: ShiritoriOwner?, selectable: Bool)
    }

    let card: ShiritoriCard
    let reading: String
    let style: Style

    private var owner: ShiritoriOwner? {
        if case let .board(owner, _) = style { return owner }
        return nil
    }

    private var isCurrent: Bool { style == .current }

    var body: some View {
        VStack(spacing: 2) {
            ObjectCardArt(card.kind)
                .padding(isCurrent ? 6 : 3)
            Text(reading)
                .font(.system(size: isCurrent ? 14 : 10, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 2).padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CardStyle.faceFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(borderColor, lineWidth: isCurrent ? 2.5 : (owner == nil ? 1 : 2))
                )
        )
        .opacity(owner == nil ? 1 : 0.55)
        .overlay(alignment: .topTrailing) { ownerBadge }
    }

    private var borderColor: Color {
        if isCurrent { return Theme.yellow }
        switch owner {
        case .player: return Theme.teal
        case .cpu:    return Theme.coral
        case nil:     return Theme.inkSub.opacity(0.3)
        }
    }

    @ViewBuilder
    private var ownerBadge: some View {
        switch owner {
        case .player:
            Image(systemName: "person.fill").font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.onAccent).padding(3)
                .background(Circle().fill(Theme.teal)).offset(x: 3, y: -3)
        case .cpu:
            Image(systemName: "cpu").font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.onAccent).padding(3)
                .background(Circle().fill(Theme.coral)).offset(x: 3, y: -3)
        case nil:
            EmptyView()
        }
    }
}

// MARK: - 開始シート

struct ShiritoriSetupSheet: View {
    @State private var quota: ShiritoriQuota
    let onStart: (ShiritoriQuota) -> Void
    let onCancel: () -> Void

    init(quota: ShiritoriQuota,
         onStart: @escaping (ShiritoriQuota) -> Void,
         onCancel: @escaping () -> Void) {
        _quota = State(initialValue: quota)
        self.onStart = onStart
        self.onCancel = onCancel
    }

    var body: some View {
        GameSetupSheet(
            title: "新規ゲーム", startTitle: "スタート",
            onStart: { onStart(quota) }, onCancel: onCancel
        ) {
            GameSetupSection("むずかしさ") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(ShiritoriQuota.allCases, id: \.rawValue) { level in
                            GameSetupChooser(
                                title: level.label, subtitle: "",
                                selected: quota == level, accent: Theme.Fill.purple,
                                metrics: .init(title: .body(15), verticalPadding: 14, titleMinimumScale: 0.6)
                            ) { quota = level }
                        }
                    }
                    Text("時間切れのとき: " + quota.summary)
                        .themeBody(13)
                        .foregroundStyle(Theme.inkSub)
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - ルールシート

struct ShiritoriRuleSheet: View {
    private let rules: [(String, String)] = [
        ("ゲームの流れ", "CPUと交互に札を取ります。場の札の読みの最後の字から始まる読みの札を選べたら、その札を取れます。取った札が新しい場の札になります"),
        ("読みのルール", "「ー」で終わるときはひとつ前の字で受けます。「ぎ」のような濁音は、そのまま「ぎ」でも、濁点を取った「き」でも受けられます。1枚の札が別の読みを持つこともあります（うらよみ）"),
        ("制限時間", "制限時間は60秒。しりとりが成立するたびに+10秒、成立しない札を選ぶ（おてつき）と-5秒。時間はあなたの番のあいだだけ減ります"),
        ("「ん」で終わると負け", "「ん」で終わる読みの札を選んだ人は、その場で負けです"),
        ("勝ち負け", "CPUが続けられなくなったらあなたの勝ち、あなたが続けられなくなったら負けです"),
        ("ノルマ", "時間切れになったときだけ、取られた札のうち自分が取った割合がノルマを超えていれば勝ちです。やさしい=4割以上・ふつう=5割より多く・むずかしい=7割以上"),
    ]

    var body: some View {
        RuleListSheet(title: "ルール", rules: rules)
    }
}
