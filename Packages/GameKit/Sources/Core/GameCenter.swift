import Foundation

/// Game Center へ送るリーダーボードの 1 件（ID と値）。
public struct GameCenterScore: Equatable, Sendable {
    /// App Store Connect に登録するリーダーボード ID。
    public let leaderboardID: String
    /// 送る値。タイムは秒、スコア・チップはそのままの数値。
    public let value: Int

    public init(leaderboardID: String, value: Int) {
        self.leaderboardID = leaderboardID
        self.value = value
    }
}

/// Game Center へ送る実績の進捗 1 件。
public struct GameCenterAchievement: Equatable, Sendable {
    /// App Store Connect に登録する実績 ID。
    public let achievementID: String
    /// 達成率（0...100）。100 で解除。
    public let percentComplete: Double

    public init(achievementID: String, percentComplete: Double) {
        self.achievementID = achievementID
        self.percentComplete = percentComplete
    }
}

/// Game Center 送信の境界。**Apple の GameKit に依存しない**プロトコルで、実装は App 層が注入する
/// （`AnalyticsService` と同じ設計。`Packages` 配下に `import GameKit`(Apple) を持ち込まないため）。
///
/// - Important: 実装は**投げっぱなし**にすること（戻り値も throws も持たせない）。呼び出し元は
///   リザルト表示の同期パスであり、通信の完了を待つ余地がない。オフラインでも「待たされない」という
///   受け入れ条件（#289）は、この API 形状そのもので担保している。
public protocol GameCenterService {
    @MainActor func submit(_ score: GameCenterScore)

    /// - Parameter completion: 送信の成否を**後から**知らせる。呼び出し元はこれを待たない
    ///   （リザルトの同期パスは即座に戻る）。用途は 1 つだけで、失敗したときに
    ///   `GameCenterReporter` が送信済みの控えを巻き戻し、次の決着で同じ進捗を送り直せるように
    ///   することにある。控えを送信前に確定させると、オフラインで失敗した進捗が
    ///   「送信済み」として二度と送られなくなる（PR #297 の CodeRabbit 指摘）。
    @MainActor func report(
        _ achievements: [GameCenterAchievement],
        completion: @escaping @MainActor (Bool) -> Void
    )
}

/// 何もしない実装。テスト・プレビュー・撮影モード用。
public struct NoopGameCenterService: GameCenterService {
    public init() {}
    @MainActor public func submit(_ score: GameCenterScore) {}
    /// 「意図的に送らない」ので**成功扱い**にする（再送を溜め込まない）。
    @MainActor public func report(
        _ achievements: [GameCenterAchievement],
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        completion(true)
    }
}

/// 決着 1 回をどのリーダーボードへ送るかの対応表（#289 段階②）。
///
/// **どのゲームに何を出すかの選定理由**:
/// - 出すのは「同じ条件で誰でも挑める、客観的に比較できる記録」だけに絞る。盤面や配牌が毎回変わる
///   対 CPU 戦（将棋・五目並べ・オセロ・大富豪・四人打ち麻雀・神経衰弱）は勝敗しか残らず、
///   勝ち数を並べても「たくさん遊んだ人」の順になるだけなので**対象外**にした。
/// - 区分（難易度・盤サイズ）があるゲームは区分ごとに別のリーダーボードにする。初級のタイムと
///   上級のタイムを同じ表に混ぜると、初級を選んだ人が常に上位に来て意味を成さないため。
/// - マインスイーパーは**プリセット 3 種だけ**を対象にする。カスタム盤（任意の行列・地雷数）は
///   区分が無限に増え、App Store Connect に登録しきれないため送らない。
public enum GameCenterLeaderboard {
    // 高いほど良い（App Store Connect では「High to Low」で登録する）
    public static let game2048Score  = "asobiba.2048.score"
    public static let pokerChips     = "asobiba.poker.chips"
    public static let blackjackChips = "asobiba.blackjack.chips"

