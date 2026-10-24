import Testing
import Core
@testable import GameShiritori
import CoreTestSupport

/// 図で見る「はじめての遊び方」（#2825）の中身が、実装のルールのとおりになっていること。
@MainActor
@Suite("カードしりとり: はじめての遊び方")
struct ShiritoriOnboardingTests {
    private let apple = ShiritoriCard(.apple, "りんご")
    private let gorilla = ShiritoriCard(.gorilla, "ごりら")
    private let otter = ShiritoriCard(.seaOtter, "らっこ")
    private let squirrel = ShiritoriCard(.squirrel, "りす")
    private let trapForPlayer = ShiritoriCard(.pillow, "ごはん")
    private let trapForCPU = ShiritoriCard(.cat, "らーめん")

    private func makeModel() -> ShiritoriModel {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        return ShiritoriModel(services: services, cpuDelay: .zero, seed: 42)
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている。遊び方ごとに gameID は同じ")
    func wellFormed() {
        for mode in ShiritoriMode.allCases {
            let guide = ShiritoriOnboarding.guide(mode: mode)
            #expect(guide.isWellFormed, "\(mode)")
            #expect(guide.gameID == makeModel().gameID)
        }
        #expect(ShiritoriOnboarding.guide(mode: .quota) != ShiritoriOnboarding.guide(mode: .endless))
    }

    @Test("しりとり: 最後の字から始まる札だけ取れる（りんご → ごりら。らっこは合わない）")
    func chain() {
        #expect(ShiritoriRules.acceptingReading(of: gorilla, after: "ご") != nil)
        #expect(ShiritoriRules.acceptingReading(of: otter, after: "ご") == nil)
    }

    @Test("制限時間: 60 秒・成立で +10 秒・合わない札で -5 秒。ノルマは 4・6・9 枚")
    func time() {
        #expect(ShiritoriTime.initial == 60)
        #expect(ShiritoriTime.successBonus == 10)
        #expect(ShiritoriTime.missPenalty == 5)
        #expect([ShiritoriQuota.easy, .normal, .hard].map(\.cardCount) == [4, 6, 9])

        let model = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla, squirrel])
        model.select(1)   // りす: 「ご」では始まらない
        #expect(model.timeRemaining == 55)
        model.select(0)   // ごりら
        #expect(model.timeRemaining == 65)
    }

    @Test("「ん」で終わる札を取ると、その場で負け。CPU が取らされたら勝ち")
    func nEnding() async {
        #expect(ShiritoriRules.endsWithN(ShiritoriOnboarding.nReading))

        let player = makeModel()
        player.configureForTesting(opener: apple, board: [trapForPlayer, gorilla])
        player.select(0)
        #expect(player.ending == .playerHitN)
        #expect(!player.didPlayerWin)

        let cpu = makeModel()
        cpu.configureForTesting(opener: apple, board: [gorilla, trapForCPU], quota: .normal)
        cpu.select(0)
        await cpu.runCPUTurnIfNeeded()
        #expect(cpu.ending == .cpuHitN)
        #expect(cpu.didPlayerWin)
    }

    @Test("勝ち負け: CPU が続けられないと勝ち、あなたが続けられない・時間切れは負け")
    func winLose() async {
        let stuckCPU = makeModel()
        stuckCPU.configureForTesting(opener: apple, board: [gorilla])
        stuckCPU.select(0)
        #expect(stuckCPU.ending == .cpuStuck)
        #expect(stuckCPU.didPlayerWin)

        let stuckPlayer = makeModel()
        stuckPlayer.configureForTesting(opener: apple, board: [gorilla, otter])
        stuckPlayer.select(0)
        await stuckPlayer.runCPUTurnIfNeeded()
        #expect(stuckPlayer.ending == .playerStuck)
        #expect(!stuckPlayer.didPlayerWin)

        let timeUp = makeModel()
        timeUp.configureForTesting(opener: apple, board: [gorilla])
        timeUp.tick(60)
        #expect(timeUp.ending == .timeUp)
        #expect(!timeUp.didPlayerWin)
    }

    @Test("とことん: 取った場所に山札から補充され、全部取りきるとパーフェクト")
    func endless() {
        let model = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla], mode: .endless, stock: [otter])
        model.select(0)
        #expect(model.slots[0].card == otter, "取った場所に山札の札が出る")

        let last = makeModel()
        last.configureForTesting(opener: apple, board: [gorilla], mode: .endless)
        last.select(0)
        #expect(last.ending == .perfect)
        #expect(last.didPlayerWin)
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        // 数字を埋める文は、埋めたあとの文ではなく元の文（鍵）で訳を引く。
        let keys = [
            "ノルマは かんたん %1$lld 枚・ふつう %2$lld 枚・むずかしい %3$lld 枚です。",
            "制限時間は %lld 秒です。",
            "しりとりが成立すると +%lld 秒。",
            "合わない札を選ぶと -%lld 秒です。",
        ]
        for key in keys {
            #expect(tr.hasTranslation(key, language: .english), "「\(key)」に英語の訳が無い")
        }
        let filled: Set<String> = [
            tr(keys[0], ShiritoriQuota.easy.cardCount, ShiritoriQuota.normal.cardCount, ShiritoriQuota.hard.cardCount),
            tr(keys[1], Int(ShiritoriTime.initial)),
            tr(keys[2], Int(ShiritoriTime.successBonus)),
            tr(keys[3], Int(ShiritoriTime.missPenalty)),
        ]
        for mode in ShiritoriMode.allCases {
            for text in ShiritoriOnboarding.guide(mode: mode).texts where !filled.contains(text) {
                #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
            }
        }
    }
}
