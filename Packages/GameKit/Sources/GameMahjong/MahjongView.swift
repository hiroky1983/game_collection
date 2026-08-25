import SwiftUI
import Core
import MahjongTiles

/// 手牌の並べ方。牌を 1 列 14 枚に並べると 1 枚が 24pt 前後になり、タップ標的が 44pt に
/// 遠く届かない（#207 と同じ問題）。7 列 × 2 段にして 1 枚を大きく取る。
enum MahjongHandLayout {
    static let columns = 7
    static let spacing: CGFloat = 4
    static let tileWidth: CGFloat = 38
    static let tileHeight: CGFloat = 52
    /// タップ標的の最小の高さ（幅は列いっぱいに広げる）。
    static let minimumTapTarget: CGFloat = 44
}

public struct MahjongView: View {
    @State private var model: MahjongModel
    private let services: GameServices
    @Environment(\.dismiss) private var dismiss
    @State private var showStartSheet = true

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: MahjongModel(services: services))
        _showStartSheet = State(initialValue: !services.snapshots.exists(for: "mahjong4"))
    }

    public var body: some View {
        VStack(spacing: 6) {
            statusBar
            opponentRow
            if model.phase == .gameResult {
                gameResultCard.transition(.opacity)
                Spacer(minLength: 0)
            } else if model.phase == .handResult {
                handResultCard.transition(.opacity)
                Spacer(minLength: 0)
            } else {
                playerDiscardArea.transition(.opacity)
                Spacer(minLength: 0)
                handArea.transition(.opacity)
            }
            HowToPlayHint(.mahjong, playLog: services.playLog)
            actionArea
            RecommendationSlot(services: services, isFinished: model.phase == .gameResult)
            BannerSlot(ads: services.ads)
        }
        // 局面 → リザルトの差し替えは、入れ替わる枝ではなく残り続ける親に置く（#195）。
        .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
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
                Text("麻雀")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
        }
        // 役と点数は 3 行に収まらないので「くわしいルール」へ送る（#118）。
        .howToPlay(.mahjong) { MahjongRuleSheet() }
        .sheet(isPresented: $showStartSheet) {
            MahjongStartSheet {
                showStartSheet = false
                model.startGame()
                Task { await model.runCPUTurnsIfNeeded() }
            }
            .interactiveDismissDisabled(true)
        }
        .task {
            // 中断から戻ったときに手番が止まったままにならないようにする。
            await model.runCPUTurnsIfNeeded()
        }
        .task(id: model.turnKey) {
            await model.runCPUTurnsIfNeeded()
        }
    }

    // MARK: - ステータス

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text("東\(model.roundNumber)局")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(Theme.ink)
            if model.honba > 0 {
                Text("\(model.honba)本場")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
            }
            if model.riichiSticks > 0 {
                Label("\(model.riichiSticks)", systemImage: "flag.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.coral)
            }
            Spacer()
            if let dora = model.doraIndicators.first {
                HStack(spacing: 3) {
                    Text("ドラ")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                    MahjongTileView(tile: dora, width: 18, height: 24)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("ドラ表示牌は\(dora.displayName)")
            }
            Text("残り\(model.remainingTiles)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .popCard(corner: Theme.cornerSmall)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            MahjongAccessibility.roundLabel(
                roundNumber: model.roundNumber, honba: model.honba, remainingTiles: model.remainingTiles
            )
        )
    }

    // MARK: - 他家

    private var opponentRow: some View {
        HStack(spacing: 6) {
            ForEach(1..<MahjongModel.playerCount, id: \.self) { index in
                opponentCard(index)
            }
        }
    }

    private func opponentCard(_ index: Int) -> some View {
        let isCurrent = model.currentPlayer == index && model.phase == .playing
        return VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: "cpu")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isCurrent ? Theme.coral : Theme.inkSub)
                Text("\(model.playerName(index))・\(Self.windNames[model.seatWind(index)])")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text("\(model.scores[index])")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(model.scores[index] < 0 ? Theme.coral : Theme.inkSub)
            if model.riichi[index] {
                Text("立直")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.coral))
            }
            MahjongMeldRow(melds: model.melds[index], tileWidth: 11, showsBadge: false)
            discardStrip(model.discards[index], tileWidth: 13, perRow: 6, maxTiles: 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7).padding(.horizontal, 4)
        .popCard(corner: Theme.cornerSmall)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            MahjongAccessibility.playerLabel(
                name: model.playerName(index), score: model.scores[index],
                isRiichi: model.riichi[index], isCurrent: isCurrent, melds: model.melds[index]
            )
            + "。"
            + MahjongAccessibility.discardPileLabel(
                player: model.playerName(index), tiles: model.discards[index]
            )
        )
    }

    /// 河を小さい牌で並べる。古い牌から順に、入りきらないぶんは新しい側を残す。
    private func discardStrip(
        _ tiles: [MahjongTile], tileWidth: CGFloat, perRow: Int, maxTiles: Int
    ) -> some View {
        let shown = Array(tiles.suffix(maxTiles))
        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: 2), count: perRow),
            alignment: .leading,
            spacing: 2
        ) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, tile in
                MahjongTileView(tile: tile, width: tileWidth, height: tileWidth * 1.34)
            }
        }
        // 河は左上から順に並ぶもの。中央寄せだと捨てるたびに既に置いた牌が動いて見える。
        .frame(maxWidth: .infinity, minHeight: tileWidth * 1.34, alignment: .topLeading)
    }

    // MARK: - 自分の河

    private var playerDiscardArea: some View {
        VStack(spacing: 4) {
            Text("あなたの捨て牌")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            // 河は 6 枚 × 3 段（本来の並べ方）。捨てるたびに高さが跳ねないよう 3 段ぶんを常に確保する。
            discardStrip(model.discards[MahjongModel.humanIndex], tileWidth: 26, perRow: 6, maxTiles: 18)
                .frame(minHeight: 26 * 1.34 * 3 + 4, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8).padding(.horizontal, 10)
        .popCard(corner: Theme.cornerSmall)
        .gameAnimation(.easeInOut(duration: 0.18), value: model.discards[MahjongModel.humanIndex])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            MahjongAccessibility.discardPileLabel(
                player: "あなた", tiles: model.discards[MahjongModel.humanIndex]
            )
        )
    }

    // MARK: - 手牌

    private var handArea: some View {
        // 切れる牌の判定は手牌の枚数ぶん走るので、1 回だけ求めて配る（#190 と同じ考え方）。
        let discardable = model.discardableTiles
        let waits = model.playerWaits
        return VStack(spacing: 6) {
            HStack {
                Text("あなた・\(Self.windNames[model.seatWind(MahjongModel.humanIndex)])")
                    .themeBody(13).foregroundStyle(Theme.ink)
                if model.riichi[MahjongModel.humanIndex] {
                    Text("立直")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.coral))
                }
                Spacer()
                Text("\(model.scores[MahjongModel.humanIndex])点")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: MahjongHandLayout.spacing),
                    count: MahjongHandLayout.columns
                ),
                spacing: MahjongHandLayout.spacing
            ) {
                ForEach(Array(model.playerHand.tiles.enumerated()), id: \.offset) { _, tile in
                    handTile(tile, isDrawn: false, discardable: discardable)
                }
                if let drawn = model.drawnTile {
                    handTile(drawn, isDrawn: true, discardable: discardable)
                }
            }
            .gameAnimation(.easeInOut(duration: 0.18), value: model.playerHand)
            MahjongMeldRow(melds: model.playerMelds, tileWidth: 22)
            hintLine(waits: waits)
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    private func handTile(
        _ tile: MahjongTile, isDrawn: Bool, discardable: Set<MahjongTile>
    ) -> some View {
        let canDiscard = discardable.contains(tile)
        return MahjongTileView(
            tile: tile,
            width: MahjongHandLayout.tileWidth,
            height: MahjongHandLayout.tileHeight,
            isBlocked: model.isPlayerTurn && !canDiscard,
            isHinted: isDrawn
        )
        // 見える牌の大きさは変えず、タップ判定だけを 44pt 以上に広げる（#195・#207 と同じ手当て）。
        .frame(maxWidth: .infinity, minHeight: MahjongHandLayout.minimumTapTarget)
        .contentShape(Rectangle())
        .onTapGesture { model.discard(tile) }
        .transition(.scale.combined(with: .opacity))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            MahjongAccessibility.handTileLabel(tile, isDrawn: isDrawn, isDiscardable: canDiscard)
        )
        .accessibilityHint("ダブルタップでこの牌を切ります")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.discard(tile) }
        .disabled(!model.isPlayerTurn)
    }

    /// 手牌の下に出す 1 行の案内（#190 の設定に従う）。
    @ViewBuilder
    private func hintLine(waits: [MahjongTile]) -> some View {
        let message: String? = {
            if model.isDeclaringRiichi { return "立直します。切る牌を選んでください" }
            if model.isPlayerFuriten && !waits.isEmpty { return "フリテンです（ツモでのみ和了できます）" }
            if !waits.isEmpty {
                // ツモ牌を除いた 13 枚の待ちなので、条件つきの言い方にする（`playerWaits` を参照）。
                return "ツモ切りすると " + waits.map(\.displayName).joined(separator: "・") + " 待ち"
            }
            return nil
        }()
        if let message {
            HStack(spacing: 4) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(message)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(model.isPlayerFuriten ? Theme.inkSub : Theme.coral)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - リザルト

    private var handResultCard: some View {
        VStack(spacing: 8) {
            Text(handResultTitle)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(Theme.coral)
            if let result = model.handResult, result.kind != .exhaustiveDraw {
                Text("\(result.han)飜 \(result.fu > 0 ? "\(result.fu)符 " : "")\(result.limitName ?? "")")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                VStack(spacing: 3) {
                    ForEach(Array(result.yaku.enumerated()), id: \.offset) { _, name in
                        Text(name)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.inkSub)
                    }
                }
                Text("\(result.gainedPoints)点")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.teal)
            } else if let result = model.handResult {
                Text(
                    result.tenpaiPlayers.isEmpty
                        ? "全員ノーテンです"
                        : "聴牌: " + result.tenpaiPlayers.map { model.playerName($0) }.joined(separator: "・")
                )
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            }
            scoreTable
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .popCard(corner: Theme.cornerSmall)
    }

    private var handResultTitle: String {
        guard let result = model.handResult else { return "" }
        switch result.kind {
        case .exhaustiveDraw: return "流局"
        case .tsumo:  return "\(model.playerName(result.winner ?? 0))のツモ"
        case .ron:    return "\(model.playerName(result.winner ?? 0))のロン"
        }
    }

    private var gameResultCard: some View {
        VStack(spacing: 10) {
            Text("東風戦終了")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(Theme.coral)
            if let place = model.playerPlace {
                Text("あなたは \(place + 1)位")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            VStack(spacing: 4) {
                ForEach(Array(model.ranking.enumerated()), id: \.offset) { place, player in
                    HStack {
                        Text("\(place + 1)位")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.coral)
                            .frame(width: 36, alignment: .leading)
                        Text(model.playerName(player))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(model.scores[player])点")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.inkSub)
                    }
                }
            }
            RecordLabel(model.recordResult)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .popCard(corner: Theme.cornerSmall)
    }

    private var scoreTable: some View {
        VStack(spacing: 2) {
            ForEach(0..<MahjongModel.playerCount, id: \.self) { player in
                HStack {
                    Text(model.playerName(player))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                    Spacer()
                    Text("\(model.scores[player])点")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(model.scores[player] < 0 ? Theme.coral : Theme.ink)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - 操作

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .ronOffer:
            HStack(spacing: 12) {
                actionButton("見逃す", color: Theme.fillMuted) {
                    model.declineRon()
                    Task { await model.runCPUTurnsIfNeeded() }
                }
                actionButton("ロン", color: Theme.coral) { model.declareRon() }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .callOffer:
            if let offer = model.callOffer {
                MahjongCallBar(
                    offer: offer,
                    onAccept: { call in
                        model.acceptCall(call)
                        Task { await model.runCPUTurnsIfNeeded() }
                    },
                    onDecline: {
                        model.declineCall()
                        Task { await model.runCPUTurnsIfNeeded() }
                    }
                )
            }
        case .playing:
            HStack(spacing: 12) {
                if model.isDeclaringRiichi {
                    actionButton("やめる", color: Theme.fillMuted) { model.cancelRiichiDeclaration() }
                } else {
                    actionButton("立直", color: Theme.purple, disabled: !model.canDeclareRiichi) {
                        model.declareRiichi()
                    }
                }
                // カンは出来るときだけ出す（常設すると押せないボタンが 3 つ並ぶ）。
                if model.canDeclareKan {
                    MahjongKanButton(options: model.availableSelfKans) { call in
                        model.declareKan(call)
                        Task { await model.runCPUTurnsIfNeeded() }
                    }
                }
                actionButton("ツモ", color: Theme.coral, disabled: !model.canDeclareTsumo) {
                    model.declareTsumo()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .handResult:
            actionButton("次の局へ", color: Theme.coral) {
                model.advanceToNextHand()
                Task { await model.runCPUTurnsIfNeeded() }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .gameResult:
            actionButton("もう一度", color: Theme.coral) {
                model.startGame()
                Task { await model.runCPUTurnsIfNeeded() }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        }
    }

    private func actionButton(
        _ title: String, color: Color, disabled: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .disabled(disabled)
    }

    static let windNames = ["東", "南", "西", "北"]
}

// MARK: - Start Sheet

struct MahjongStartSheet: View {
    let onStart: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ゲームの流れ")
                        .themeBody(15).foregroundStyle(Theme.inkSub)
                    ruleRow("1", "CPU3人と東風戦（東1局〜東4局）。持ち点は25000点から")
                    ruleRow("2", "1枚ツモって1枚切る。4面子+雀頭で和了")
                    ruleRow("3", "聴牌したら立直できます（1000点を供託）。門前のときだけ")
                    ruleRow("4", "他の人の捨て牌はポン・チー・カンで鳴けます（鳴くと立直はできません）")
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 3))

                NavigationLink {
                    MahjongRuleSheet()
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("ルールと役を見る")
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
                    Text("対局開始").themeBody(18).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.coral)
            }
            .padding(Theme.pad)
            .popBackground()
            .navigationTitle("麻雀")
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

struct MahjongRuleSheet: View {
    private let rules: [(String, String)] = [
        ("和了の形", "同じ牌3枚（刻子）か連番3枚（順子）を4組と、同じ牌2枚（雀頭）を1組そろえると和了です。ほかに七対子（対子7組）と国士無双もあります"),
        ("ツモとロン", "自分で引いた牌で和了すればツモ、他の人が切った牌で和了すればロンです"),
        ("役が要ります", "和了の形になっても、役が1つも無いと和了できません。立直・断幺九・役牌などが役です"),
        ("立直", "聴牌したら1000点を供託して宣言できます。以後は引いてきた牌をそのまま切ります（手牌は変えられません）。鳴いた手では宣言できません"),
        ("ポン・チー", "同じ牌が2枚あれば誰の捨て牌でもポン、連番であと2枚そろうときは上家（左の人）の捨て牌をチーできます。鳴くとその牌を含む面子を手牌の外に晒し、そのまま自分の番になって1枚切ります"),
        ("カン", "同じ牌4枚でカンできます。手の内の4枚なら暗槓、他の人の捨て牌でそろえば明槓、ポン済みの牌に4枚目を足せば加槓です。カンすると新しいドラがめくれ、王牌から1枚（嶺上牌）を引きます"),
        ("鳴くと何が変わるか", "立直・門前清自摸和・平和・一盃口・七対子は付かなくなり、三色同順・一気通貫・チャンタ・混一色などは1飜下がります。役牌のように鳴いても付く役をねらいます。暗槓だけは門前のままです"),
        ("フリテン", "自分の待ち牌を自分で捨てているとロンできません（ツモなら和了できます）"),
        ("流局", "山が尽きたら流局。聴牌していた人が3000点を分け合い、ノーテンの人が払います"),
        ("東風戦", "東1局から東4局までの4局。親が和了または聴牌で流局すると連荘して本場が増えます"),
        ("この版の範囲", "半荘は次の版で追加します。立直したあとのカン・食い替えの禁止・流し満貫はまだ入っていません"),
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
        .navigationTitle("ルールと役")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