    // 短いほど良い（App Store Connect では「Low to High」・フォーマットは経過時間で登録する）
    public static let minesweeperBeginner     = "asobiba.minesweeper.time.beginner"
    public static let minesweeperIntermediate = "asobiba.minesweeper.time.intermediate"
    public static let minesweeperExpert       = "asobiba.minesweeper.time.expert"
    public static let sudokuEasy              = "asobiba.sudoku.time.easy"
    public static let sudokuNormal            = "asobiba.sudoku.time.normal"
    public static let sudokuHard              = "asobiba.sudoku.time.hard"
    public static let mahjongSolitaireTime    = "asobiba.mahjongsolitaire.time"
    /// ソリティア（クロンダイク・#397）。配札は検証済みの種から選ぶだけで難度の区分を持たないので表は 1 つ。
    public static let solitaireTime           = "asobiba.solitaire.time"

    /// 登録が必要なリーダーボード ID の全量（App Store Connect の設定漏れを検証するのに使う）。
    public static let allIDs = [
        game2048Score, pokerChips, blackjackChips,
        minesweeperBeginner, minesweeperIntermediate, minesweeperExpert,
        sudokuEasy, sudokuNormal, sudokuHard, mahjongSolitaireTime,
        solitaireTime,
    ]

    /// 決着 1 回を送るリーダーボードと値。対象外なら nil（＝何も送らない）。
    ///
    /// - Note: タイム系は**勝ち / クリアのときだけ**送る。負けた局の経過時間を最短タイムの表に
    ///   混ぜると、投了した瞬間が常に世界一になってしまう（`PlayRecord.applying` と同じ理由）。
    /// - Note: 2048 のコンティニュー（#71）は、直前に送ったスコアを取り消せない。ただし
    ///   Game Center は自己ベストだけを残すため、続きを遊んで最終的に伸びたスコアを送れば
    ///   上書きされる。取り消せないことによる不利益は無い。
    public static func score(gameID: String, outcome: GameOutcome, score: GameScore) -> GameCenterScore? {
        switch score.metric {
        case .points:
            guard let points = score.points, points >= 0 else { return nil }
            guard let id = pointsLeaderboardID(gameID: gameID) else { return nil }
            return GameCenterScore(leaderboardID: id, value: points)

        case .shortestTime:
            // 0 秒のクリアは送らない。全世界で共有する表に 0 秒が 1 つでも載ると誰にも抜けない
            // 不動の 1 位になり、その表が誰の役にも立たなくなる（自己ベスト #115 は自分にしか
            // 見えないので 0 秒を許しているが、順位表は同じ扱いにできない）。対象 3 ゲームは
            // どれも実機で 0 秒クリアが成立しないため、正当な記録を捨てることはない。
            guard outcome == .win, let seconds = score.seconds, seconds > 0 else { return nil }
            guard let id = timeLeaderboardID(gameID: gameID, variant: score.variant) else { return nil }
            return GameCenterScore(leaderboardID: id, value: seconds)

        case .fewestMoves, .winLoss:
            // 上の選定理由のとおり対象外。`fewestMoves` を使うゲームは現時点で存在しない。
            return nil
        }
    }

    private static func pointsLeaderboardID(gameID: String) -> String? {
        switch gameID {
        case "2048":      return game2048Score
        case "poker":     return pokerChips
        case "blackjack": return blackjackChips
        default:          return nil
        }
    }

