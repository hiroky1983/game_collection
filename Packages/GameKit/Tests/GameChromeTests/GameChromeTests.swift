import Foundation
import Testing
import GameKitTestSupport

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
        let sources = SourceScan.packageRoot.appendingPathComponent("Sources")
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
        // ナビバーの背景とボタン色も Core に固定（#1412）。ゲーム側の上書きは 1 本だけ違う色に戻る。
        for forbidden in ["navigationBarBackButtonHidden", ".reviewRequestPrompt(",
                          ".toolbarBackground(", "matchesNavigationBarBackground"] {
            for game in Self.gameDirectories {
                let hit = game.files.contains { $0.contains(forbidden) }
                #expect(hit == false, "\(game.name) が \(forbidden) を自前で持っている")
            }
        }
    }

    /// ヘッダー右の「役の早見表」「新規」は `gameChrome` の引数で渡し、並び（役 → ？ → 新規）と絵柄を
    /// Core で固定する（#1418）。ゲーム側が自前のツールバー項目に書き直すと並びと絵柄がばらつく。
    @Test("役の早見表と新規ボタンはゲーム側で自前のアイコンに書き直されていない")
    func referenceAndNewGameStayInCore() {
        // ツールバー項目（`ToolbarItem(placement: .primaryAction)` から続く 400 文字）だけを見る。
        // 開始シート・盤面選択メニューなど、ツールバー以外の同じ絵柄・文言は対象外。
        let forbidden = ["list.bullet.rectangle", "list.number", "questionmark.circle",
                         "Label(\"新規対局\"", "Label(\"新規ゲーム\"", "Label(\"はじめから\"", "Label(\"リセット\"", "Label(\"新規\""]
        for game in Self.gameDirectories {
            for file in game.files {
                for part in file.components(separatedBy: "ToolbarItem(placement: .primaryAction)").dropFirst() {
                    let head = String(part.prefix(400))
                    for word in forbidden {
                        #expect(head.contains(word) == false, "\(game.name) が \(word) をツールバーに自前で置いている")
                    }
                }
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

    /// レコメンドのカード（#52）と難易度の階段（#722）はレコメンドの枠に相乗りしている。
    /// 枠を持たない終局画面が 1 本でもあると、そのゲームだけレコメンドも階段も出ない。
    @Test("どのゲームの終局画面にもレコメンドの枠がある")
    func everyGameHasRecommendationSlot() {
        let entries = ["RecommendationSlot(", "RecommendationArea(", "GameControlArea("]
        for game in Self.gameDirectories {
            let hit = game.files.contains { file in entries.contains { file.contains($0) } }
            #expect(hit, "\(game.name) の終局画面にレコメンドの枠が無い（レコメンドも階段も出ない）")
        }
    }
}
