import Testing
import CoreGraphics
import Core
import CoreEngine
@testable import GameSpeed
import CoreTestSupport
import GameKitTestSupport

private func card(_ suit: SpeedSuit, _ rank: Int) -> SpeedCard {
    SpeedCard(id: suit.rawValue * 13 + rank - 1, suit: suit, rank: rank)
}

@Suite("スピードのモジュール")
@MainActor
struct SpeedModuleTests {
    @Test("登録口の ID と Model の gameID・遊び方ガイドは同じ")
    func idsMatch() {
        #expect(SpeedModule().id == SpeedModel.gameID)
        #expect(HowToPlayGuide.speed.gameID == SpeedModule().id)
        #expect(HowToPlayGuide.all.contains(.speed))
        // 記録は勝敗・連勝・最速（速さの区分あり）なので順位表は持たない（ぱっと暗算・いろリレーと同じ）。
        #expect(GameCenterLeaderboard.score(
            gameID: SpeedModule().id, outcome: .win,
            score: GameScore(metric: .winLoss, seconds: 30, variant: "normal")
        ) == nil)
        #expect(!SpeedModule().resumesFromSnapshot, "中断データは速さの控えで、ゲームは復元しない")
    }

    @Test("表示名・説明・ルールに他社の登録商標や公式を思わせる語を含めない（Issue #1323 の権利チェック）")
    func noTrademarkedWords() {
        let module = SpeedModule()
        #expect(module.title == "スピード")
        #expect(!module.description.isEmpty)
        let texts = [module.title, module.description]
            + HowToPlayGuide.speed.lines + [HowToPlayGuide.speed.title, HowToPlayGuide.speed.hint]
            + SpeedRuleSheet.rules.flatMap { [$0.0, $0.1] }
        // 「スピード」自体は伝統的トランプゲームの一般名称（文字商標 0 件・2026-09-24 patent-i.com）。
        // 他社製品名や公式を思わせる語だけを禁じる。
        for banned in ["公式", "ライセンス", "®", "™", "Online", "オンライン"] {
            #expect(texts.allSatisfy { !$0.contains(banned) }, "「\(banned)」を含む文言がある")
        }
    }

    @Test("画面は共通の枠・レコメンド枠・局ガード付きの救済を使い、時間は Model が返す待ちを .task で待つだけ")
    func viewUsesSharedParts() throws {
        let source = try SourceScan.moduleSources("GameSpeed")
        let code = SourceScan.strippingComments(source)
        #expect(code.components(separatedBy: ".gameChrome(title:").count - 1 == 1)
        #expect(code.contains("RecommendationSlot("))
        // レイアウトパターン A（全画面・#2531）: バナーは枠が最下部に置くので、ゲーム側に BannerSlot を書かない。
        #expect(code.contains("fullScreen: .felt, ads: services.ads"), "全画面の枠にバナーの取得元を渡していない")
        #expect(!code.contains("BannerSlot("), "バナーを枠と二重に置いている")
        #expect(code.contains("FullScreenGameLayoutMetrics.sideInset"), "左右の余白は全画面の枠の値")
        // 会長 QA 2026-10-23「＋ともう一個ボタンあるけど、これ同じじゃね？」: 新規は「＋」1 つで、速さのシートから始める。
        #expect(!code.contains("slider.horizontal.3"), "ヘッダーに「速さ」のボタンが残っている")
        #expect(code.contains("GameChromeNewGame(.match, isDisabled: timeoutRescue.isWatching)"), "広告の視聴中に＋を塞いでいない")
        #expect(code.contains("Button(tr(\"終了して新規対局\"), role: .destructive) { showSetup = true }"),
                "途中の確認のあとは速さのシートから始める")
        #expect(code.contains("HowToPlayHint(.speed"))
        #expect(code.contains("GameSetupSheet(") && code.contains("GameSetupChooser("), "速さのシートは共通枠から組む")
        #expect(code.components(separatedBy: "Rescue.request(").count - 1 == 1, "救済の入口はタイムの 1 面だけ")
        #expect(code.contains("guardedBy: .checkedByGrant"))
        #expect(code.contains("model.grantTimeoutAfterAd(forGame:"))
        #expect(code.contains("unavailable: RewardUnavailableAlert("))
        #expect(code.contains(".rewardOffer(timeoutRescue, for: .revival, isPresented: model.canUseTimeout"))
        #expect(!code.contains("showRewardedAd("), "広告は RewardedRescue 経由でしか出さない")
        #expect(!code.contains("withAnimation("), "アニメーションは gameAnimation 経由")
        #expect(code.contains("level: settings.level.analyticsLevel"), "速さを持つので game_start に level を載せる")
        #expect(code.contains("gameDidStart(") && code.contains("gameDidRestart(")
                && code.contains("gameDidProgress(") && code.contains("gameDidFinish("),
                "解析は 1 ゲーム 1 組 + 進行の 3 点で接続する")
        #expect(code.contains("gameWillNotResume("), "中断データは速さの控えなので休憩扱いを打ち消す")
        #expect(!code.contains("Timer.") && !code.contains("DispatchQueue"), "時間は Model が返す待ちを .task で待つだけ")
        #expect(!code.contains("AITurnGuarded"), "手番が無いので順番制の定石は使わない（Issue #1323）")
        #expect(code.contains(".task(id: model.cpuRun)"), "CPU の待ちは cpuRun を鍵に組み直す")
        #expect(code.contains("Task.sleep(for: wait)"))
        #expect(code.contains("model.cpuRun == run"), "番号が変わったら古いループは抜ける（同じ場で 2 度動かない）")
        #expect(code.contains(".onChange(of: timeoutRescue.isWatching)") && code.contains("model.holdCPU("),
                "広告の視聴中は CPU を止める（あなたが触れないあいだに CPU だけが出し切らない）")
        #expect(code.contains("onPresent: { model.holdCPU(.sheet, true) }") && code.contains("onDismiss: { model.holdCPU(.sheet, false) }"),
                "遊び方のシートを開いているあいだは CPU を止め、閉じたら再開する（#1358）")
        #expect(code.contains(".onChange(of: showSetup)"), "速さのシートを開いているあいだも CPU を止める（#1358）")
        #expect(code.contains("model.holdCPU(.confirm, open)"), "新規の確認は開始シートとは別の理由で止める（確認が閉じる解除がシートの止めを解かない。#3142）")
        #expect(code.contains(".onChange(of: scenePhase)"), "バックグラウンドでは CPU を止める（アクション枠の基盤規約）")
        #expect(code.contains("PlayingCardSurface(") && code.contains("PlayingCardFace("), "札はトランプ共通基盤（#397）で描く")
        #expect(code.contains(".actionSlowMode"), "設定の「ゆっくりモード」（アクション枠共通）を CPU の反応に掛ける")
    }

    @Test("撮影用の経路は Release に残っていない")
    func debugScenarioIsDebugOnly() throws {
        let source = try SourceScan.packageSource("Sources/GameSpeed/SpeedModel.swift")
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
        #expect(!release.contains("isFrozenForCapture"))
        #expect(release.contains("public func nextCPUWait()"), "走査そのものが機能している")
    }

    @Test("手札 4 枚と山札は iPhone SE の幅に収まり、札は 44pt 以上の押し幅を持つ")
    func handFits() {
        #expect(SpeedHandLayout.fits(screenWidth: 375))
        #expect(SpeedHandLayout.cardWidth(contentWidth: 375 - FullScreenGameLayoutMetrics.sideInset * 2) >= 44)
    }

    /// 会長 QA 2026-10-23「スピードの画面がチカチカフラッシュする」の再発防止。補充された札は `.transition(.scale)` で
    /// ほぼ 0 倍から出てくるので、札の側で枠を測ると幅 0.0007pt の枠が残り、台札へ飛ぶ札が 14 万倍に拡大されて
    /// 札の面が画面全体を白く覆っていた。
    @Test("台札へ飛ぶ札の倍率は、測った手札の枠が潰れていても台札の大きさの上限を超えない")
    func flightScaleIsBounded() {
        // 実際に記録された潰れた枠（幅 0.0007pt）と台札の幅 98pt。
        #expect(SpeedFlight.pileScale(handWidth: 0.0007, pileWidth: 98) == SpeedTableLayout.maxPileRatio)
        #expect(SpeedFlight.pileScale(handWidth: 70, pileWidth: 98) == 1.4)
        #expect(SpeedFlight.pileScale(handWidth: 70, pileWidth: 70) == 1)
        #expect(SpeedFlight.pileScale(handWidth: 0, pileWidth: 98) == 1)
        #expect(SpeedFlight.pileScale(handWidth: nil, pileWidth: 98) == 1)
        // どの画面の寸法でも、台札 ÷ 手札は 1〜maxPileRatio に収まる（上限で切っても見た目は変わらない）。
        for size in [CGSize(width: 375, height: 667), CGSize(width: 402, height: 874), CGSize(width: 1024, height: 1366), .zero] {
            let metrics = SpeedTableLayout.metrics(contentSize: size)
            let ratio = metrics.pileCard.width / metrics.handCard.width
            #expect(ratio >= 1 && ratio <= SpeedTableLayout.maxPileRatio + 0.0001)
        }
    }

    @Test("手札の枠は、拡大縮小の出入りをする札の外（動かない枠）で測る")
    func handFrameIsMeasuredOutsideTransition() throws {
        let code = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameSpeed/SpeedView.swift"))
        #expect(code.contains(".cardDropTarget(SpeedSlot.hand(id), in: Self.tableSpace)"))
        #expect(!code.contains(".cardDropTarget(SpeedSlot.hand(card.id)"), "出入りで縮む札の側で枠を測っている")
        #expect(code.contains("SpeedFlight.pileScale(handWidth: metrics.width"), "飛ぶ札の倍率を寸法の幅から上限つきで決めていない")
    }

    /// 会長 QA 2026-10-27（#2955）: 山札から札を出す（補充）動きを、切り替わりではなく滑る動きにする。
    @Test("補充の札は山札から空いた枠へ滑り、着くまで手札の側では見せない。Reduce Motion では滑らせない")
    func refillSlides() throws {
        let card = SpeedCard(id: 1, suit: .hearts, rank: 5)
        let deal = SpeedFlight(card: card, from: .zero, to: CGPoint(x: 10, y: 10), isToPile: false, isDeal: true, toScale: 1)
        let toPile = SpeedFlight(card: card, from: .zero, to: .zero, isToPile: true)
        let bounce = SpeedFlight(card: card, from: .zero, to: .zero, isToPile: false)
        // 台札へ飛ぶ札と同じ長さ（CPU の飛ぶ札と見た目・速さを揃える）。跳ね返りのばねとは別。
        #expect(deal.lifetime == toPile.lifetime)
        #expect(deal.lifetime != bounce.lifetime)
        let code = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameSpeed/SpeedView.swift"))
        #expect(code.contains("flyHumanRefill()"), "自分が出したあとに補充の札を滑らせていない")
        #expect(code.contains("flyCPURefill(before: hand)"), "CPU が出したあとに補充の札を滑らせていない")
        #expect(code.contains(".cardDropTarget(SpeedSlot.humanStock"), "自分の山札の位置を測っていない")
        #expect(code.contains(".cardDropTarget(SpeedSlot.cpuStock"), "CPU の山札の位置を測っていない")
        #expect(code.contains(".opacity(isDealing(card) ? 0 : 1)"), "CPU の補充の札が着く前から見えている")
        #expect(code.contains("guard !Motion.isReduceMotionEnabled"), "Reduce Motion でも滑らせている")
    }

    /// 会長 QA 2026-10-23「相手が出したアニメーションが無く、急に札が入れ替わったように感じる」。
    @Test("CPU が出した札も CPU の手札の位置から台札へ飛び、台札は下の札を重ねて見せる")
    func cpuPlayFlies() throws {
        let code = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameSpeed/SpeedView.swift"))
        #expect(code.contains("flyCPUPlay(hand: hand, tops: tops)"), "CPU の着手のあとに飛ぶ札を出していない")
        #expect(code.contains(".cardDropTarget(SpeedSlot.cpu(card.id), in: Self.tableSpace)"), "CPU の札の位置を測っていない")
        #expect(code.contains("fromScale: SpeedTableLayout.cpuCardRatio"), "CPU の札の大きさから飛び始めていない")
        #expect(code.contains("ForEach(model.piles[index].suffix(3))"), "台札が 1 枚だけで、飛んでくるあいだ空いて見える")
        // CPU の着手は無音・触覚なし（#2726 の効果音も CPU では鳴らさない）。飛ぶ演出の側で鳴らさない。
        let body = try #require(code.range(of: "private func flyCPUPlay").map { String(code[$0.lowerBound...].prefix(700)) })
        #expect(!body.contains("feedback"), "CPU の札を飛ばすときに音・触覚を鳴らしている")
    }

    /// 柵越えおじさんで、モデルのテストは緑なのに実際の `DragGesture` で動かなかった事故（時刻の扱い）の再発防止。
    /// 払いの判定は離した瞬間の動いた量と OS の速さだけを読み、時刻は読まない。タップ・VoiceOver の入口も残す。
    @Test("手札の払いは DragGesture の動いた量と速さを SpeedSwipe に渡し、時刻を読まない")
    func swipeIsWiredFromGesture() throws {
        let code = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameSpeed/SpeedView.swift"))
        #expect(code.contains("DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.tableSpace))"))
        #expect(code.contains(".gesture(swipeGesture(card))"), "手札に払いのジェスチャがついていない")
        #expect(code.contains("SpeedSwipe.resolve("))
        #expect(code.contains("translation: value.translation") && code.contains("velocity: value.velocity"))
        #expect(!code.contains("value.time"), "ジェスチャの時刻を読まない")
        #expect(code.components(separatedBy: "if let lifted, lifted.card.id != card.id { return }").count - 1 == 2,
                "ほかの札を持ち上げているあいだの 2 本目の指（onChanged・onEnded）を無視していない")
        #expect(code.contains("model.swipeCard(card, onto: pile)"), "判定の結果を Model に渡していない")
        #expect(code.contains(".cardDropTarget(SpeedSlot.pile(index)"), "台札の枠を測っていない")
        #expect(code.contains(".accessibilityAction { tapHandCard(card) }"), "VoiceOver の操作（ダブルタップで出す）が残っていない")
        // 通常の操作ではタップで札を出さない（会長 QA 2026-10-24・build 52）。支援機能のときだけ今までのタップの操作に渡す。
        let tapCase = try #require(code.range(of: "case .tap:").map { String(code[$0.upperBound...].prefix(80)) })
        #expect(tapCase.contains("fingerTapHandCard(card)"), "指のタップを、札を出さない入口に通していない")
        #expect(code.contains("Button { fingerTapPile(index) }"), "台札の指のタップを、通常時は止める入口に通していない")
        #expect(code.contains("model.fingerTapHandCard(card, assistive: false)"))
        #expect(code.contains("model.fingerTapPile(index, assistive: assistive)"))
        #expect(code.contains("@Environment(\\.accessibilityVoiceOverEnabled)")
                && code.contains("@Environment(\\.accessibilitySwitchControlEnabled)"),
                "VoiceOver・スイッチコントロールの使用を読んでいない")
        #expect(code.contains("private var assistive: Bool { voiceOverEnabled || switchControlEnabled }"))
    }
}

