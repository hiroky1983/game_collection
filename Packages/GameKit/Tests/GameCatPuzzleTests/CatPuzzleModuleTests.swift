import Testing
@testable import Core
import CoreEngine
@testable import GameCatPuzzle
import CoreTestSupport
import GameKitTestSupport

@Suite("おじさんちのねこさがしのモジュール")
@MainActor
struct CatPuzzleModuleTests {
    @Test("登録口の ID と Model の gameID・遊び方ガイドは同じ")
    func idsMatch() {
        #expect(CatPuzzleModule().id == CatPuzzleModel.gameID)
        #expect(HowToPlayGuide.catPuzzle.gameID == CatPuzzleModule().id)
        #expect(HowToPlayGuide.all.contains(.catPuzzle))
        // 順位表は持たない（倉庫の段階で Game Center の登録を増やさない）。
        #expect(GameCenterLeaderboard.score(
            gameID: CatPuzzleModule().id, outcome: .win,
            score: GameScore(metric: .shortestTime, seconds: 90, variant: "normal")
        ) == nil)
    }

    @Test("表示名・説明・ルール・部屋の名前に他社の名称を含めない（Issue #2250 の権利の整理）")
    func noTrademarkedWords() {
        let module = CatPuzzleModule()
        #expect(module.title == "おじさんちのねこさがし")
        #expect(!module.description.isEmpty)
        let guide = HowToPlayGuide.catPuzzle
        let english = [GameCatPuzzle.tr("おじさんちのねこさがし", language: .english),
                       GameCatPuzzle.tr("家のどこかに隠れた飼い猫を、部屋ごとに1匹ずつ見つけよう", language: .english),
                       Core.tr("おじさんちのねこさがしの遊び方", language: .english)]
        let texts = [module.title, module.description, guide.title, guide.hint]
            + guide.lines + guide.items.map(\.text) + guide.notes + english
            + CatPuzzleHouse.rooms.map(\.name)
        // 他社の猫パズルアプリの名前と、同じ型のパズルの他社名。
        for banned in ["Nekodoku", "Catdoku", "Meowdoku", "Petdoku", "Jindoblu", "Queens", "LinkedIn",
                       "ネコドク", "キャットドク", "®", "™"] {
            #expect(texts.allSatisfy { !$0.localizedCaseInsensitiveContains(banned) }, "「\(banned)」を含む文言がある")
        }
    }

    @Test("画面は共通の枠・操作の段・レコメンド枠・図入りの遊び方・リワード広告の部品を使う")
    func viewUsesSharedParts() throws {
        let code = SourceScan.strippingComments(try SourceScan.moduleSources("GameCatPuzzle"))
        #expect(code.components(separatedBy: ".gameChrome(title:").count - 1 == 1)
        #expect(code.contains("GameStatusBar {"))
        #expect(code.contains("GameOverflowBar("))
        // 終局後は他のゲームと同じ「同じ条件でもう一回」「設定を変える」とレコメンド（会長 QA 2026-10-21・build 42）。
        #expect(code.contains("GameControlArea(isFinished:"))
        #expect(code.contains("GameReplayBar("))
        #expect(code.contains("BannerSlot("))
        #expect(code.contains("HowToPlayHint(.catPuzzle"))
        // 後ろに .onboarding(...)（#2826）が続くので、閉じ括弧の手前までで見る。
        #expect(code.contains(".howToPlay(HowToPlayGuide.catPuzzle.illustrated(CatPuzzleHowToFigures.items)"))
        #expect(code.contains("RecordLabel("))
        #expect(code.contains(".gameClearCard(isPresented:"))
        // ヒントの広告は他のゲームと同じ部品（`RewardedRescue`）で、局ガード・失敗アラート・視聴中の計時停止まで揃える。
        #expect(code.contains("var hintRescue = RewardedRescue()"))
        #expect(code.contains("hintRescue.request(") && code.contains("purpose: .hint") && code.contains("guardedBy: .checkedByGrant"))
        #expect(code.contains(".rewardedRescueAlerts(\n            hintRescue,"))
        #expect(code.contains("rescues: [hintRescue, continueRescue]"), "広告の視聴中は計時を止める")
        // 3 回目のミスで出すのは負けの結果カード 1 枚だけで、その中でコンティニューかあきらめるかを選ぶ（#2904）。
        // 広告は押したときだけ（局ガードつき）出し、提案の計測も揃える（#2780）。
        #expect(code.contains(".boardGameResultCard(isPresented: Self.showsFailCard(model, closed: failCardClosed))"))
        #expect(!code.contains("RewardedContinueOverlay("), "ミス 3 回のダイアログを 2 枚にしない")
        #expect(code.contains("continueRescue.request(") && code.contains("purpose: .continue"))
        #expect(code.contains(".rewardOffer(continueRescue, for: .continue, isPresented: model.isOfferingContinue"))
        #expect(code.contains(".rewardedRescueAlerts(\n            continueRescue,"))
        #expect(code.contains(".hint(totalRemaining:"), "ヒントの 2 行目は他のゲームと同じ共通のバッジ")
        #expect(!code.contains("showRewardedAd("), "広告は RewardedRescue 経由だけで出す")
        #expect(!code.contains("withAnimation("), "アニメーションは gameAnimation 経由")
        #expect(!code.contains("UIImage("), "macOS でもビルドできるよう画像は ImageIO で読む")
        #expect(code.contains("level: size.analyticsLevel"), "盤の大きさを game_start の level に載せる")
        #expect(code.contains("gameDidStart(") && code.contains("gameDidRestart(")
                && code.contains("gameDidProgress(") && code.contains("gameDidFinish(") && code.contains("gameDidUseHint("))
    }

    @Test("遊び方の図は項目と同じ数で、図の問題は形が正しく解が 1 つ")
    func howToFigures() {
        #expect(CatPuzzleHowToFigures.items.count == HowToPlayGuide.catPuzzle.items.count)
        let sample = CatPuzzleHowToFigures.sample
        #expect(CatPuzzleLogic.isWellFormed(sample))
        #expect(CatPuzzleLogic.countSolutions(side: sample.side, rooms: sample.rooms, limit: 3) == 1)
        #expect(CatPuzzleLogic.isSolved(puzzle: sample, cats: sample.solutionCells))
    }

    @Test("猫の絵が 9 枚とも同梱されていて読める")
    func catImagesLoad() {
        for pose in CatPuzzleArt.Pose.allCases {
            #expect(CatPuzzleArt.cgImage(pose) != nil, "\(pose.rawValue) が読めない")
        }
        #expect(CatPuzzleArt.aspect(.sleep) > 1, "寝ている姿は横長")
    }

    @Test("家の部屋は 9 つあり、名前が重ならず、9×9 まで足りる")
    func houseRooms() {
        let rooms = CatPuzzleHouse.rooms
        #expect(rooms.count >= CatPuzzleSize.expert.side)
        #expect(Set(rooms.map(\.name)).count == rooms.count)
        #expect(CatPuzzleHouse.room(0).name == "居間")
        #expect(CatPuzzleHouse.room(rooms.count).name == rooms[0].name, "表より大きい番号は折り返す")
    }

    @Test("中断データ: 印を 1 つでも付けた盤だけが「続き」")
    func resumableSnapshot() {
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService())
        let module = CatPuzzleModule()
        let model = CatPuzzleModel(services: services, seed: 4)
        #expect(!module.hasResumableSnapshot(in: store))
        #expect(!module.hasUntouchedSnapshot(in: store), "手つかずの盤はそもそも保存しない")
        // × を付けて外す（タップで付け外し）。
        let cell = model.puzzle.solutionCells[0]
        model.toggleCross(cell: cell)
        #expect(module.hasResumableSnapshot(in: store))
        model.toggleCross(cell: cell)
        #expect(!module.hasResumableSnapshot(in: store), "印を消したら続きではない")
    }

    @Test("記録の区分名は難易度で、英語では訳される")
    func recordVariantLabels() {
        #expect(RecordVariantLabels.label(recordKey: "catpuzzle#easy", language: .japanese) == "かんたん")
        #expect(RecordVariantLabels.label(recordKey: "catpuzzle#normal", language: .english) == "Normal")
        #expect(RecordVariantLabels.label(recordKey: "catpuzzle#hard", language: .english) == "Hard")
        #expect(RecordVariantLabels.label(recordKey: "catpuzzle#9x9", language: .english) == nil)
        for size in CatPuzzleSize.allCases {
            #expect(size.recordVariantLabel == size.label)
        }
    }
}

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("おじさんちのねこさがし: 英語の文言と読み上げ")
struct CatPuzzleLocalizationTests {
    @Test("題名・読み上げ・残りの表示に英語の訳がある")
    func englishTerms() {
        #expect(GameCatPuzzle.tr("おじさんちのねこさがし", language: .english) == "Ojisan's Hidden Cats")
        #expect(GameCatPuzzle.tr("残り %lld匹", 1, language: .english) == "1 cat left")
        #expect(GameCatPuzzle.tr("残り %lld匹", 4, language: .english) == "4 cats left")
        #expect(GameCatPuzzle.tr("%1$lld行%2$lld列", 2, 3, language: .english) == "Row 2, column 3")
        #expect(GameCatPuzzle.tr("居間", language: .english) == "Living Room")
        #expect(Core.tr("おじさんちのねこさがしの遊び方", language: .english) == "How to Play Ojisan's Hidden Cats")
    }

