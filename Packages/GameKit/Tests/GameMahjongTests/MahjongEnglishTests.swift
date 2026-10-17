import Core
import Foundation
import Testing
import MahjongTiles
@testable import GameMahjong

/// 麻雀の英語表示（#2166）。`AppLanguageStore.shared` は書き換えず、`language: .english` を明示して引く。
@Suite("麻雀: 英語の文言（#2166）")
struct MahjongEnglishTests {

    @Test("役名・鳴き・点数の呼び名は英語圏のリーチ麻雀の表記（会長決定）")
    func terms() {
        #expect(GameMahjong.tr("立直", language: .english) == "Riichi")
        #expect(GameMahjong.tr("断幺九", language: .english) == "Tanyao")
        #expect(GameMahjong.tr("門前清自摸和", language: .english) == "Menzen Tsumo")
        #expect(GameMahjong.tr("国士無双", language: .english) == "Kokushi Musou")
        #expect(GameMahjong.tr("役牌 自風", language: .english) == "Yakuhai: Seat Wind")
        #expect(GameMahjong.tr("チー", language: .english) == "Chii")
        #expect(GameMahjong.tr("ロン", language: .english) == "Ron")
        #expect(GameMahjong.tr("満貫", language: .english) == "Mangan")
        #expect(GameMahjong.tr("流局", language: .english) == "Exhaustive draw")
        #expect(GameMahjong.tr("麻雀", language: .english) == "Mahjong")
    }

    @Test("書式・語順・複数形")
    func formats() {
        #expect(GameMahjong.tr("%lld点", 1, language: .english) == "1 pt")
        #expect(GameMahjong.tr("%lld点", 25000, language: .english) == "25000 pts")
        #expect(GameMahjong.tr("%1$lld飜（鳴き%2$lld飜）", 6, 5, language: .english) == "6 Han (open: 5)")
        #expect(GameMahjong.tr("%1$lld飜（鳴き%2$lld飜）", 6, 5, language: .japanese) == "6飜（鳴き5飜）")
        #expect(GameMahjong.tr("%1$@ → %2$@のロン", "CPU1", "You", language: .english) == "Ron: CPU1 → You")
        #expect(GameMahjong.tr("山の残り%lld枚", 1, language: .english) == "1 tile left in the wall")
        #expect(GameMahjong.tr("2位", language: .english) == "2nd")
    }

    @Test("役牌の保存用の牌名は日本語で固定し、日本語の読み上げ名と一致する")
    func tileStoredNames() {
        #expect(MahjongTile.characters(1).storedName == "萬子の1")
        #expect(MahjongTile.dragon(0).storedName == "字牌の中")
        // swift test は常に日本語なので、表示名（MahjongTiles の tr）とも一致する。
        for tile in MahjongTile.all {
            #expect(tile.storedName == tile.displayName, "\(tile)")
        }
    }

    @Test("中断データに入る役・満貫の保存値（日本語）は、日本語の表示では 1 文字も変わらない")
    func storedValuesRoundTripInJapanese() {
        // `swift test` は常に日本語（AppLanguageStore を bootstrap しない）。
        #expect(MahjongHandResult.displayYakuLine("立直 1飜") == "立直 1飜")
        #expect(MahjongHandResult.displayYakuLine("役牌 自風 1飜") == "役牌 自風 1飜")
        #expect(MahjongHandResult.displayYakuLine("役牌 字牌の中 1飜") == "役牌 字牌の中 1飜")
        #expect(MahjongHandResult.displayYakuLine("国士無双 役満") == "国士無双 役満")
        #expect(MahjongHandResult.displayYakuLine("ドラ 3飜") == "ドラ 3飜")
        #expect(MahjongHandResult.displayLimitName("跳満") == "跳満")
        #expect(MahjongHandResult.displayLimitName("2倍役満") == "2倍役満")
    }
}