@Suite("スピードの読み上げ")
struct SpeedAccessibilityTests {
    @Test("札の呼び名はマーク + 数字で、記号のまま読ませない")
    func cardNames() {
        #expect(SpeedAccessibility.cardName(card(.hearts, 5)) == "ハートの5")
        // 絵札は共通基盤（`PlayingCardFigure.spokenLabel`）の読み（K / A）に揃える（大富豪・ポーカーと同じ）。
        #expect(SpeedAccessibility.cardName(card(.spades, 13)) == "スペードのK")
        #expect(SpeedAccessibility.cardName(card(.diamonds, 1)) == "ダイヤのA")
        for c in SpeedCard.makeDeck() {
            #expect(SpeedAccessibility.cardName(c).rangeOfCharacter(from: .symbols) == nil, "\(c)")
        }
    }

    @Test("手札の読み上げは選択中と出せる / 出せないを文字で足す")
    func handLabels() {
        let c = card(.hearts, 5)
        #expect(SpeedAccessibility.handCardLabel(c, isSelected: false, isPlayable: true) == "ハートの5、出せます")
        #expect(SpeedAccessibility.handCardLabel(c, isSelected: true, isPlayable: true) == "ハートの5、選択中、出せます")
        #expect(SpeedAccessibility.handCardLabel(c, isSelected: false, isPlayable: false) == "ハートの5、いまは出せません")
    }

