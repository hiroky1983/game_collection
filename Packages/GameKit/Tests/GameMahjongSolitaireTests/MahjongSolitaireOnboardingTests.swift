import Testing
import Core
import MahjongTiles
@testable import GameMahjongSolitaire

/// 図で見る「はじめての遊び方」（#2825）の図が、実装のルールのとおりになっていること。
@MainActor
@Suite("麻雀ソリティア: はじめての遊び方")
struct MahjongSolitaireOnboardingTests {
    private let layout = MahjongSolitaireLayout.turtle

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(MahjongSolitaireOnboarding.guide.isWellFormed)
        #expect(MahjongSolitaireOnboarding.guide.gameID == MahjongSolitaireModule().id)
    }

    @Test("同じ絵柄だけが合い、花牌どうし・季節牌どうしは絵柄がちがっても合う")
    func matching() {
        #expect(MahjongFace.circles(3).matches(.circles(3)))
        #expect(!MahjongFace.circles(3).matches(.circles(4)))
        #expect(!MahjongFace.circles(3).matches(.bamboos(3)))
        #expect(MahjongFace.flower(0).matches(.flower(1)))
        #expect(MahjongFace.season(0).matches(.season(3)))
        #expect(!MahjongFace.flower(0).matches(.season(0)))
    }

    @Test("取れる牌: 上に牌が乗っていると取れず、両どなりがふさがっていても取れない")
    func freeTiles() throws {
        let all = [Bool](repeating: true, count: layout.count)
        let relations = layout.relations

        // 上に牌が乗っている牌は、左右が空いていても取れない。乗っている牌をどけると取れる。
        let covered = try #require((0..<layout.count).first {
            !relations.above[$0].isEmpty && (relations.left[$0].isEmpty || relations.right[$0].isEmpty)
        })
        #expect(!MahjongSolitaireRules.isFree(covered, remaining: all, layout: layout))
        var uncovered = all
        for above in relations.above[covered] { uncovered[above] = false }
        #expect(MahjongSolitaireRules.isFree(covered, remaining: uncovered, layout: layout))

        // 上は空いていても、左右の両方がふさがっている牌は取れない。片側をどけると取れる。
        let pinned = try #require((0..<layout.count).first {
            relations.above[$0].isEmpty && !relations.left[$0].isEmpty && !relations.right[$0].isEmpty
        })
        #expect(!MahjongSolitaireRules.isFree(pinned, remaining: all, layout: layout))
        var sideOpen = all
        for left in relations.left[pinned] { sideOpen[left] = false }
        #expect(MahjongSolitaireRules.isFree(pinned, remaining: sideOpen, layout: layout))
    }

    @Test("全部で 144 枚。すべて消すとクリア")
    func fullSet() {
        #expect(MahjongSolitaireLayout.all.allSatisfy { $0.count == 144 })
        #expect(MahjongSolitaireRules.facePairs().count * 2 == 144)
    }

    @Test("手詰まり: 取れる牌に同じ絵柄が無いと、取れる組が無い")
    func deadlock() throws {
        let a = try #require(layout.index(layer: 0, hx: 2, hy: 0))
        let b = try #require(layout.index(layer: 0, hx: 24, hy: 0))
        let c = try #require(layout.index(layer: 4, hx: 13, hy: 7))
        var faces = [MahjongFace?](repeating: nil, count: layout.count)
        faces[a] = .characters(1)
        faces[b] = .circles(2)
        faces[c] = .bamboos(7)
        #expect(MahjongSolitaireRules.availablePairs(faces: faces, layout: layout).isEmpty)
        #expect(MahjongSolitaireModel(services: nil, faces: faces).isDeadlocked)
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        for text in MahjongSolitaireOnboarding.guide.texts {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
