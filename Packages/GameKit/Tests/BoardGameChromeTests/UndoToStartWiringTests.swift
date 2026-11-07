import Testing
import Foundation
import GameKitTestSupport

/// 「待った」を持つ盤ゲームは、開始局面まで戻したとき離脱の印も戻す（#3398）。
///
/// 判定（開始局面か）はゲームごとに違うので呼び出しは各 Model に残る。そのぶん 1 本抜けると
/// 手を指していない盤が `game_end`（quit）に数えられるため、ソースの形で固定する（#3133・#3200 の取りこぼしの再発防止）。
@Suite("待ったと離脱の印の結線（#3398）")
struct UndoToStartWiringTests {
    /// 設計上「待った」で離脱の印を戻さないゲームと、その理由。
    private static let exempt: [String: String] = [
        "Game2048": "手数の概念が盤の進行と一致せず、開始局面へ戻す設計ではない",
        "GameSolitaire": "一度立った印は下ろさない設計（#500。SolitaireModel の undo コメント）",
        "GameFreeCell": "ソリティア系と同じ（#500）",
        "GameSpider": "ソリティア系と同じ（#500）",
        "GameMahjongSolitaire": "ソリティア系と同じく一度立った印は下ろさない",
        "GameSudoku": "盤は最初から埋まっており、待ったは入力の取り消しで開始局面の概念が無い",
        "GameCatPuzzle": "一手ごとの巻き戻しで、離脱の印は一度立ったら下ろさない",
    ]

    private static func modulesWithUndo() throws -> [String] {
        let sources = packageSourcesDirectory
        let names = try FileManager.default.contentsOfDirectory(atPath: sources.path).sorted()
        return try names.filter { name in
            guard name != "Core" else { return false }   // プロトコル定義だけで Model ではない
            guard let text = try? SourceScan.moduleSources(name) else { return false }
            let code = SourceScan.strippingComments(text)
            return code.contains("var canUndo") && code.contains("func undo")
        }
    }

    private static var packageSourcesDirectory: URL {
        SourceScan.packageRoot.appendingPathComponent("Sources")
    }

    @Test("canUndo と undo を持つモジュールは gameDidUndoToStart を呼ぶ（許可リスト以外）")
    func undoModelsCallUndoToStart() throws {
        let modules = try Self.modulesWithUndo()
        #expect(modules.count >= 10, "走査が空振りしていない（実際: \(modules.count)）")
        for module in modules where Self.exempt[module] == nil {
            let code = SourceScan.strippingComments(try SourceScan.moduleSources(module))
            #expect(code.contains("gameDidUndoToStart"), "\(module) は待ったで開始局面まで戻しても離脱の印を戻さない")
        }
    }

    @Test("許可リストは実在し、本当に呼んでいないゲームだけが載っている")
    func exemptListIsNotStale() throws {
        let modules = try Self.modulesWithUndo()
        for (module, _) in Self.exempt {
            #expect(modules.contains(module), "\(module) は待ったを持たない。許可リストから外す")
            let code = SourceScan.strippingComments(try SourceScan.moduleSources(module))
            #expect(!code.contains("gameDidUndoToStart"), "\(module) は呼んでいる。許可リストから外す")
        }
    }
}
