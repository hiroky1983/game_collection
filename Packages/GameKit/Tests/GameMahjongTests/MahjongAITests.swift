import Testing
import Foundation
import MahjongTiles
@testable import GameMahjong

/// CPU の打牌選択と立直判断を、固定した手牌で直接確かめる（#1390）。
///
/// 期待値はすべて手で数えた値（牌姿は `123m456p789s1z` 記法。1z=東 3z=西）。
/// 受け入れ枚数は「受け入れ牌ごとに 4 − 見えている枚数」の合計で、`visible` を渡さないときは
/// 自分の 14 枚だけが見えている扱いになる。**打牌だけでなくシャンテン数・受け入れ枚数まで
/// `Choice` 丸ごとで固定する**（打牌だけだと評価の中身が壊れても同じ牌を選んで素通りするため）。
@Suite("麻雀 CPU の打牌と立直（固定手牌・#1390）")
struct MahjongAIDiscardTests {

    private func hand(_ text: String) -> MahjongHand { MahjongNotation.hand(text) }
    private func tile(_ text: String) -> MahjongTile { MahjongNotation.tile(text) }

    // MARK: - chooseDiscard

    @Test("受け入れが広い両面を残す: 45s7s から 7s を切って 3s6s 待ち（8 枚）")
    func keepsWiderWait() {
        // 123m 456m 789p 東東 + 4s5s7s。
        // 7s 切り → 45s の両面で 3s・6s 待ち = 4 + 4 = 8 枚。
        // 4s 切り → 57s の嵌張で 6s 待ち = 4 枚。5s・東などを切ると 1 シャンテンに戻る。
        let choice = MahjongAI.chooseDiscard(from: hand("123456m789p457s11z"))
        #expect(choice == MahjongAI.Choice(tile: tile("7s"), shanten: 0, acceptance: 8))
    }

    @Test("シャンテン・受け入れが同じなら孤立した字牌を先に切る（単騎の 5m を残す）")
    func tieBreaksByIsolation() {
        // 123m 5m 456p 234s 789s 東。東切りでも 5m 切りでも単騎待ちの聴牌で、
        // 待ちは残り 3 枚ずつ（自分が 1 枚持っている）。孤立度は
        // 東 = 0（字牌は周りを見ない）、5m = −1（2 つ隣の 3m が 1 枚）なので東を切る。
        let choice = MahjongAI.chooseDiscard(from: hand("1235m456p234789s1z"))
        #expect(choice == MahjongAI.Choice(tile: tile("1z"), shanten: 0, acceptance: 3))
    }

    @Test("場に見えている枚数で受け入れを数え直し、残り枚数の多い単騎を選ぶ")
    func visibleTilesChangeTheChoice() {
        // 123m 456m 789p 456s 東 西。東切りなら西単騎、西切りなら東単騎。
        let base = hand("123456m789p456s13z")
        // 対照: 自分の手牌しか見えていなければどちらも残り 3 枚で、孤立度も同じ 0。
        // 先に調べる（添字の小さい）東が残る。
        #expect(MahjongAI.chooseDiscard(from: base)
            == MahjongAI.Choice(tile: tile("1z"), shanten: 0, acceptance: 3))

        // 河に西が 2 枚見えている（自分の 1 枚と合わせて 3 枚）。西単騎は残り 1 枚しかないので、
        // 西を切って東単騎（残り 3 枚）に受ける。
        var visible = base.counts
        visible[MahjongTileOrder.index(of: tile("3z"))] = 3
        #expect(MahjongAI.chooseDiscard(from: base, visible: visible)
            == MahjongAI.Choice(tile: tile("3z"), shanten: 0, acceptance: 3))
    }

    @Test("副露数を渡すと、門前 11 枚でも聴牌に取れる打牌を選ぶ")
    func meldCountIsHonoured() {
        // 1 副露 + 門前 123m 456p 東東 45s 西（11 枚）。西切りで 2 面子 + 副露 1 + 雀頭 + 45s の聴牌。
        // 待ちは 3s・6s で 8 枚。
        let concealed = hand("123m456p45s113z")
        let choice = MahjongAI.chooseDiscard(from: concealed, meldCount: 1)
        #expect(choice == MahjongAI.Choice(tile: tile("3z"), shanten: 0, acceptance: 8))
    }

    @Test("七対子の聴牌も打牌の候補に入る（6 対子 + 浮き 2 枚）")
    func sevenPairsTenpai() {
        // 11m 99m 11p 99p 11s 99s + 東・西。通常形では遠いが、どちらを切っても七対子の単騎聴牌。
        // 待ちは残り 3 枚ずつ、孤立度は字牌どうしで同じ 0 なので添字の小さい東を切る。
        let choice = MahjongAI.chooseDiscard(from: hand("1199m1199p1199s13z"))
        #expect(choice == MahjongAI.Choice(tile: tile("1z"), shanten: 0, acceptance: 3))
    }

    @Test("1 シャンテンの浮き牌 3 枚が同点なら添字の小さい 8s を切る（受け入れ 14 枚）")
    func oneShantenFloatingTiles() {
        // 123m 456m 789p 45s + 浮き 8s・東・西（雀頭なし）。
        // 浮き牌のどれを切っても 1 シャンテンで、受け入れは
        //   45s の両面 3s・6s（4 + 4）+ 残った浮き 2 枚の重なり（3 + 3）= 14 枚。
        // 45s を崩すと 2 シャンテンに戻るので候補にならない。
        // 孤立度は 8s（±2 に 6s・7s・9s なし）も字牌も 0 で同点 → 添字の小さい 8s（索子 < 字牌）。
        let choice = MahjongAI.chooseDiscard(from: hand("123456m789p458s13z"))
        #expect(choice == MahjongAI.Choice(tile: tile("8s"), shanten: 1, acceptance: 14))
    }

    // MARK: - shouldDeclareRiichi

    @Test("聴牌（両面待ち）なら立直する")
    func riichiWhenTenpai() {
        #expect(MahjongAI.shouldDeclareRiichi(hand: hand("123456m789p45s11z")))
    }

    @Test("1 シャンテンでは立直しない")
    func noRiichiWhenOneAway() {
        // 123m 456m 789p 45s 東 西: 雀頭が無く 1 シャンテン。
        #expect(!MahjongAI.shouldDeclareRiichi(hand: hand("123456m789p45s13z")))
    }

    @Test("七対子・国士無双の聴牌でも立直する")
    func riichiOnSpecialHands() {
        #expect(MahjongAI.shouldDeclareRiichi(hand: hand("1199m1199p1199s1z")))
        // 国士無双 13 面待ち（幺九牌 13 種を 1 枚ずつ）。
        #expect(MahjongAI.shouldDeclareRiichi(hand: hand("19m19p19s1234567z")))
    }

    @Test("CPU の手順どおり「打牌を選んでから立直判断」すると、聴牌打牌の直後に立直する")
    func riichiAfterChosenDiscard() {
        // MahjongModel+CPU と同じ順: 14 枚から打牌を選び、切った 13 枚で立直を判断する。
        let full = hand("123456m789p457s11z")
        let choice = MahjongAI.chooseDiscard(from: full)
        let rest = full.removing(choice.tile)
        #expect(MahjongAI.shouldDeclareRiichi(hand: rest))
        // 対照: 嵌張に取らず 5s を切ると 1 シャンテンで、立直しない。
        #expect(!MahjongAI.shouldDeclareRiichi(hand: full.removing(tile("5s"))))
    }
}
