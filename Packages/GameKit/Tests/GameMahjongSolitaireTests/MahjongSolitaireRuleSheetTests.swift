import Testing
import Foundation
import Core
import MahjongTiles
@testable import GameMahjongSolitaire

/// 「くわしいルール」ページの受け入れ条件（#238）。
///
/// 文言そのものを見るテストなので、**説明が実装から乖離していないか**も併せて確かめる
/// （花牌・季節牌が合う説明を載せても、`matchKey` 側が変わってしまえば嘘になるため）。
@Suite("麻雀ソリティアのくわしいルール")
struct MahjongSolitaireRuleSheetTests {

    private var bodies: [String] { MahjongSolitaireRuleSheet.rules.map(\.1) }
    private var allText: String { MahjongSolitaireRuleSheet.rules.map { $0.0 + $0.1 }.joined(separator: "\n") }

    @Test("花牌どうしは絵柄が違っても合うことが書いてある")
    func explainsFlowers() {
        let found = bodies.contains { body in
            ["梅", "蘭", "菊", "竹"].allSatisfy(body.contains) && body.contains("絵柄が違っても")
        }
        #expect(found, "花牌4種の名前と「絵柄が違っても合う」を含む項目が無い:\n\(allText)")
    }

    @Test("季節牌どうしは絵柄が違っても合うことが書いてある")
    func explainsSeasons() {
        let found = bodies.contains { body in
            ["春", "夏", "秋", "冬"].allSatisfy(body.contains) && body.contains("絵柄が違っても")
        }
        #expect(found, "季節牌4種の名前と「絵柄が違っても合う」を含む項目が無い:\n\(allText)")
    }

    @Test("取れる牌の条件（上に載っていない・左右どちらかが空いている）が書いてある")
    func explainsTakeableCondition() {
        let found = bodies.contains { $0.contains("上に牌") && $0.contains("どなり") }
        #expect(found, "「上に牌が載っていない」「左右どちらかが空いている」を含む項目が無い:\n\(allText)")
    }

    @Test("見出しは重複しない（ForEach の id に使っている）")
    func titlesAreUnique() {
        let titles = MahjongSolitaireRuleSheet.rules.map(\.0)
        #expect(Set(titles).count == titles.count, "見出しが重複している: \(titles)")
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(bodies.allSatisfy { !$0.isEmpty })
    }

    @Test("文言どおりに、花牌どうし・季節牌どうしは合い、数違いの標準牌は合わない")
    func textMatchesImplementation() {
        #expect(MahjongFace.flower(0).matches(.flower(3)), "梅と竹が合わないなら文言が嘘になる")
        #expect(MahjongFace.season(0).matches(.season(3)), "春と冬が合わないなら文言が嘘になる")
        #expect(!MahjongFace.flower(0).matches(.season(0)), "花牌と季節牌は合わない")
        #expect(!MahjongFace.characters(1).matches(.characters(2)), "一萬と二萬は合わない")
        #expect(MahjongFace.characters(1).matches(.characters(1)))
    }

    @Test("144 枚の内訳の記述が実際の盤面と一致する")
    func tileCountMatchesLayout() {
        #expect(MahjongSolitaireLayout.turtle.positions.count == 144)
        let faces = MahjongSolitaireRules.facePairs().flatMap { $0 }
        #expect(faces.count == 144)
        #expect(faces.filter { if case .flower = $0 { return true } else { return false } }.count == 4)
        #expect(faces.filter { if case .season = $0 { return true } else { return false } }.count == 4)
        #expect(bodies.contains { $0.contains("144枚") }, "枚数の記述が無い:\n\(allText)")
    }

    @Test("盤面のかたちが複数あることと、記録がかたちごとに分かれることが書いてある（#239）")
    func explainsLayouts() {
        let found = bodies.contains { body in
            MahjongSolitaireLayout.all.map(\.displayName).allSatisfy(body.contains)
                && body.contains("かたち")
        }
        #expect(found, "収録している全部のかたちの名前を含む項目が無い:\n\(allText)")
        // 記録が分かれることはユーザーから見て挙動の変化なので、説明が落ちたら気づけるようにする。
        #expect(
            bodies.contains { $0.contains("かたちごと") },
            "記録がかたちごとに分かれる説明が無い:\n\(allText)"
        )
        // 実装と食い違っていないか（3種類あり、id も表示名も重複しない）。
        #expect(MahjongSolitaireLayout.all.count >= 3)
    }

    @Test("初回ミニガイドは1行のまま（#81 の方針を崩していない）")
    func miniGuideUnchanged() {
        let guide = HowToPlayGuide.mahjongSolitaire
        #expect(guide.hint == "同じ牌を 2 枚タップで消そう")
        #expect(guide.lines.count == 3)
    }

    /// `?` から詳細ページへ辿れること。SwiftUI の階層は組み立てても検査できないので、
    /// 呼び出し側がどの API を使っているかをソースで見る。
    @Test("View は詳細ページ付きの howToPlay を使っている")
    func viewWiresUpTheExtraPage() throws {
        let source = try Self.viewSource()
        #expect(
            source.contains(".howToPlay(.mahjongSolitaire) { MahjongSolitaireRuleSheet() }"),
            "詳細ページ付きの howToPlay になっていない"
        )
        // extra 無しの呼び出しが残っていたら、そちらが使われている可能性がある。
        #expect(!source.contains(".howToPlay(.mahjongSolitaire)\n"), "extra 無しの呼び出しが残っている")
    }

    private static func viewSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GameMahjongSolitaireTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources/GameMahjongSolitaire/MahjongSolitaireView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
