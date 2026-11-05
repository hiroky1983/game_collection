import Testing
@testable import Core
import CoreEngine
@testable import GameTsunagi
import CoreTestSupport
import GameKitTestSupport

@Suite("線つなぎのモジュール")
@MainActor
struct TsunagiModuleTests {
    @Test("登録口の ID と Model の gameID・遊び方ガイドは同じ")
    func idsMatch() {
        #expect(TsunagiModule().id == TsunagiModel.gameID)
        #expect(HowToPlayGuide.tsunagi.gameID == TsunagiModule().id)
        #expect(HowToPlayGuide.all.contains(.tsunagi))
        // 順位表は持たない（倉庫の段階で Game Center の登録を増やさない）。
        #expect(GameCenterLeaderboard.score(
            gameID: TsunagiModule().id, outcome: .win,
            score: GameScore(metric: .fewestMoves, moves: 5, variant: "5x5")
        ) == nil)
    }

    @Test("表示名・説明・ルールに他社の名称を含めない（Issue #2235 の権利チェック）")
    func noTrademarkedWords() {
        let module = TsunagiModule()
        #expect(module.title == "線つなぎ")
        #expect(!module.description.isEmpty)
        let guide = HowToPlayGuide.tsunagi
        let english = [GameTsunagi.tr("線つなぎ", language: .english),
                       Core.tr("線つなぎの遊び方", language: .english)]
        let texts = [module.title, module.description, guide.title, guide.hint]
            + guide.lines + guide.items.map(\.text) + guide.notes + english
        // 「ナンバーリンク」はニコリのペンシルパズルの名前（愛称「ナンリン」）。"Flow" は他社のアプリ名に紛れる。
        for banned in ["ナンバーリンク", "ナンリン", "Numberlink", "Number Link", "ニコリ", "Nikoli",
                       "Flow", "®", "™"] {
            #expect(texts.allSatisfy { !$0.contains(banned) }, "「\(banned)」を含む文言がある")
        }
        // 英語の名前に "Line" を使わない（国内の大手メッセージアプリの名前と紛れる）。
        #expect(!english[0].localizedCaseInsensitiveContains("line"))
    }

    @Test("画面は共通の枠・レコメンド枠・図入りの遊び方を使い、広告の救済は持たない")
    func viewUsesSharedParts() throws {
        let code = SourceScan.strippingComments(try SourceScan.moduleSources("GameTsunagi"))
        #expect(code.components(separatedBy: ".gameChrome(title:").count - 1 == 1)
        #expect(code.contains("RecommendationArea("))
        #expect(code.contains("BannerSlot("))
        #expect(code.contains("HowToPlayHint(.tsunagi"))
        #expect(code.contains(".howToPlay(HowToPlayGuide.tsunagi.illustrated(TsunagiHowToFigures.items))"))
        #expect(code.contains(".gameClearCard(") && code.contains("record: model.recordResult"), "結果は共通のクリアカードで、記録も載せる（#3059）")
        #expect(!code.contains("Rescue.request("), "広告の救済は足さない（#2235 では広告を追加しない）")
        #expect(!code.contains("showRewardedAd("))
        #expect(!code.contains("withAnimation("), "アニメーションは gameAnimation 経由")
        #expect(!code.contains("Image(\"") && !code.contains("UIImage("), "絵はコード描画だけで、画像を持たない")
        #expect(code.contains("level: size.analyticsLevel"), "盤の大きさを game_start の level に載せる")
        #expect(code.contains("gameDidStart(") && code.contains("gameDidRestart(")
                && code.contains("gameDidProgress(") && code.contains("gameDidFinish("))
    }

    @Test("遊び方の図は項目と同じ数で、図の問題は形が正しく解が 1 つ")
    func howToFigures() {
        #expect(TsunagiHowToFigures.items.count == HowToPlayGuide.tsunagi.items.count)
        #expect(TsunagiLogic.isWellFormed(TsunagiHowToFigures.sample))
        #expect(TsunagiLogic.countSolutions(TsunagiHowToFigures.sample, limit: 3) == 1)
    }

    @Test("中断データ: 線を 1 本でも引いた盤だけが「続き」")
    func resumableSnapshot() {
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService())
        let module = TsunagiModule()
        let model = TsunagiModel(services: services, seed: 4)
        #expect(!module.hasResumableSnapshot(in: store))
        #expect(module.hasUntouchedSnapshot(in: store))
        let path = model.puzzle.solution[0]
        model.beginStroke(at: path[0])
        model.extendStroke(to: path[1])
        model.endStroke()
        #expect(module.hasResumableSnapshot(in: store))
        #expect(!module.hasUntouchedSnapshot(in: store))
    }

    @Test("記録の区分名は大きさで、英語でも日本語でも同じ表記")
    func recordVariantLabels() {
        for size in TsunagiSize.allCases {
            let key = "tsunagi#\(size.rawValue)"
            #expect(RecordVariantLabels.label(recordKey: key, language: .english) == size.label)
            #expect(RecordVariantLabels.label(recordKey: key, language: .japanese) == size.label)
            #expect(size.recordVariantLabel == size.label)
        }
        #expect(RecordVariantLabels.label(recordKey: "tsunagi#9x9", language: .english) == nil)
    }
}

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("線つなぎ: 英語の文言と読み上げ")
struct TsunagiLocalizationTests {
    @Test("題名・読み上げ・クリア表示に英語の訳がある")
    func englishTerms() {
        #expect(GameTsunagi.tr("線つなぎ", language: .english) == "Connect Pairs")
        #expect(GameTsunagi.tr("%1$lld行%2$lld列、%3$lldの点", 2, 3, 4, language: .english) == "Row 2, column 3, dot 4")
        #expect(GameTsunagi.tr("%lld手でつなぎました", 1, language: .english) == "Connected in 1 move")
        #expect(GameTsunagi.tr("%lld手でつなぎました", 12, language: .english) == "Connected in 12 moves")
        #expect(Core.tr("線つなぎの遊び方", language: .english) == "How to Play Connect Pairs")
    }

    @Test("読み上げは色でなく数字で、点・線・空き・つながりを区別する")
    func accessibilityLabels() {
        #expect(TsunagiAccessibility.cellLabel(cell: 7, side: 5, number: 3, isEndpoint: true, isConnected: true)
                == "2行3列、3の点、つながった")
        #expect(TsunagiAccessibility.cellLabel(cell: 0, side: 5, number: 2, isEndpoint: false, isConnected: false)
                == "1行1列、2の線、つながっていない")
        #expect(TsunagiAccessibility.cellLabel(cell: 24, side: 5, number: nil, isEndpoint: false, isConnected: false)
                == "5行5列、空き")
        #expect(TsunagiAccessibility.cellLabel(cell: 1, side: 5, number: 1, isEndpoint: false, isConnected: false, isSelected: true)
                .hasSuffix("選択中（隣のマスを選ぶと線がのびます）"))
        #expect(TsunagiAccessibility.progressLabel(connected: 2, pairs: 5, filled: 10, cells: 25)
                == "つながった数字 2/5、うまったマス 10/25")
    }
}
