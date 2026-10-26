import Testing
import Foundation
import Core
import CoreEngine
@testable import GameColorRelay
import CoreTestSupport
import GameKitTestSupport

@Suite("いろリレーのモジュール")
@MainActor
struct ColorRelayModuleTests {
    @Test("登録口の ID と Model の gameID・遊び方ガイドは同じ")
    func idsMatch() {
        #expect(ColorRelayModule().id == ColorRelayModel.gameID)
        #expect(HowToPlayGuide.colorRelay.gameID == ColorRelayModule().id)
        #expect(HowToPlayGuide.all.contains(.colorRelay))
        // 勝敗しか残らないので順位表は持たない（大富豪と同じ）。
        #expect(GameCenterLeaderboard.score(
            gameID: ColorRelayModule().id, outcome: .win, score: GameScore(metric: .winLoss)
        ) == nil)
    }

    @Test("表示名・説明・ルールに他社の商標を含めない（Issue #1320 の権利面の注意）")
    func noTrademarkedWords() {
        let module = ColorRelayModule()
        #expect(module.title == "いろリレー")
        #expect(!module.description.isEmpty)
        let texts = [module.title, module.description]
            + HowToPlayGuide.colorRelay.lines + [HowToPlayGuide.colorRelay.title, HowToPlayGuide.colorRelay.hint]
            + ColorRelayRuleSheet.rules.flatMap { [$0.0, $0.1] }
        for banned in ["UNO", "uno", "Uno", "ウノ", "公式", "ライセンス", "®", "™"] {
            #expect(texts.allSatisfy { !$0.contains(banned) }, "「\(banned)」を含む文言がある")
        }
    }

    @Test("中断データがあるあいだだけ「続きから」になる")
    func resumableSnapshot() {
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService())
        let module = ColorRelayModule()
        #expect(!module.hasResumableSnapshot(in: store))
        let model = ColorRelayModel(services: services, cpuDelay: .zero, seed: 7)
        model.startGame()
        #expect(!module.hasResumableSnapshot(in: store), "配ったばかりの局は保存しない（#240）")
        model.configureForTesting(hands: [[card(.red, .number(3)), card(.green, .number(5))], [card(.green, .number(1))], [card(.green, .number(2))], [card(.green, .number(4))]],
                                  top: card(.red, .number(7)), drawPile: [card(.purple, .number(9))])
        #expect(module.hasResumableSnapshot(in: store))
        model.toggleSelection(card(.red, .number(3)))
        model.playSelected()
        #expect(module.hasResumableSnapshot(in: store))
    }

    @Test("2 ゲーム目で CPU の先手だけが入った局は「続きから」にならず、人間が打てば従来どおり（#2763）")
    func cpuFirstOnlyIsNotResumable() async {
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService())
        let module = ColorRelayModule()
        let model = ColorRelayModel(services: services, cpuDelay: .zero, seed: 7)
        // CPU が途中で上がらないよう、CPU の手札は多めに持たせる。
        let hands = [[card(.red, .number(3)), card(.green, .number(5))],
                     (1...6).map { card(.green, .number($0)) }, (1...6).map { card(.purple, .number($0)) },
                     (1...6).map { card(.yellow, .number($0)) }]
        // 2 ゲーム目: CPU1 が親で、人間が打つ前に 1 枚出した直後。
        model.configureForTesting(hands: hands, top: card(.red, .number(7)), drawPile: [card(.purple, .number(9))],
                                  currentPlayer: 1, gameNumber: 2, humanHasActed: false)
        #expect(store.exists(for: ColorRelayModel.gameID), "CPU の手は保存される")
        #expect(!module.hasResumableSnapshot(in: store))
        #expect(module.hasUntouchedSnapshot(in: store))
        #expect(!model.hasProgressToLose)
        // 復元しても人間未着手のまま。
        let restored = ColorRelayModel(services: services, cpuDelay: .zero, seed: 7)
        #expect(!restored.hasProgressToLose)
        #expect(!module.hasResumableSnapshot(in: store))
        // 人間が 1 枚出せば従来どおり「続きから」。
        await restored.runCPUTurnsIfNeeded()
        if let c = restored.playerHand.first(where: { restored.playableCardIDs.contains($0.id) }) {
            restored.toggleSelection(c)
            restored.playSelected(color: c.isWild ? .red : nil)
        } else {
            restored.drawCard()
        }
        #expect(module.hasResumableSnapshot(in: store))
        #expect(!module.hasUntouchedSnapshot(in: store))
        #expect(restored.hasProgressToLose)
    }

    @Test("画面は共通の枠・レコメンド枠・局ガード付きの救済を使い、素のアニメーションを書いていない")
    func viewUsesSharedParts() throws {
        let source = try SourceScan.moduleSources("GameColorRelay")
        let code = SourceScan.strippingComments(source)
        #expect(code.components(separatedBy: ".gameChrome(title:").count - 1 == 1)
        // レイアウトパターン A（#2531）: バナーは全画面の枠が最下部に置くので、ゲーム側には `BannerSlot` を書かない。
        #expect(code.contains("fullScreen: .felt, ads: services.ads"), "全画面の枠にバナーの取得元を渡していない")
        #expect(!code.contains("BannerSlot("), "バナーを枠と二重に置いている")
        #expect(code.contains("RecommendationSlot("))
        #expect(code.contains("HowToPlayHint(.colorRelay"))
        #expect(code.components(separatedBy: "Rescue.request(").count - 1 == 1, "救済の入口は引き札の免除 1 面だけ")
        #expect(code.contains("guardedBy: .checkedByGrant"))
        #expect(code.contains("model.waivePenaltyAfterAd(forTurn:"))
        #expect(code.contains("unavailable: RewardUnavailableAlert("))
        #expect(!code.contains("showRewardedAd("), "広告は RewardedRescue 経由でしか出さない")
        #expect(!code.contains("withAnimation("), "アニメーションは gameAnimation 経由")
        #expect(code.contains("level: CPUStrength.analyticsLevel(forLevel: aiLevel)"), "CPU の強さを game_start の level に載せる（#2604）")
        #expect(code.contains("gameDidRestart(") && code.contains("gameDidProgress(") && code.contains("gameDidFinish("),
                "解析は 1 ゲーム 1 組 + 進行の 3 点で接続する")
    }

    @Test("撮影用の経路は Release に残っていない")
    func debugScenarioIsDebugOnly() throws {
        let source = try SourceScan.packageSource("Sources/GameColorRelay/ColorRelayModel.swift")
        #expect(source.contains("func applyDebugScenario("))
        var depth = 0
        var releaseLines: [String] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if DEBUG") { depth += 1; continue }
            if trimmed.hasPrefix("#endif") { depth = max(0, depth - 1); continue }
            if depth == 0, !trimmed.hasPrefix("//") { releaseLines.append(String(line)) }
        }
        let release = releaseLines.joined(separator: "\n")
        #expect(!release.contains("applyDebugScenario"))
        #expect(release.contains("public func startGame(aiLevel"), "走査そのものが機能している")
    }

    @Test("手札の 1 枚あたりの見える幅（タップ判定）は、何枚になっても 44pt 以上", arguments: [375.0, 393.0, 402.0, 440.0])
    func handTapTarget(screenWidth: Double) {
        let width = CGFloat(screenWidth)
        let card = ColorRelayHandLayout.metrics(screenWidth: width).handCardWidth
        let strip = ColorRelayHandLayout.stripWidth(screenWidth: width)
        for count in 1...30 {
            let exposure = ColorRelayHandLayout.exposure(count: count, cardWidth: card, available: strip)
            #expect(exposure >= ColorRelayHandLayout.minimumTapTarget, "\(count) 枚")
            // 札の高さもタップの最小に届く。
            #expect(ColorRelayCardSize(width: card).height >= ColorRelayHandLayout.minimumTapTarget)
        }
    }

    @Test("SE（375pt）でも配られた 7 枚 + 1 枚引いた 8 枚までは横スクロール無しで並ぶ")
    func seFitsEightCards() {
        #expect(ColorRelayHandLayout.maxCardsWithoutScroll(screenWidth: 375) >= 8)
        #expect(ColorRelayHandLayout.maxCardsWithoutScroll(screenWidth: 402) >= 8)
        let card = ColorRelayHandLayout.metrics(screenWidth: 375).handCardWidth
        let strip = ColorRelayHandLayout.stripWidth(screenWidth: 375)
        let exposure = ColorRelayHandLayout.exposure(count: 8, cardWidth: card, available: strip)
        #expect(ColorRelayHandLayout.totalWidth(count: 8, cardWidth: card, exposure: exposure) <= strip)
        // 17 Pro は札を大きく、SE だけ小さくする。
        #expect(ColorRelayHandLayout.metrics(screenWidth: 402).handCardWidth
                > ColorRelayHandLayout.metrics(screenWidth: 375).handCardWidth)
    }

    @Test("場の札は卓の中段の大きさに収まり、大きさ 0 でも負にならない")
    func fieldFitsTheTable() {
        let zero = ColorRelayHandLayout.field(size: .zero, maxTopWidth: 96)
        #expect(zero.topWidth == 0 && zero.pileWidth == 0)
        let size = CGSize(width: 340, height: 150)
        let field = ColorRelayHandLayout.field(size: size, maxTopWidth: 96)
        #expect(field.topWidth * ColorRelayHandLayout.plateRatio + ColorRelayHandLayout.fieldLabelHeight <= size.height + 0.5)
        #expect(field.pileWidth + field.spacing + field.topWidth * ColorRelayHandLayout.plateRatio <= size.width + 0.5)
        #expect(ColorRelayHandLayout.field(size: CGSize(width: 1000, height: 1000), maxTopWidth: 96).topWidth == 96)
    }

    @Test("卓はアプリ共通のフェルト（全画面の枠）に載せ、茶色の独自の卓やおじさんの顔を使わない")
    func tableUsesTheSharedSurface() throws {
        let code = SourceScan.strippingComments(try SourceScan.moduleSources("GameColorRelay"))
        // レイアウトパターン A（会長決裁 2026-10-19・#2531）: フェルトは `gameChrome(fullScreen: .felt)` が画面全体に敷く。
        // 盤にもう一度 `.cardTable()` を付けると、フェルトの上に木枠付きの卓が二重に乗る。
        #expect(SourceScan.matchCount(of: "\\.cardTable\\(", in: code) == 0, "全画面のフェルトの上に卓を二重に敷いている")
        #expect(code.contains("fullScreen: .felt"))
        #expect(!code.contains("CardTableSurface("), "卓の面を直接組み立てない")
        #expect(!code.contains("rimMiddle") && !code.contains("rimBottom"), "木枠の色で独自の茶色の卓を塗らない")
        #expect(!code.contains("OjisanPixel"), "相手のアイコンにおじさんの絵を使わない（会長決裁 2026-10-18）")
    }

    @Test("相手の席は共通部品（OpponentSeat）を使い、大富豪と同じ見た目にする（#2531）")
    func seatsUseTheSharedPart() throws {
        let code = SourceScan.strippingComments(try SourceScan.moduleSources("GameColorRelay"))
        #expect(code.contains("OpponentSeat("), "相手の席を自前で組んでいる")
        #expect(code.contains("OpponentCardFan("), "裏向きの束を自前で組んでいる")
        #expect(!code.contains("ColorRelayBackFan"), "いろリレー専用の束が残っている")
    }

    @Test("相手 3 人のアイコンは記号も丸の色も互いに違い、丸の色は札の 4 色と重ならない")
    func opponentIconsAreDistinct() {
        let seats = Array(1..<ColorRelayModel.maxPlayerCount)
        #expect(Set(seats.map(OpponentSeatStyle.symbol(for:))).count == seats.count)
        let discs = seats.map { OpponentSeatStyle.colors(for: $0).disc }
        #expect(Set(discs).count == seats.count)
        let faces = Set(RelayColor.allCases.map(\.faceHex))
        for disc in discs { #expect(!faces.contains(disc)) }
        // 記号は丸の上で読める（非テキストの 3:1）。
        for seat in seats {
            let c = OpponentSeatStyle.colors(for: seat)
            #expect(WCAG.contrast(c.mark, c.disc) >= 3, "CPU\(seat)")
        }
    }
}