    @Test("台札・山札・CPU の手札の読み上げ")
    func tableLabels() {
        #expect(SpeedAccessibility.pileLabel(index: 0, top: card(.spades, 7)) == "左の台札、スペードの7")
        #expect(SpeedAccessibility.pileLabel(index: 1, top: nil) == "右の台札、まだ札はありません")
        #expect(SpeedAccessibility.stockLabel(of: .human, count: 12) == "あなたの山札、残り12枚")
        #expect(SpeedAccessibility.stockLabel(of: .cpu, count: 0) == "CPUの山札、なし")
        #expect(SpeedAccessibility.cpuHandLabel([card(.spades, 3), card(.clubs, 9)], stockCount: 4)
                == "CPUの手札、スペードの3、クラブの9。CPUの山札、残り4枚")
    }

    @Test("進行の 1 行は局面ごとに変わる")
    func statusLabels() {
        #expect(SpeedAccessibility.statusLabel(phase: .idle, isStuck: false, hasSelection: false, winner: nil, isDraw: false)
                == "速さを選んで始めましょう")
        #expect(SpeedAccessibility.statusLabel(phase: .playing, isStuck: true, hasSelection: false, winner: nil, isDraw: false)
                == "どちらも出せません。めくってください")
        #expect(SpeedAccessibility.statusLabel(phase: .playing, isStuck: false, hasSelection: true, winner: nil, isDraw: false)
                == "どちらの台札に置くか選んでください")
        // 盤の下の 1 行はスワイプ前提の言い方（会長 QA 2026-10-23）。
        #expect(SpeedAccessibility.statusLabel(phase: .playing, isStuck: false, hasSelection: false, winner: nil, isDraw: false)
                == "1つ違いの札を台札のほうへ払ってください")
        #expect(SpeedAccessibility.statusLabel(phase: .result, isStuck: false, hasSelection: false, winner: .human, isDraw: false)
                == "あなたの勝ち")
        #expect(SpeedAccessibility.statusLabel(phase: .result, isStuck: false, hasSelection: false, winner: nil, isDraw: true)
                == "引き分け")
    }
}