    private static func timeLeaderboardID(gameID: String, variant: String?) -> String? {
        switch gameID {
        // 麻雀ソリティアの gameID は "mahjong"、四人打ち麻雀（#106）が "mahjong4"。
        // 後から増えた側に別名が付いているので取り違えないこと。
        case "mahjong":
            // 区分キーは `MahjongSolitaireLayout.id`（#239）。**標準の亀甲だけを順位表に載せる**。
            // かたちが違えば取り切るまでの難度も違い、同じ表に混ぜると誰と competing しているのか
            // 分からない数字になる。かたちごとの表を作るには App Store Connect への登録
            // （会長のコンソール操作）が要るため、必要になった時点で稟議して足す。
            // nil はレイアウト識別子を持たない v1.1.1 までの記録 = 亀甲。
            switch variant {
            case nil, "turtle": return mahjongSolitaireTime
            default:            return nil
            }
        case "minesweeper":
            // 区分キーは `MinesweeperModel` が盤の構成から作る "行x列-地雷数"。
            switch variant {
            // **`MinesweeperDifficulty` を変えたらここも直す**（#444）。Core は GameMinesweeper に
            // 依存できない（依存の向きが逆）ため文字列を写し取るしかなく、二重管理になる。
            // 食い違うと「中級・上級で何秒でクリアしても順位表に載らない」という静かな故障になるので、
            // `MinesweeperGameCenterVariantTests` が両者の一致を機械的に確かめている。
            case "9x9-10":   return minesweeperBeginner
            case "16x16-40": return minesweeperIntermediate
            case "20x20-82": return minesweeperExpert
            // カスタム盤に加えて**旧プリセット**（"12x12-25" / "15x15-40"・#444 以前）も対象外。
            // 旧中級は 12×12/25、新中級は 16×16/40 で盤の広さも密度も違うため、同じ表に混ぜると
            // 盤が小さいぶん有利な旧記録が上位を占める（冒頭の「初級と上級を混ぜない」と同じ理由）。
            // 旧プリセットは中断データを再開したときにだけ現れる過渡的なもので、新規対局からは
            // 二度と作られない。
            default:         return nil
            }
        case "solitaire":
            // 区分を持たないので、区分キーが付いていないときだけ送る。
            // **ジョーカー（中継札）を使ったクリアを除外する仕掛けは #406 の決裁後に足す**
            // （ジョーカーの入手経路そのものがまだ無く、この版では使用クリアが発生しない）。
            return variant == nil ? solitaireTime : nil
        case "sudoku":
            // 区分キーは `SudokuDifficulty` の rawValue。
            switch variant {
            case "easy":   return sudokuEasy
            case "normal": return sudokuNormal
            case "hard":   return sudokuHard
            default:       return nil
            }
        default:
            return nil
        }
    }
}

/// 実績の定義と進捗計算（#289 段階③）。
///
/// **「最小限」の解釈**: ゲーム 1 本ごとに実績を作ると 12 個になり、そのぶん App Store Connect への
/// 手作業の登録（名前・説明・ポイント・画像）が会長の作業として積み上がる。ここでは**ゲーム横断で
/// 意味を持つ 4 個**に絞り、いずれも既に `PlayLog` が持っている値だけから計算する（新しい保存項目を
/// 増やさない = 会長が渋る永続化を足さない）。ゲーム別の実績は必要になったらこの対応表に足すだけで
/// 増やせる形にしてある。
public enum GameCenterAchievements {
    /// 初めて勝った / クリアした。
    public static let firstWin = "asobiba.achievement.firstwin"
    /// 通算 10 勝。
    public static let wins10 = "asobiba.achievement.wins10"
    /// 通算 50 勝。
    public static let wins50 = "asobiba.achievement.wins50"
    /// 全ゲームを 1 回ずつ遊ぶ（進捗つき）。
    public static let playAll = "asobiba.achievement.playall"

    /// 登録が必要な実績 ID の全量。
    public static let allIDs = [firstWin, wins10, wins50, playAll]

    /// 現在の進捗から実績の達成率を組み立てる。**純粋関数**（保存も送信もしない）。
    ///
    /// - Parameters:
    ///   - totalWins: 通算の勝利・クリア回数（`PlayLog.totalWins`）。
    ///   - playedGameCount: 一度でも終局まで遊んだゲーム数（`PlayLog.playedGameIDs.count`）。
    ///   - registeredGameCount: ハブに登録済みのゲーム数。0 のときは `playAll` を出さない
    ///     （ゼロ除算を避ける。ゲーム 0 本は本番では起きないがテスト・プレビューでは起きうる）。
    /// - Returns: 達成率が 0 より大きいものだけ。まだ何も進んでいない実績は送らない。
    public static func progress(
        totalWins: Int,
        playedGameCount: Int,
        registeredGameCount: Int
    ) -> [GameCenterAchievement] {
        var result: [GameCenterAchievement] = []
        func add(_ id: String, _ value: Int, target: Int) {
            guard target > 0, value > 0 else { return }
            let percent = min(100, Double(value) / Double(target) * 100)
            result.append(GameCenterAchievement(achievementID: id, percentComplete: percent))
        }
        add(firstWin, totalWins, target: 1)
        add(wins10, totalWins, target: 10)
        add(wins50, totalWins, target: 50)
        add(playAll, playedGameCount, target: registeredGameCount)
        return result
    }
}

