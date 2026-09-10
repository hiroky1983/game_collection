import Foundation
import Testing

/// ゲーム画面の共通枠（#528）が、全ゲームで**本当に**共通のものを通っているかを見る。
///
/// 枠の中身（背景・戻る・表示名・ナビバーの構成）は値として取り出せないので、
/// 盤ゲームの `BoardGameChromeSourceTests` と同じくソース走査で固定する。
///
/// 走査は**ゲームごとのディレクトリ一式**を読む。1 ファイルを名指しすると、View を
/// 分割した瞬間に検証対象がずれて green のまま空振りする（#516 と同型の失敗）。
@Suite("ゲーム画面の共通枠")
struct GameChromeSourceTests {

    /// `Sources/` 直下のゲームごとのディレクトリ（Core と牌の描画部品を除く）。
    private static let gameDirectories: [(name: String, files: [String])] = {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GameChromeTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources")
        let excluded: Set<String> = ["Core", "MahjongTiles"]
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: sources.path)) ?? [])
            .filter { $0.hasPrefix("Game") && !excluded.contains($0) }
            .sorted()
        return names.map { name in
            let dir = sources.appendingPathComponent(name)
            let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
                .filter { $0.hasSuffix(".swift") }
                .sorted()
                .compactMap { try? String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8) }
            return (name, files)
        }
    }()

    @Test("走査の前提: ゲームのディレクトリが読めている")
    func directoriesAreFound() {
        #expect(Self.gameDirectories.count >= 20,
                "ゲームのディレクトリが \(Self.gameDirectories.count) 個しか見つからない（走査の前提が壊れている）")
        #expect(Self.gameDirectories.allSatisfy { !$0.files.isEmpty })
    }

    /// 新しいゲームを足すときに枠を写し忘れると、戻るボタンや背景が 1 本だけ欠ける。
    /// **ゲーム 1 本につき 1 回**であることまで見る（画面を分けたときの二重適用も防ぐ）。
    @Test("どのゲームもちょうど 1 回 gameChrome を通る")
    func everyGameUsesGameChromeOnce() {
        for game in Self.gameDirectories {
            let count = game.files.reduce(0) { $0 + $1.components(separatedBy: ".gameChrome(title:").count - 1 }
            #expect(count == 1, "\(game.name) の gameChrome の適用が \(count) 回（1 回であるべき）")
        }
    }

    /// 枠の中身を各ゲームが自前で書き直していないこと。ここが 1 本でも残っていると、
    /// 「共通化したのに片方だけ古いまま」という #530 と同じ状態に戻る。
    @Test("枠の中身はゲーム側に書き写されていない")
    func chromeInternalsStayInCore() {
        // 戻るボタンの自前化と評価リクエストの紐づけは Core の gameChrome だけが持つ。
        for forbidden in ["navigationBarBackButtonHidden", ".reviewRequestPrompt("] {
            for game in Self.gameDirectories {
                let hit = game.files.contains { $0.contains(forbidden) }
                #expect(hit == false, "\(game.name) が \(forbidden) を自前で持っている")
            }
        }
    }

    /// 盤の下の操作エリアは、ひな形と実物を同じ組み方に通すのが要点（#148）。
    /// 各ゲームが `ZStack` + 隠しひな形を書き写す形に戻っていないことを見る。
    @Test("操作エリアの高さのひな形はゲーム側に書き写されていない")
    func controlAreaTemplateStaysInCore() {
        for game in Self.gameDirectories {
            let hit = game.files.contains { $0.contains("RecommendationCard.heightPlaceholder") }
            #expect(hit == false, "\(game.name) が高さのひな形を自前で組んでいる")
        }
    }
}
