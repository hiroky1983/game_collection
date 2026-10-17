import Testing
import Foundation
import Core
import GameKitTestSupport
@testable import GameRoulette
import CoreTestSupport

/// 画面の流れ（#2364・会長決裁 2026-10-17）。賭けの画面（案 A）→「スピン」でホイールの画面（案 B）→ 結果
/// →「同じ賭けでもう一度」「次のゲーム」で賭けの画面へ戻る。Model の局面からどちらの画面かを決める
/// `RouletteScreen.of` を、本物の Model を動かして確かめる。
@Suite("ルーレットの画面の流れ（#2364）")
@MainActor
struct RouletteScreenTests {

    private func screen(_ model: RouletteModel) -> RouletteScreen {
        RouletteScreen.of(phase: model.phase, sessionOver: model.sessionOver)
    }

    @Test("局面とチップ切れからどちらの画面かが決まる")
    func mapping() {
        #expect(RouletteScreen.of(phase: .betting, sessionOver: false) == .betting)
        #expect(RouletteScreen.of(phase: .spinning, sessionOver: false) == .wheel)
        #expect(RouletteScreen.of(phase: .result, sessionOver: false) == .wheel)
        #expect(RouletteScreen.of(phase: .result, sessionOver: true) == .wheel)
        #expect(RouletteScreen.of(phase: .betting, sessionOver: true) == .wheel, "チップ切れは賭けられない")
    }

    @Test("賭け → 回転（ホイール全面）→ 結果 → 次のゲームで賭けの画面へ戻る")
    func betSpinResultNextRound() {
        // 回転の待ちを長く取り、回っている途中の局面を観察する。
        let model = RouletteModel(seed: 7, spinInterval: .seconds(60))
        #expect(screen(model) == .betting)

        model.placeBet(.red)
        model.placeBet(.straight(17))
        #expect(screen(model) == .betting, "置いているあいだは賭けの画面のまま")

        model.spin()
        #expect(model.phase == .spinning)
        #expect(screen(model) == .wheel, "スピンを押した瞬間にホイールの画面へ")
        #expect(model.winningNumber != nil)
        #expect(model.lastSettlement == nil, "止まるまで答えは出さない")

        model.skipSpin()
        #expect(model.phase == .result)
        #expect(screen(model) == .wheel, "結果もホイールの画面で見せる")
        #expect(model.lastSettlement != nil)

        if !model.sessionOver {
            model.nextRound()
            #expect(screen(model) == .betting, "次のゲームで賭けの画面へ戻る")
            #expect(model.bets.isEmpty)
        }
    }

    @Test("結果から「同じ賭けでもう一度」でも賭けの画面へ戻り、口は置き直されている")
    func repeatReturnsToBetting() {
        let model = RouletteModel(seed: 3, spinInterval: .zero)
        model.selectedChip = 10
        model.placeBet(.even)
        model.spin()
        // 待ちが 0 なので押した直後に精算まで進む（それでも画面はホイールの側で止まる）。
        #expect(model.phase == .result)
        #expect(screen(model) == .wheel, "結果は自動では戻さず、ホイールの画面で見せる")
        model.repeatLastBets()
        #expect(screen(model) == .betting)
        #expect(model.bets.map(\.kind) == [.even])
    }

    @Test("チップが尽きたらホイールの画面にとどまる（復活・やり直しの操作欄を出す）")
    func bustStaysOnWheelScreen() {
        let store = MemorySnapshotStore()
        let snapshot = RouletteSnapshot(
            chips: 10, bets: [RouletteBet(id: 0, kind: .straight(0), amount: 10)],
            phase: .spinning, winningNumber: 5, history: [], hasRevivedThisSession: false
        )
        try? store.save(snapshot, for: "roulette")
        let model = RouletteModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.phase == .result)
        #expect(model.sessionOver)
        #expect(screen(model) == .wheel)
        model.nextRound()
        #expect(screen(model) == .wheel, "チップ切れでは次のゲームへ進めない")
        model.restartSession()
        #expect(screen(model) == .betting, "やり直すと賭けの画面へ戻る")
    }

    @Test("タブは数字 1 点と、それ以外の賭けを分け合う")
    func tabsPartitionEveryBet() {
        var kinds: [RouletteBetKind] = (0...36).map { .straight($0) }
        kinds += RouletteBetKind.dozens + RouletteBetKind.evenMoney
        for kind in kinds {
            let owners = RouletteBetTab.allCases.filter { $0.contains(kind) }
            #expect(owners.count == 1, "\(kind) がちょうど 1 つのタブに載っていない")
        }
        #expect(RouletteBetTab.numbers.contains(.straight(0)))
        #expect(RouletteBetTab.outside.contains(.red))
        #expect(RouletteBetTab.outside.contains(.dozen(2)))
    }

    @Test("View は局面から画面を選び、切り替えを Motion の定数で溶かす")
    func viewIsWiredToTheScreen() throws {
        let view = try SourceScan.packageSource("Sources/GameRoulette/RouletteView.swift")
        #expect(SourceScan.matchCount(of: #"RouletteScreen\.of\(phase: model\.phase, sessionOver: model\.sessionOver\)"#,
                                      in: view) == 1)
        #expect(SourceScan.matchCount(of: #"case \.betting:\s*bettingWheelCard\s*tableCard\(sizing\)\s*case \.wheel:\s*wheelScreen"#,
                                      in: view) == 1, "賭けの画面は大きなホイール + 表、回すとホイールの画面")
        #expect(SourceScan.matchCount(of: #"\.gameAnimation\(RouletteMotion\.screenSwap, value: screen\)"#, in: view) == 1)
        #expect(RouletteMotion.screenSwapDuration < RouletteMotion.spinDuration / 4, "切り替えが回転の頭を食わない")
        // 回転中も「あなたの賭け」を見せる。チップの残りと賭け額はどちらの画面にも出す。
        let wheel = SourceScan.functionSource(startingWith: "private var wheelScreen", in: view)
        #expect(wheel.contains("chipsPill") && wheel.contains("betPill") && wheel.contains("betSummaryCard"))
        let card = SourceScan.functionSource(startingWith: "private var bettingWheelCard", in: view)
        #expect(card.contains("chipsPill") && card.contains("betPill") && card.contains("historyStrip"))
        // 割り込み広告は使わない（救済はリワードのまま）。
        #expect(!view.contains("showInterstitial"))
    }
}
