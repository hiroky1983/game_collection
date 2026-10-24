import Testing
import Foundation
import Core
@testable import GameRunner

/// チャリンコおじさんの英語の文言（多言語④ #2167）。`swift test` は常に日本語なので、言語を明示して表を引く。
@Suite("チャリンコおじさん: 英語の文言（#2167）")
struct RunnerEnglishTests {
    private func en(_ key: String, _ arguments: any CVarArg...) -> String {
        GameRunner.tr.string(key, arguments: arguments, language: .english)
    }

    /// 1 コマ 1.6 秒で読み切れる長さ。英語は日本語より横に長いので、文字数の上限は別に持つ
    /// （日本語は `RunnerStory.lineLimit` = 24 文字。英語は SE の幅で 2 行に収まる 48 文字）。
    @Test("ストーリーの台詞は全部英語があり、短い")
    func storyLinesInEnglish() {
        for scene in RunnerStoryScene.all {
            #expect(GameRunner.tr.hasTranslation(scene.title, language: .english) || scene.title.contains("おわり"),
                    "\(scene): 題に英語が無い")
            for panel in scene.panels {
                #expect(GameRunner.tr.hasTranslation(panel.line, language: .english), "「\(panel.line)」に英語が無い")
                let line = en(panel.line)
                #expect(!line.isEmpty && line.count <= 48, "「\(line)」が \(line.count) 文字")
            }
        }
    }

    @Test("世界の名前と締めの題")
    func worldNamesInEnglish() {
        for world in RunnerWorld.allCases {
            #expect(GameRunner.tr.hasTranslation(world.displayName, language: .english), "\(world)")
        }
        #expect(en("%@のおわり", "Harbor Town") == "Harbor Town Finale")
    }

    @Test("説明のステージ数は本編の面数と一致する（英語も）")
    func descriptionStageCountInEnglish() {
        #expect(en("タップで跳んで48ステージを走りぬけよう").contains("\(RunnerRules.stageCount)"))
    }

    @Test("読み上げの数は 1 のとき単数")
    func pluralsInEnglish() {
        #expect(en("無敵 あと%lld秒", 1) == "Invincible, 1 second left")
        #expect(en("無敵 あと%lld秒", 3) == "Invincible, 3 seconds left")
        #expect(en("%lldメートルでミスしました", 120) == "Wiped out at 120 meters")
        #expect(en("ステージ %1$lld / %2$lld", 3, 42) == "Stage 3 / 42")
    }
}
