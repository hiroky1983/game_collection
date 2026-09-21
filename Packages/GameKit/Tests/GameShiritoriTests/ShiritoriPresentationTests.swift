import Testing
import Foundation
import Core
@testable import GameShiritori

@Suite("カードしりとりの文言")
struct ShiritoriPresentationTests {

    @Test("取った割合は四捨五入。0 枚は 0%")
    func sharePercentRounds() {
        #expect(ShiritoriPresentation.sharePercent(player: 2, cpu: 1) == 67)
        #expect(ShiritoriPresentation.sharePercent(player: 1, cpu: 2) == 33)
        #expect(ShiritoriPresentation.sharePercent(player: 1, cpu: 1) == 50)
        #expect(ShiritoriPresentation.sharePercent(player: 0, cpu: 0) == 0)
    }

    @Test("結果の見出しは終わり方と勝敗の全組み合わせで空でなく、勝ち・負けが読み取れる")
    func resultTitlesCoverEveryEnding() {
        let endings: [ShiritoriEnding] = [.cpuStuck, .playerStuck, .timeUp, .playerHitN, .cpuHitN]
        for ending in endings {
            for win in [true, false] {
                // 「ん」の即決着は勝敗が終わり方で決まるので、起こり得ない組み合わせは見ない。
                if ending == .playerHitN && win { continue }
                if ending == .cpuHitN && !win { continue }
                if ending == .cpuStuck && !win { continue }
                if ending == .playerStuck && win { continue }
                let title = ShiritoriPresentation.resultTitle(ending: ending, didWin: win)
                #expect(title.contains(win ? "勝ち" : "負け"), "\(ending) win=\(win): \(title)")
            }
        }
    }

    @Test("内訳の 1 行に枚数・割合が入り、ノルマは時間切れのときだけ添える")
    func resultDetailMentionsCountsAndQuota() {
        let timeUp = ShiritoriPresentation.resultDetail(player: 3, cpu: 2, quota: .normal, ending: .timeUp)
        #expect(timeUp == "あなた3枚・CPU2枚（60%）／ノルマ: 取った札の過半数（5割より多く）でクリア")
        let stuck = ShiritoriPresentation.resultDetail(player: 3, cpu: 2, quota: .normal, ending: .cpuStuck)
        #expect(stuck == "あなた3枚・CPU2枚（60%）")
    }

    @Test("案内: 自分の番は受ける字を出し、CPU の番は考え中")
    func promptShowsTheRequiredKana() {
        #expect(ShiritoriPresentation.prompt(tail: "ご", isPlayerTurn: true, phase: .playing) == "「ご」からはじまる札を取ろう")
        #expect(ShiritoriPresentation.prompt(tail: "ご", isPlayerTurn: false, phase: .playing) == "CPUが考え中…")
        #expect(ShiritoriPresentation.prompt(tail: nil, isPlayerTurn: true, phase: .idle) == "ゲームを始めよう")
    }

    @Test("出来事: お手つきは -5びょう、裏読みは「うらよみ！」が付く")
    func eventText() {
        #expect(ShiritoriPresentation.eventText(.miss) == "おてつき！ -5びょう")
        #expect(ShiritoriPresentation.eventText(.played(by: .player, reading: "どらむ", isAlternate: true)) == "あなた：「どらむ」 うらよみ！")
        #expect(ShiritoriPresentation.eventText(.played(by: .cpu, reading: "ごりら", isAlternate: false)) == "CPU：「ごりら」")
    }

    @Test("VoiceOver: 札は名前と読み、取られていれば誰が取ったか。取れるかどうかは教えない")
    func slotLabels() {
        let card = ShiritoriCard(.apple, "りんご")
        #expect(ShiritoriPresentation.slotLabel(ShiritoriSlot(card: card)) == "りんご、りんご")
        #expect(ShiritoriPresentation.slotLabel(ShiritoriSlot(card: card, owner: .player)) == "りんご、りんご、あなたが取りました")
        #expect(ShiritoriPresentation.slotLabel(ShiritoriSlot(card: card, owner: .cpu)) == "りんご、りんご、CPUが取りました")
        #expect(ShiritoriPresentation.currentLabel(card: nil, reading: "") == "場の札はまだありません")
        #expect(ShiritoriPresentation.currentLabel(card: card, reading: "りんご") == "場の札はりんご、読みはりんご")
    }
}
