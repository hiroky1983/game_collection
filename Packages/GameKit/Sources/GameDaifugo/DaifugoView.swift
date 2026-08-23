import SwiftUI
import Core

public struct DaifugoView: View {
    @State private var model: DaifugoModel
    private let services: GameServices
    @Environment(\.dismiss) private var dismiss
    @State private var showStartSheet = true

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: DaifugoModel(services: services))
        let hasSnapshot = services.snapshots.exists(for: "daifugo")
        _showStartSheet = State(initialValue: !hasSnapshot)
    }

    public var body: some View {
        VStack(spacing: 8) {
            statusBar
            cpuRow
            // 決着後は場も手札も空になるので、代わりに階級のリザルトを出す。
            if model.phase == .result {
                resultCard
                Spacer(minLength: 2)
            } else {
                fieldArea
                Spacer(minLength: 0)
                handArea
            }
            HowToPlayHint(.daifugo, playLog: services.playLog)
            actionArea
            RecommendationSlot(services: services, isFinished: model.phase == .result)
            BannerSlot(ads: services.ads)
        }
        .padding(Theme.pad)
        .popBackground()
        .reviewRequestPrompt(services.review)
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
                Text("大富豪")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
        }
        // 革命・8切り・階級まで含む細かいルールは3行に収まらないので「くわしいルール」へ送る（#118）。
        .howToPlay(.daifugo) { DaifugoRuleSheet() }
        .sheet(isPresented: $showStartSheet) {
            DaifugoStartSheet {
                showStartSheet = false
                model.startGame()
                Task { await model.runCPUTurnsIfNeeded() }
            }
            .interactiveDismissDisabled(true)
        }
        .task {
            // 中断から戻ったときに CPU の手番が止まったままにならないようにする。
            await model.runCPUTurnsIfNeeded()
        }
    }

    // MARK: - ステータス

    private var statusBar: some View {
        HStack(spacing: 8) {
            Label("\(max(model.gameNumber, 1))ゲーム目", systemImage: "number")
                .themeBody(13)
                .foregroundStyle(Theme.inkSub)
            if model.isRevolution {
                Text("革命中")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.coral))
            }
            Spacer()
            Text(turnLabel)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(model.isPlayerTurn ? Theme.teal : Theme.inkSub)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private var turnLabel: String {
        switch model.phase {
        case .idle:    return "開始待ち"
        case .result:  return "決着"
        case .playing: return model.isPlayerTurn ? "あなたの番" : "\(model.playerName(model.currentPlayer))の番"
        }
    }

    // MARK: - CPU

    private var cpuRow: some View {
        HStack(spacing: 8) {
            ForEach(1..<DaifugoModel.playerCount, id: \.self) { index in
                cpuCard(index)
            }
        }
    }

    private func cpuCard(_ index: Int) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(model.currentPlayer == index && model.phase == .playing ? Theme.coral : Theme.inkSub)
                Text(model.playerName(index))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            Text("残り\(model.hands[index].count)枚")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            Text(model.lastActions[index].isEmpty ? " " : model.lastActions[index])
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(model.lastActions[index].isEmpty ? Color.clear : Theme.purple))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10).padding(.horizontal, 6)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - 場

    private var fieldArea: some View {
        VStack(spacing: 6) {
            Text(model.field.isEmpty ? "場は流れています（好きな組を出せます）" : "場")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            HStack(spacing: 6) {
                if model.field.isEmpty {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.inkSub.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .frame(width: 56, height: 78)
                } else {
                    ForEach(model.field) { card in
                        DaifugoCardView(card: card, size: .large)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .popCard(corner: Theme.cornerSmall)
        // 場は「何が出ているか」が分かればよいので 1 要素にまとめる（#188）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DaifugoAccessibility.fieldLabel(model.field))
    }

    // MARK: - 手札

    private var handArea: some View {
        // 1枚ごとに引くと合法手の探索が手札の枚数ぶん走るので、ここで1回だけ求める（#190）。
        let handHint = model.handHint
        return VStack(spacing: 6) {
            HStack {
                Text("あなた（残り\(model.playerHand.count)枚）")
                    .themeBody(13)
                    .foregroundStyle(Theme.ink)
                Spacer()
                if !model.lastActions[DaifugoModel.humanIndex].isEmpty {
                    Text(model.lastActions[DaifugoModel.humanIndex])
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.teal)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(model.playerHand) { card in
                    let isSelected = model.selected.contains(card.id)
                    let hint = handHint?.state(for: card.id) ?? .none
                    DaifugoCardView(card: card, size: .small, selected: isSelected, hint: hint)
                        .offset(y: isSelected ? -6 : 0)
                        .gameAnimation(.spring(response: 0.2), value: isSelected)
                        .onTapGesture { model.toggleSelection(card) }
                        // カードは `onTapGesture` で組んでいるため、Button と違って
                        // ボタン trait も読み上げ文も自動では付かない（#188）。
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            DaifugoAccessibility.handCardLabel(card, isSelected: isSelected, hint: hint)
                        )
                        .accessibilityHint("ダブルタップで選択を切り替えます")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { model.toggleSelection(card) }
                        // CPU の手番では `toggleSelection` が何もしないので、
                        // 操作可能として案内しない（描画は素の図形なので見た目は変わらない）。
                        .disabled(!model.isPlayerTurn)
                }
            }
            hintLine(handHint)
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 手札の下に出す1行の案内（#190）。
    /// 出せない組を選んでいればその理由を、選んでいなければ「1枚も出せない」ときだけ助言を出す。
    @ViewBuilder
    private func hintLine(_ handHint: DaifugoHandHint?) -> some View {
        let message = model.selectionIssue
            ?? (handHint?.playable.isEmpty == true ? "出せる組がありません。パスしてください" : nil)
        if let message {
            HStack(spacing: 4) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(message)
                    // 受け入れ条件どおり1行に収める。文字を拡大しても高さが跳ねないよう縮めて入れる（#189）。
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(Theme.coral)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - 操作

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .playing:
            HStack(spacing: 12) {
                actionButton("パス", color: Theme.fillMuted, disabled: !model.canPass) {
                    model.pass()
                    Task { await model.runCPUTurnsIfNeeded() }
                }
                actionButton(playButtonTitle, color: Theme.coral, disabled: !model.canPlaySelection) {
                    model.playSelected()
                    Task { await model.runCPUTurnsIfNeeded() }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .result:
            actionButton("次のゲーム", color: Theme.coral) {
                model.startGame()
                Task { await model.runCPUTurnsIfNeeded() }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        }
    }

    private var playButtonTitle: String {
        model.selected.isEmpty ? "カードを選ぶ" : "\(model.selected.count)枚出す"
    }

    // MARK: - リザルト

    private var resultCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: model.playerPlace == 0 ? "crown.fill" : "flag.checkered")
                    .font(.system(size: 20))
                    .foregroundStyle(model.playerPlace == 0 ? Theme.yellow : Theme.inkSub)
                Text("あなたは \(model.playerTitle)")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(model.playerPlace == 0 ? Theme.teal : Theme.ink)
                if model.fouls.contains(DaifugoModel.humanIndex) {
                    Text("反則上がり")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.coral))
                }
                Spacer()
            }
            VStack(spacing: 4) {
                ForEach(Array(model.ranking.enumerated()), id: \.element) { place, player in
                    HStack(spacing: 8) {
                        Text(DaifugoRules.title(forPlace: place))
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 58)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(place == 0 ? Theme.yellow : Theme.fillMuted))
                        Text(model.playerName(player))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(player == DaifugoModel.humanIndex ? Theme.coral : Theme.ink)
                        if model.fouls.contains(player) {
                            Text("反則")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.coral)
                        }
                        Spacer()
                    }
                }
            }
            RecordLabel(model.recordResult)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("次のゲームは階級に応じてカードを交換します（大富豪⇔大貧民 2枚 / 富豪⇔貧民 1枚）")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.inkSub)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .popCard(corner: Theme.cornerSmall)
    }

    private func actionButton(_ title: String, color: Color, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .themeBody(14)
                // 文字を拡大すると「カードを選ぶ」「コール 20枚」等が折り返して
                // ボタンの高さが跳ねるため、折り返さずに縮めて収める（#189）。
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(disabled ? Theme.inkSub.opacity(0.3) : color,
                            in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(disabled ? Theme.inkSub : .white)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Card View

struct DaifugoCardView: View {
    enum Size {
        case small, large
        var width: CGFloat { self == .small ? 42 : 56 }
        var height: CGFloat { self == .small ? 60 : 78 }
        var rankFont: CGFloat { self == .small ? 16 : 22 }
        var suitFont: CGFloat { self == .small ? 15 : 20 }
    }

    let card: DaifugoCard
    var size: Size = .small
    var selected: Bool = false
    /// 出せる / 出せないの区別（#190）。`.none` なら素の見た目のまま。
    var hint: DaifugoCardHint = .none

    /// 出せない札は色に頼らず**明度**でも落として区別する（色覚特性の影響を受けないため）。
    private var isDimmed: Bool { hint == .unplayable && !selected }

    private var borderColor: Color {
        if selected { return Theme.coral }
        if hint == .playable { return Theme.teal }
        return Color.gray.opacity(0.2)
    }

    private var borderWidth: CGFloat {
        if selected { return 2 }
        return hint == .playable ? 1.5 : 0.5
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
                .shadow(color: selected ? Theme.coral.opacity(0.6) : .black.opacity(0.15),
                        radius: selected ? 6 : 3, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(borderColor, lineWidth: borderWidth)
                )

            if card.isJoker {
                VStack(spacing: 1) {
                    Image(systemName: "star.fill")
                        .font(.system(size: size.suitFont))
                    Text("JOKER")
                        .font(.system(size: size.rankFont * 0.42, weight: .black, design: .rounded))
                }
                .foregroundStyle(Theme.purple)
            } else {
                VStack(spacing: 0) {
                    Text(card.rankLabel)
                        .font(.system(size: size.rankFont, weight: .black, design: .rounded))
                    Text(card.suit?.symbol ?? "")
                        .font(.system(size: size.suitFont))
                }
                .foregroundStyle((card.suit?.isRed ?? false) ? Color(hex: 0xC0392B) : Color(hex: 0x1A1A1A))
            }
        }
        .frame(width: size.width, height: size.height)
        .opacity(isDimmed ? 0.4 : 1)
    }
}

// MARK: - Start Sheet

struct DaifugoStartSheet: View {
    let onStart: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ゲームの流れ")
                        .themeBody(15).foregroundStyle(Theme.inkSub)
                    ruleRow("1", "CPU3人と対戦。手札を早く出し切るほど上の階級")
                    ruleRow("2", "場と同じ枚数で、より強い組だけ出せる")
                    ruleRow("3", "出せない・出したくないときはパス")
                    ruleRow("4", "決着後は階級に応じてカードを交換して次戦へ")
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 3))

                NavigationLink {
                    DaifugoRuleSheet()
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("ルールを見る")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.inkSub)
                    }
                    .foregroundStyle(Theme.coral)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 3))
                }

                Spacer()
                Button {
                    onStart()
                } label: {
                    Text("ゲーム開始").themeBody(18).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.coral)
            }
            .padding(Theme.pad)
            .popBackground()
            .navigationTitle("大富豪")
        }
        .presentationDetents([.large])
    }

    private func ruleRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.coral))
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.ink)
            Spacer()
        }
    }
}