@Suite("いろリレーの読み上げ")
struct ColorRelayAccessibilityTests {
    @Test("札の呼び名は色 + 種類。万能札は種類だけ")
    func cardNames() {
        #expect(ColorRelayAccessibility.cardName(card(.red, .number(5))) == "あかの5")
        #expect(ColorRelayAccessibility.cardName(card(.green, .skip)) == "みどりのとばし")
        #expect(ColorRelayAccessibility.cardName(card(.purple, .reverse)) == "むらさきのぎゃく")
        #expect(ColorRelayAccessibility.cardName(card(.yellow, .drawTwo)) == "きいろのプラス2")
        #expect(ColorRelayAccessibility.cardName(card(nil, .wild)) == "いろがえ")
        #expect(ColorRelayAccessibility.cardName(card(nil, .wildDrawFour)) == "いろがえプラス4")
        // 記号のまま読ませない。
        for c in RelayCard.makeDeck() {
            #expect(ColorRelayAccessibility.cardName(c).rangeOfCharacter(from: .symbols) == nil, "\(c)")
        }
    }

    @Test("手札の読み上げは選択中と出せる / 出せないを文字で足す")
    func handLabels() {
        let c = card(.red, .number(5))
        #expect(ColorRelayAccessibility.handCardLabel(c, isSelected: false) == "あかの5")
        #expect(ColorRelayAccessibility.handCardLabel(c, isSelected: true, hint: .playable) == "あかの5、選択中、出せます")
        #expect(ColorRelayAccessibility.handCardLabel(c, isSelected: false, hint: .unplayable) == "あかの5、いまは出せません")
    }

