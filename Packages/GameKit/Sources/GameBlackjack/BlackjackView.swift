import SwiftUI
import Core

public struct BlackjackView: View {
    @State private var model: BlackjackModel
    private let services: GameServices
    @Environment(\.dismiss) private var dismiss

    // ベット選択肢
    private let betOptions = [50, 100, 200, 500]

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: BlackjackModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 10) {
            chipsBar
            dealerArea
            Spacer(minLength: 4)
            playerArea
            if model.sessionOver {
                sessionOverView
            } else {
                actionArea
            }
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
                Text("ブラックジャック")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
        }
    }

    // MARK: - Chips Bar

    private var chipsBar: some View {
        HStack {
            Label("チップ: \(model.chips)枚", systemImage: "circle.hexagongrid.fill")
                .font(Theme.body(14))
                .foregroundStyle(Theme.ink)
            Spacer()
            if model.bet > 0 {
                Label("ベット: \(model.bet)枚", systemImage: "dollarsign.circle.fill")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.yellow)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Dealer Area

    private var dealerArea: some View {
        VStack(spacing: 10) {
            HStack {
                Text("ディーラー")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkSub)
                Spacer()
                if model.phase == .result || model.phase == .dealerTurn {
                    Text("\(model.dealerValue)")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(model.dealerValue > 21 ? Theme.coral : Theme.purple)
                } else if !model.dealerHand.isEmpty {
                    Text("\(model.dealerVisibleValue) + ?")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                }
            }

            HStack(spacing: 8) {
                ForEach(Array(model.dealerHand.enumerated()), id: \.element.id) { idx, card in
                    let hidden = idx == 1 && model.phase == .playerTurn
                    BJCardView(card: card, faceUp: !hidden)
                }
            }
            .frame(minHeight: 90)
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Player Area

    private var playerArea: some View {
        VStack(spacing: 10) {
            HStack {
                Text("あなた")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if !model.playerHand.isEmpty {
                    Text("\(model.playerValue)")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(model.playerValue > 21 ? Theme.coral : Theme.teal)
                }
                if let outcome = model.outcome {
                    outcomeBadge(outcome)
                }
            }

            HStack(spacing: 8) {
                ForEach(model.playerHand) { card in
                    BJCardView(card: card, faceUp: true)
                }
            }
            .frame(minHeight: 90)
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .popCard(corner: Theme.cornerSmall)
    }

    @ViewBuilder
    private func outcomeBadge(_ outcome: BlackjackOutcome) -> some View {
        switch outcome {
        case .playerBlackjack:
            Text("ブラックジャック！")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.yellow))
        case .win:
            Text("勝ち！")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.teal))
        case .push:
            Text("引き分け")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.inkSub))
        case .lose:
            Text("負け")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.coral))
        case .bust:
            Text("バスト")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.coral))
        }
    }

    // MARK: - Action Area

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .betting:
            bettingView
        case .playerTurn:
            playerActionView
        case .result:
            resultView
        case .dealerTurn, .idle:
            EmptyView()
        }
    }

    private var bettingView: some View {
        VStack(spacing: 8) {
            Text("ベット額を選んでください")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            HStack(spacing: 10) {
                ForEach(betOptions, id: \.self) { amount in
                    actionButton(
                        "\(amount)枚",
                        color: Theme.coral,
                        disabled: model.chips < amount
                    ) {
                        model.placeBet(amount)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    private var playerActionView: some View {
        HStack(spacing: 12) {
            actionButton("スタンド", color: Theme.inkSub) {
                model.stand()
            }
            actionButton("ヒット", color: Theme.coral) {
                model.hit()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    private var resultView: some View {
        actionButton("次のゲーム", color: Theme.coral) {
            model.nextRound()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Session Over

    private var sessionOverView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.coral)
                VStack(alignment: .leading, spacing: 2) {
                    Text("チップがなくなりました")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.coral)
                    Text("広告を見て500枚回復するか、最初からやり直せます")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                }
                Spacer()
            }

            Button { model.recoverChipsAfterAd() } label: {
                Label("広告を見てチップ回復 (+500枚)", systemImage: "play.rectangle.fill")
                    .font(Theme.body(16)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.yellow)

            Button { model.restartSession() } label: {
                Text("最初からやり直す (1000枚)").font(Theme.body(16)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.coral)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Helper

    private func actionButton(_ title: String, color: Color, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(14))
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

struct BJCardView: View {
    let card: BlackjackCard
    var faceUp: Bool = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(faceUp ? Color.white : Color(hex: 0x2A5298))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                )

            if faceUp {
                VStack(spacing: 2) {
                    Text(card.rankLabel)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                    Text(card.suit.symbol)
                        .font(.system(size: 24))
                }
                .foregroundStyle(card.suit.isRed ? Color(hex: 0xC0392B) : Color(hex: 0x1A1A1A))
            } else {
                Image(systemName: "suit.spade.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(width: 62, height: 90)
    }
}
