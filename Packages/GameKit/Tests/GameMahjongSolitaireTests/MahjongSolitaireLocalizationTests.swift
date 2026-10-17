import Testing
import Core
@testable import MahjongTiles
@testable import GameMahjongSolitaire

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("麻雀ソリティア: 英語の文言")
struct MahjongSolitaireLocalizationTests {

    @Test("題名・かたちの名前に英語の訳がある")
    func englishTerms() {
        #expect(GameMahjongSolitaire.tr("麻雀ソリティア", language: .english) == "Mahjong Solitaire")
        #expect(GameMahjongSolitaire.tr("亀甲", language: .english) == "Turtle")
        #expect(GameMahjongSolitaire.tr("タイム %@", "1:23", language: .english) == "Time 1:23")
    }

    /// 記録の区分名は保存されるので、表示が英語でも日本語のまま（表示の英語化は #2168）。
    @Test("記録の区分名は日本語のまま")
    func recordLabelsStayJapanese() {
        #expect(MahjongSolitaireLayout.all.map(\.recordLabel) == ["亀甲", "ピラミッド", "十字"])
        #expect(MahjongSolitaireLayout.all.map(\.displayName) == ["亀甲", "ピラミッド", "十字"])
    }

    /// 牌の読み上げ名（MahjongTiles の表）。牌の面に描く漢字は絵柄なので訳さない。
    @Test("牌の読み上げ名に英語の訳がある")
    func tileNames() {
        #expect(MahjongTiles.tr("萬子の%lld", 3, language: .english) == "3 of Characters")
        #expect(MahjongTiles.tr("筒子の%lld", 3, language: .english) == "3 of Circles")
        #expect(MahjongTiles.tr("索子の%lld", 3, language: .english) == "3 of Bamboo")
        #expect(MahjongTiles.tr("東", language: .english) == "East Wind")
        #expect(MahjongTiles.tr("白", language: .english) == "White Dragon")
        // 日本語では従来の読み上げ文のまま（四人打ちの麻雀と共有）。
        #expect(MahjongFace.characters(3).displayName == "萬子の3")
        #expect(MahjongFace.standard(.wind(0)).displayName == "字牌の東")
        #expect(MahjongFace.flower(0).displayName == "花牌の梅")
    }
}