// MARK: - Rule Sheet

struct DaifugoRuleSheet: View {
    private let rules: [(String, String)] = [
        ("カードの強さ", "弱い ← 3 4 5 6 7 8 9 10 J Q K A 2 → 強い。ジョーカーが最強で、どのカードの代わりにもなります"),
        ("出し方", "場が空なら好きな組（1枚・ペア・3枚…）を出せます。場に組があるときは同じ枚数で、より強い組だけ出せます"),
        ("革命", "同じ数字を4枚以上まとめて出すと革命。カードの強さが上下逆になります（もう一度出すと元に戻ります）"),
        ("8切り", "8 を含む組を出すと場が流れ、そのまま続けて出せます"),
        ("反則上がり", "最後の1手が 2・8・ジョーカーだと反則。上がっても大貧民に落ちます"),
        ("階級とカード交換", "上がった順に 大富豪・富豪・貧民・大貧民。次のゲームは 大貧民→大富豪 に強い2枚、大富豪→大貧民 に弱い2枚（富豪と貧民は1枚ずつ）を渡します"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(rules, id: \.0) { rule in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(rule.0)
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.coral)
                        Text(rule.1)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2))
                }
            }
            .padding(Theme.pad)
        }
        .popBackground()
        .navigationTitle("ルール")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