    @Test("場の読み上げはいまの札・いろがえならいまの色・山の残り")
    func fieldLabel() {
        #expect(ColorRelayAccessibility.fieldLabel(top: card(.red, .number(5)), activeColor: .red, drawPileCount: 30)
                == "場の札、あかの5。山は残り30枚")
        #expect(ColorRelayAccessibility.fieldLabel(top: card(nil, .wild), activeColor: .yellow, drawPileCount: 3)
                == "場の札、いろがえ。いまの色はきいろ。山は残り3枚")
        #expect(ColorRelayAccessibility.fieldLabel(top: nil, activeColor: .red, drawPileCount: 0) == "場に札はありません")
    }

    @Test("相手の席の読み上げは名前・残り枚数・手番・直前の手（画面はアイコンだけなので名前を文字で補う）")
    func seatLabel() {
        #expect(ColorRelayAccessibility.seatLabel(name: "CPU1", cardCount: 5, isCurrent: false, lastAction: "")
                == "CPU1、残り5枚")
        #expect(ColorRelayAccessibility.seatLabel(name: "CPU2", cardCount: 1, isCurrent: true, lastAction: "ぎゃく！")
                == "CPU2、残り1枚、いまの番、直前の手、ぎゃく！")
        #expect(GameColorRelay.tr("%1$@、残り%2$lld枚", "CPU1", 1, language: .english) == "CPU1, 1 card left")
        #expect(GameColorRelay.tr("%1$@、残り%2$lld枚", "CPU1", 4, language: .english) == "CPU1, 4 cards left")
    }

    @Test("卓の見出しの読み上げは何ゲーム目・回る向き・誰の番")
    func tableHeaderLabel() {
        #expect(ColorRelayAccessibility.tableHeaderLabel(gameNumber: 3, isClockwise: true, turn: "CPU2の番")
                == "3ゲーム目、順回り、CPU2の番")
        #expect(ColorRelayAccessibility.tableHeaderLabel(gameNumber: 1, isClockwise: false, turn: "")
                == "1ゲーム目、逆回り")
    }
}