    @Test("読み上げは部屋の名前と印・矛盾・ヒントを言葉で区別する")
    func accessibilityLabels() {
        #expect(CatPuzzleAccessibility.cellLabel(row: 1, col: 2, roomName: "居間", mark: .cat, isConflict: true)
                == "2行3列、居間、猫、ちがう")
        #expect(CatPuzzleAccessibility.cellLabel(row: 0, col: 0, roomName: "台所", mark: .cross) == "1行1列、台所、×")
        #expect(CatPuzzleAccessibility.cellLabel(row: 3, col: 4, roomName: "寝室", mark: .cat, isHint: true)
                == "4行5列、寝室、猫、ヒントで置いた")
        let puzzle = CatPuzzle(side: 4, rooms: [0, 0, 1, 1, 0, 0, 1, 1, 2, 2, 3, 1, 2, 2, 3, 3], solution: [1, 3, 0, 2])
        let roomName: (Int) -> String = { ["居間", "押し入れ", "寝室", "書斎"][$0] }
        #expect(CatPuzzleAccessibility.message(for: CatPuzzleHint(reason: .onlyCell(group: .room(3), cell: 14), placed: 14),
                                               puzzle: puzzle, roomName: roomName)
                == "ヒント: 書斎で猫が入れるのはここだけ。猫はここ！")
        #expect(CatPuzzleAccessibility.message(for: CatPuzzleHint(reason: .confined(sources: [.room(3)], targets: [.column(3)]), crossed: [3]),
                                               puzzle: puzzle, roomName: roomName)
                == "ヒント: 書斎の猫は4列目にしかいないので、4列目のほかのマスに猫はいない")
        #expect(CatPuzzleAccessibility.message(for: CatPuzzleHint(reason: .wrongCat(cell: 10, violation: .adjacent), removed: [10]),
                                               puzzle: puzzle, roomName: roomName)
                == "ヒント: 猫どうしは隣り合わないので、書斎の猫を外すよ")
        #expect(CatPuzzleAccessibility.message(for: CatPuzzleViolations(cells: [0, 1], kinds: [.room, .adjacent]))
                == "同じ部屋に2匹・猫どうしが隣")
        #expect(CatPuzzleAccessibility.message(for: CatPuzzleViolations()) == nil)
    }
}
