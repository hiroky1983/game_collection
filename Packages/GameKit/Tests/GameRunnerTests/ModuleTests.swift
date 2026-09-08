import Core
import Testing
@testable import GameRunner

@Suite("チャリンコおじさんのモジュール登録")
struct RunnerModuleTests {

    /// `RunnerModule.id` は LP 照合スクリプトの都合で**文字列リテラル**で書いてあり、
    /// `RunnerModel.gameID` とは別々に書かれている。食い違うと
    /// 「記録・解析・中断データが別のキーに書かれる」という静かな故障になるので、ここで縛る。
    @Test("モジュールの id と Model の gameID が一致する")
    func idsMatch() {
        #expect(RunnerModule().id == RunnerModel.gameID)
        #expect(RunnerModule().id == "runner")
    }

    /// 既存タイトル名（Spicysoft の `チャリ走` 等）は、表示に出る文言だけでなく
    /// **ID と URL スラッグにも入れない**（#494 の権利チェック）。
    @Test("表示名・説明・ID に使用禁止語が入っていない")
    func avoidsTrademarkedTerms() {
        let module = RunnerModule()
        let surfaces = [module.id, module.title, module.description]
        for forbidden in [
            "チャリ走", "チャリソウ",
            "temple run", "templerun",
            "チャリヒーロー", "チャリの達人",
        ] {
            for surface in surfaces {
                #expect(
                    !surface.lowercased().contains(forbidden.lowercased()),
                    "使用禁止語 '\(forbidden)' が '\(surface)' に入っている"
                )
            }
        }
        #expect(module.title == "チャリンコおじさん", "表示名は権利チェックで採用した名前")
    }

    @Test("遊び方ガイドがこのゲームの ID に紐づいている")
    func howToPlayGuideIsWired() {
        #expect(HowToPlayGuide.runner.gameID == RunnerModel.gameID)
        #expect(HowToPlayGuide.all.contains { $0.gameID == RunnerModel.gameID })
    }

    @Test("リーダーボードは到達ステージ数（High to Low）に紐づいている")
    func leaderboardIsWired() {
        let entry = GameCenterLeaderboard.score(
            gameID: RunnerModel.gameID,
            outcome: .win,
            score: GameScore(metric: .points, points: 7)
        )
        #expect(entry == GameCenterScore(leaderboardID: GameCenterLeaderboard.runnerStage, value: 7))
        #expect(GameCenterLeaderboard.allIDs.contains(GameCenterLeaderboard.runnerStage))
    }
}