/// 決着のたびに Game Center へリーダーボードと実績を送る係（#289 段階②③）。
///
/// `GameAnalytics` と同じ形で、**送るかどうかの判断をここ 1 か所**に閉じ込める。各ゲームの Model は
/// 何も変更しない（決着は既に `GameServices.gameDidFinish` の 1 点に集まっているため）。
///
/// オフライン・未サインインでの振る舞い（#289 の最重要の非機能要件）:
/// - `isAvailable` が false（＝未サインイン）のときは `service` を**一度も呼ばない**。
/// - サインイン済みのままオフラインになった場合は `service` を呼ぶが、**待たされない**。
///   `GameCenterService` の契約が投げっぱなし（戻り値も throws も無い）なので、通信の可否に
///   かかわらずゲームの進行は 1 ミリ秒も止まらない。失敗した実績の進捗は控えを巻き戻して
///   次の決着で送り直す。
@MainActor
public final class GameCenterReporter {
    private let service: GameCenterService
    /// ハブに登録済みのゲーム ID。知らない ID の記録は送らない（`GameAnalytics` と同じ方針）。
    private let allowedGameIDs: Set<String>
    /// Game Center が使える状態か（本番は `GKLocalPlayer.local.isAuthenticated`）。
    private let isAvailable: @MainActor () -> Bool
    /// 送信済みの達成率。同じ値を送り返さないための控え。
    private var reportedPercent: [String: Double] = [:]

    public init(
        service: GameCenterService,
        allowedGameIDs: Set<String>,
        isAvailable: @escaping @MainActor () -> Bool = { true }
    ) {
        self.service = service
        self.allowedGameIDs = allowedGameIDs
        self.isAvailable = isAvailable
    }

    /// 決着したときに `GameServices.gameDidFinish` から呼ぶ唯一の入口。
    ///
    /// - Parameters:
    ///   - totalWins / playedGameCount: 実績の進捗の元（`PlayLog` の更新**後**の値を渡す）。
    public func gameDidFinish(
        gameID: String,
        outcome: GameOutcome,
        score: GameScore,
        totalWins: Int,
        playedGameCount: Int
    ) {
        guard allowedGameIDs.contains(gameID), isAvailable() else { return }

        if let entry = GameCenterLeaderboard.score(gameID: gameID, outcome: outcome, score: score) {
            service.submit(entry)
        }

        let updated = GameCenterAchievements.progress(
            totalWins: totalWins,
            playedGameCount: playedGameCount,
            registeredGameCount: allowedGameIDs.count
        ).filter { $0.percentComplete > (reportedPercent[$0.achievementID] ?? 0) }

        guard !updated.isEmpty else { return }

        // 控えは送信「前」に進めておく（同じ決着の中で二重に送らないため）。ただし送信が
        // 失敗したら巻き戻す。巻き戻さないと、オフラインで落ちた進捗が「送信済み」の扱いのまま
        // 二度と送られない（100% に達した実績をその後遊ばずに終えると永久に解除されない）。
        var previous: [String: Double] = [:]
        for achievement in updated {
            if let recorded = reportedPercent[achievement.achievementID] {
                previous[achievement.achievementID] = recorded
            }
            reportedPercent[achievement.achievementID] = achievement.percentComplete
        }

        service.report(updated) { [weak self] succeeded in
            guard let self, !succeeded else { return }
            for achievement in updated {
                // 失敗の通知が届くまでに**さらに進んだ**進捗を送っていたら、そちらを優先する
                // （古い値で上書きして送り直しを増やさない）。
                guard reportedPercent[achievement.achievementID] == achievement.percentComplete
                else { continue }
                if let recorded = previous[achievement.achievementID] {
                    reportedPercent[achievement.achievementID] = recorded
                } else {
                    reportedPercent.removeValue(forKey: achievement.achievementID)
                }
            }
        }
    }
}
