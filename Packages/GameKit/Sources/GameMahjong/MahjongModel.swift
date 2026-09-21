import Foundation
import Observation
import Core
import MahjongTiles

// MARK: - Model

/// 四人打ち麻雀（CPU 3 人との対局）。プレイヤーは常に番号 0。
///
/// 決裁 A（#106・2026-08-24）の段階実装に、#263 で**鳴き（ポン・チー・カン）**を足した:
/// **東風戦 / 鳴きあり / 主要な一飜・二飜役 + 七対子 / 簡易点数計算**。半荘は次版以降。
/// #639 で**一局戦**（東 1 局だけ）を対局の長さの分岐として足した（`MahjongGameLength`）。
///
/// 鳴きの範囲外としたもの（#263 の PR に明記）: 立直後のカン（暗槓を含む）・食い替えの禁止・
/// 四開槓・流し満貫。
///
/// ルール判定（シャンテン・和了・役・点数・CPU の打牌）はすべて純粋関数側
/// （`MahjongShanten` / `MahjongScoring` / `MahjongAI`）に寄せ、この型は**進行・永続化・演出**だけを持つ。
@MainActor
@Observable
public final class MahjongModel: AITurnGuarded {
    /// 人間プレイヤーの番号。
    public static let humanIndex = 0
    /// 参加人数。
    public static let playerCount = 4
    /// 持ち点の初期値。
    public static let startingScore = 25_000
    /// 王牌（14 枚）。ここからは自摸らない。
    public static let deadWallCount = 14

    /// 門前の手牌。副露した面子は含まない（`melds` 側に入る）。
    public internal(set) var hands: [MahjongHand] = Array(repeating: MahjongHand(), count: playerCount)
    /// 各家が晒している副露。
    public internal(set) var melds: [[MahjongCall]] = Array(repeating: [], count: playerCount)
    /// いま自摸ってきた牌（手出しと区別して見せるため手牌とは別に持つ）。
    public internal(set) var drawnTile: MahjongTile?
    public internal(set) var discards: [[MahjongTile]] = Array(repeating: [], count: playerCount)
    public internal(set) var riichi: [Bool] = Array(repeating: false, count: playerCount)
    public internal(set) var scores: [Int] = Array(repeating: startingScore, count: playerCount)
    public internal(set) var phase: MahjongPhase = .idle
    public internal(set) var currentPlayer: Int = 0
    /// 親（0 = 自分）。
    public internal(set) var dealer: Int = 0
    /// 東何局か（1〜`roundLimit`。通常は `gameLength.roundCount`）。
    public internal(set) var roundNumber: Int = 1
    public internal(set) var honba: Int = 0
    /// **その対局に焼き込まれた**長さ（#639）。`startGame(length:)` でだけ変わり、対局中は動かない。
    public private(set) var gameLength: MahjongGameLength = .tonpuu
    /// 供託されている立直棒の本数。
    public internal(set) var riichiSticks: Int = 0
    public internal(set) var handResult: MahjongHandResult?

    /// 卓中央に出す局数。**リザルト表示中は決着した局の値**を返す（#375）。
    ///
    /// `finishHand` は次局に備えて `roundNumber` / `honba` をリザルトに入るのと同時に
    /// 繰り上げるため、そのまま出すと「東1局が終わったのに東2局と書いてある」ずれになる。
    /// 決着内容（`handResult`）に控えた値を使うので、リザルト中断からの復元でもずれない。
    public var displayedRoundNumber: Int {
        phase == .handResult ? (handResult?.roundNumber ?? roundNumber) : roundNumber
    }

    /// 卓中央に出す本場。`displayedRoundNumber` と同じ理由でリザルト中は決着した局の値を返す。
    public var displayedHonba: Int {
        phase == .handResult ? (handResult?.honba ?? honba) : honba
    }

    /// 対局の最終順位（1 位から順のプレイヤー番号）。対局中は空。
    public internal(set) var ranking: [Int] = []
    public internal(set) var recordResult: RecordResult?
    /// 立直を宣言しようとしていて、切る牌の選択を待っている状態。
    public internal(set) var isDeclaringRiichi = false
    /// ロンできる牌が出たときの提示内容（`phase == .ronOffer` のとき有効）。
    public internal(set) var ronOffer: RonOffer?
    /// 鳴ける牌が出たときの提示内容（`phase == .callOffer` のとき有効）。
    public internal(set) var callOffer: CallOffer?
    /// CPU 起動用の通し番号 × 手数。
    public internal(set) var turnCount = 0
    public private(set) var gameSerial = 0
    /// トビで終わった対局を、リワード広告を見て続けられる状態か（#338）。
    /// 1 半荘 1 回までで、自分がトビたときにだけ立つ。
    public internal(set) var canReviveAfterBust = false

    /// 東 4 局を終えて自分が最下位のとき、リワード広告を見て東 5 局を 1 局だけ足せる状態か（#1201）。
    /// 東風戦だけ・1 半荘 1 回まで。東 4 局を打ち切った終局とアガリやめ（親が連荘できる最終局で
    /// トップの親が和了り続けて終わる）は対象で、トビ終了は対象外（持ち点がマイナスのまま続けると
    /// 次の局が成立しない。トビは復活の側）。決着の順位から導ける状態なので保存せず、
    /// リザルト（`.gameResult`）にいる間だけ真になる。
    public var canExtendAfterLastPlace: Bool {
        phase == .gameResult
            && gameLength == .tonpuu
            && !hasExtendedGame
            && (gameEndReason == .completedAllRounds || gameEndReason == .agariYame)
            && reviewOutcome == .loss
    }

    /// ロンの提示。
    public struct RonOffer: Equatable, Sendable {
        public let tile: MahjongTile
        public let discarder: Int
        /// 槍槓（他家の加槓を横取りするロン）か。
        public var isChankan = false
    }

    /// 鳴きの提示。
    public struct CallOffer: Equatable, Sendable {
        public let tile: MahjongTile
        public let discarder: Int
        /// 選べる鳴き（優先度の高い順）。
        public let options: [MahjongCall]
    }

    /// 打牌に対して鳴きを主張できる家。優先度の高い順に並べて 1 人ずつ聞く。
    struct PendingClaim {
        let player: Int
        let options: [MahjongCall]
    }

    var wall: [MahjongTile] = []
    var wallIndex = 0
    /// 王牌 14 枚。前から `[表ドラ, 裏ドラ] × 5` で、末尾 4 枚が嶺上牌。
    var deadWall: [MahjongTile] = []
    /// 嶺上牌を何枚引いたか（= カンの回数）。引いたぶん自摸れる枚数が減る。
    var deadWallDraws = 0
    /// めくれている表ドラ表示牌の数。カンのたびに 1 増える。
    var revealedDoraCount = 1
    /// フリテンの判定に使う「これまでに捨てた牌の種類」。鳴かれて河から消えた牌もここには残る。
    var discardedKinds: [Set<Int>] = Array(repeating: [], count: playerCount)
    /// いま処理中の打牌（鳴きの主張を順に聞いている間だけ有効）。
    var pendingDiscard: (tile: MahjongTile, by: Int)?
    var pendingClaims: [PendingClaim] = []
    /// 槍槓のロンを提示している間、保留している加槓。見逃されたら続きを実行する。
    var pendingKan: (call: MahjongCall, player: Int)?
    /// いまのツモ牌が嶺上牌か（嶺上開花の判定に使う）。
    var isRinshanDraw = false
    /// 立直後に自分の待ち牌が河に流れたときの永続フリテン。
    var riichiFuriten: [Bool] = Array(repeating: false, count: playerCount)
    /// 見逃しによる同巡内フリテン（次の自摸で解ける）。
    var temporaryFuriten: [Bool] = Array(repeating: false, count: playerCount)
    /// 立直の宣言巡（一発の判定に使う）。`nil` は未立直。
    var riichiTurn: [Int?] = Array(repeating: nil, count: playerCount)
    /// 宣言牌がまだ通っていない立直の宣言者（#375）。宣言牌をロンされた立直は**不成立**で
    /// 1000 点も出ないため、その支払いは宣言牌が通るまで保留する。
    ///
    /// これが立っているのは `performDiscard` の同期実行中と、人間へロンを提示している
    /// `.ronOffer` の待ち受け中だけで、**どちらも `persist()` を通らない**（`.ronOffer` は
    /// 復元時に `.playing` へ落ちて宣言前の状態から打ち直しになる）。そのため中断データに
    /// 持ち回す必要がない。
    var pendingRiichi: Int?
    /// アガリやめが成立し、この局で東風戦を終えるか。
    var endsAfterThisHand = false
    /// この半荘でトビ復活（#338）を既に使ったか。1 半荘 1 回までの制限に使う。
    var hasRevivedThisGame = false
    /// この半荘で最終局延長（#1201）を既に使ったか。1 半荘 1 回までの制限と、打ち切る局数
    /// （`roundLimit`）に使う。延長戦の最中・その後の中断でも持ち回す。
    var hasExtendedGame = false
    /// 打ち切る局数。延長（#1201）を使った半荘は東 1 局ぶん長い。
    var roundLimit: Int { gameLength.roundCount + (hasExtendedGame ? Self.extensionRounds : 0) }
    /// 最終局延長で足す局数。
    static let extensionRounds = 1
    /// 東風戦が終わった理由。`.gameResult` のときだけ入る（#352）。
    public internal(set) var gameEndReason: MahjongGameEndReason?

    let services: GameServices?
    let gameID = "mahjong4"
    let cpuDelay: Duration
    private var seed: UInt64?
    private let hints: FeedbackPreference
    var isRunningCPUTurns = false
    /// デバッグ用: 自分の手番・鳴き判断・ロン判断も CPU と同じロジックで自動的に進める。
    /// `MahjongView` から起動引数（`-mahjongAutoPlay`）のときだけ有効化され、通常プレイでは
    /// 常に false。会長がシミュレータで毎回手動プレイして確認する手間を省くための機能。
    /// **Release ビルドでは有効化する手段（`enableAutoPlay()`）ごと消えるので恒久的に false**（#514）。
    public private(set) var autoPlayEnabled = false

    public init(
        services: GameServices? = nil,
        cpuDelay: Duration = .milliseconds(520),
        seed: UInt64? = nil,
        hints: FeedbackPreference = .hints
    ) {
        self.services = services
        self.cpuDelay = cpuDelay
        self.seed = seed
        self.hints = hints
        if let snap = services?.snapshots.load(MahjongSnapshot.self, for: gameID) {
            wall = snap.wall
            wallIndex = snap.wallIndex
            deadWall = snap.deadWall
            hands = snap.hands
            drawnTile = snap.drawnTile
            discards = snap.discards
            riichi = snap.riichi
            riichiFuriten = snap.riichiFuriten
            scores = snap.scores
            dealer = snap.dealer
            roundNumber = snap.roundNumber
            honba = snap.honba
            riichiSticks = snap.riichiSticks
            currentPlayer = snap.currentPlayer
            turnCount = snap.turnCount
            melds = snap.melds ?? Array(repeating: [], count: Self.playerCount)
            discardedKinds = snap.discardedKinds.map { $0.map(Set.init) }
                ?? snap.discards.map { Set($0.map(MahjongTileOrder.index(of:))) }
            revealedDoraCount = snap.revealedDoraCount ?? 1
            deadWallDraws = snap.deadWallDraws ?? 0
            hasRevivedThisGame = snap.hasRevivedThisGame ?? false
            hasExtendedGame = snap.hasExtendedGame ?? false
            // 局のリザルト表示中に中断した場合はリザルトから再開する（#350）。以前は決着と同時に
            // 中断データを消していたため、「次の局へ」を押す前に終了すると東風戦の途中経過
            // （局数・持ち点・親・本場）がまるごと失われていた。旧形式（キー無し）は nil に
            // 落ちるので、従来どおり対局中（`.playing`）として復元される。
            handResult = snap.handResult
            endsAfterThisHand = snap.endsAfterThisHand ?? false
            gameLength = snap.gameLength ?? .tonpuu
            phase = snap.handResult != nil ? .handResult : .playing
            // 終局の手前のリザルトから再開した局も決着済み（#811。`finishHand` の末尾と同じ判定）。
            if concludesAfterCurrentResult { services?.gameDidRestoreFinished(gameID: gameID) }
        }
    }

    #if DEBUG
    /// 自分の手番以降もすべて CPU 判断で自動的に進めるようにする。一度有効にしたら
    /// 対局が終わるまで無効化する手段は用意していない（デバッグ用途のみのため）。
    ///
    /// Release ビルドには入れない（#514）。`autoPlayEnabled` を true にする手段はここだけなので、
    /// Release では下の分岐がすべて「自動プレイ無効」側に固定される。
    public func enableAutoPlay() {
        autoPlayEnabled = true
    }
    #endif

    // MARK: - 公開状態

    public var playerHand: MahjongHand { hands[Self.humanIndex] }

    /// 自分の副露。
    public var playerMelds: [MahjongCall] { melds[Self.humanIndex] }

    /// その人が打牌を待っている状態か。ツモ牌があるか、鳴いた直後で手牌が 1 枚多いとき。
    ///
    /// ポン・チーの直後は自摸らずにそのまま切るので `drawnTile` は nil。門前の枚数は
    /// 副露 1 つにつき 3 枚減るため、**3 で割った余りが 2** なら「1 枚多い = 切る番」と分かる。
    func awaitsDiscard(_ player: Int) -> Bool {
        (drawnTile != nil && currentPlayer == player) || hands[player].total % 3 == 2
    }

    /// 自分の手番で、打牌を選べる状態か。
    public var isPlayerTurn: Bool {
        phase == .playing && currentPlayer == Self.humanIndex && awaitsDiscard(Self.humanIndex)
    }

    /// 自分のツモ牌。`drawnTile` は「いま手番のプレイヤーが引いた牌」を表す**全員共有**の
    /// プロパティ（`draw(for:)` が誰の手番でも同じ1つの変数へ書く）なので、CPU の手番中は
    /// CPU が引いた牌が入っている。手牌表示（`MahjongView.handOnTable`）が `drawnTile` を
    /// そのまま「自分のツモ牌」として描いていたため、CPU3人が約0.5秒おきに打牌するたびに
    /// 手牌14枚目の絵柄がランダムな牌へ切り替わって見えていた（会長指摘「ルーレット現象」の正体）。
    public var playerDrawnTile: MahjongTile? {
        currentPlayer == Self.humanIndex ? drawnTile : nil
    }

    /// 山に残っている自摸れる枚数。カンで引いた嶺上牌のぶんだけ山の末尾が王牌へ回る。
    public var remainingTiles: Int { max(0, wall.count - wallIndex - deadWallDraws) }

    /// ドラ表示牌。カンのたびに 1 枚増える（王牌の偶数番目）。
    public var doraIndicators: [MahjongTile] {
        (0..<revealedDoraCount).compactMap { index in
            index * 2 < deadWall.count ? deadWall[index * 2] : nil
        }
    }

    /// 裏ドラ表示牌。和了の精算でだけ使い、対局中は見せない（王牌の奇数番目）。
    var uraIndicators: [MahjongTile] {
        (0..<revealedDoraCount).compactMap { index in
            index * 2 + 1 < deadWall.count ? deadWall[index * 2 + 1] : nil
        }
    }

    /// 自分がツモ和了できるか。
    public var canDeclareTsumo: Bool {
        guard isPlayerTurn, let drawn = drawnTile else { return false }
        return winScore(
            for: Self.humanIndex, winningTile: drawn, isTsumo: true, isRinshan: isRinshanDraw
        ) != nil
    }

    /// 自分がいまカンできる候補（暗槓・加槓）。
    ///
    /// **立直後はカンできない**ことにしている。立直後の暗槓は「待ちが変わらない」ことが条件で、
    /// 送り槓かどうかの判定を入れないと成立しない待ちの手が出来てしまうため（#263 でスコープ外と宣言）。
    public var availableSelfKans: [MahjongCall] {
        guard isPlayerTurn, !riichi[Self.humanIndex], !isDeclaringRiichi else { return [] }
        // **自摸ってきた手番でしかカンできない**。ポン・チーの直後は `isPlayerTurn` が true でも
        // ツモ牌が無い（そのまま 1 枚切る番）ので、ここで弾かないと「ポンしてさらに暗槓し、
        // 嶺上牌のツモと新ドラまで得る」という麻雀では起きない手が打ててしまう。
        guard drawnTile != nil else { return [] }
        guard remainingTiles > 0, deadWallDraws < 4 else { return [] }
        return MahjongCallFinder.selfKanOptions(
            hand: hands[Self.humanIndex], drawnTile: drawnTile, melds: melds[Self.humanIndex]
        )
    }

    public var canDeclareKan: Bool { !availableSelfKans.isEmpty }

    /// 立直を宣言できるか。鳴いていると宣言できない（**暗槓だけは門前のまま**）。
    public var canDeclareRiichi: Bool {
        guard isPlayerTurn, drawnTile != nil, !riichi[Self.humanIndex], !isDeclaringRiichi else {
            return false
        }
        guard melds[Self.humanIndex].allSatisfy({ !$0.breaksConcealment }) else { return false }
        guard scores[Self.humanIndex] >= 1000, remainingTiles >= Self.playerCount else { return false }
        return !riichiDiscardCandidates.isEmpty
    }

    /// 立直の宣言牌にできる牌（切ったあとも聴牌が保てる牌）。
    public var riichiDiscardCandidates: Set<MahjongTile> {
        guard let drawn = drawnTile else { return [] }
        let meldCount = melds[Self.humanIndex].count
        let full = hands[Self.humanIndex].adding(drawn)
        var result: Set<MahjongTile> = []
        for index in 0..<MahjongTileOrder.kindCount where full.counts[index] > 0 {
            let tile = MahjongTileOrder.tile(at: index)
            if MahjongShanten.isTenpai(full.removing(tile), meldCount: meldCount) {
                result.insert(tile)
            }
        }
        return result
    }

    /// いま切れる牌。立直中は自摸切りのみ、立直宣言中は聴牌を保てる牌のみ。
    /// 鳴いた直後はツモ牌が無いので、手牌からだけ選ぶ。
    public var discardableTiles: Set<MahjongTile> {
        guard isPlayerTurn else { return [] }
        if isDeclaringRiichi { return riichiDiscardCandidates }
        if riichi[Self.humanIndex], let drawn = drawnTile { return [drawn] }
        var result = Set(hands[Self.humanIndex].tiles)
        if let drawn = drawnTile { result.insert(drawn) }
        return result
    }

    /// 自分の待ち牌（ヒント表示用・#190 の設定に従う）。聴牌していなければ空。
    ///
    /// **ツモ牌を含めない 13 枚**に対する待ちなので、意味は「このままツモ切りしたときの待ち」。
    /// ツモ牌を足した 14 枚で数えると `total % 3 == 2` になって待ちが定義できず、
    /// 打牌を選んでいる最中（＝ヒントが一番要る場面）に何も出せなくなる。
    public var playerWaits: [MahjongTile] {
        guard hints.isEnabled else { return [] }
        let hand = hands[Self.humanIndex]
        guard hand.total % 3 == 1 else { return [] }
        return MahjongShanten.waits(hand, meldCount: melds[Self.humanIndex].count)
    }

    /// 自分がフリテンか（ヒント表示用）。
    public var isPlayerFuriten: Bool { isFuriten(Self.humanIndex) }

    /// 自分の順位（0 始まり）。決着していなければ nil。
    public var playerPlace: Int? { ranking.firstIndex(of: Self.humanIndex) }

    /// 評価リクエスト（#53）の判定。1 位なら勝ち、4 位なら負け、間は引き分け扱い。
    public var reviewOutcome: GameOutcome {
        guard let place = playerPlace else { return .draw }
        if place == 0 { return .win }
        if place == ranking.count - 1 { return .loss }
        return .draw
    }

    public func playerName(_ index: Int) -> String {
        index == Self.humanIndex ? "あなた" : "CPU\(index)"
    }

    /// 席風（0 = 東）。親から順に東南西北が割り当たる。
    public func seatWind(_ index: Int) -> Int {
        (index - dealer + Self.playerCount) % Self.playerCount
    }

    /// CPU 起動キー。
    public var turnKey: AITurnKey { AITurnKey(gameSerial: gameSerial, ply: turnCount) }

    /// 「新規対局」で失われるものがあるか（#638）。
    ///
    /// 対局が進行中なら、持ち点・局・河・供託はこの対局だけのもので、配り直すと戻せない。
    /// 開始前（`.idle`）と決着後（`.gameResult`）は捨てるものが無いので確認を挟まない
    /// （将棋 `moves.isEmpty` / ブロック崩し `hasProgressToLose` と同じ境目）。
    public var hasGameInProgress: Bool {
        switch phase {
        case .playing, .ronOffer, .callOffer, .handResult: return true
        case .idle, .gameResult: return false
        }
    }

    // MARK: - 対局の開始

    /// 対局を最初から始める。**進行中の対局はここで破棄される**（#638）。
    ///
    /// - Parameter length: この対局に**焼き込む**長さ（#639）。nil なら直前の対局と同じものを
    ///   使い続ける（リザルトの「もう一度」とツールバーの「新規対局」は選び直しを挟まないため）。
    ///   ここでしか対局の長さは変わらない。
    ///
    /// 破棄した対局の扱いは次のとおりで、未完了のまま戦績に載ることはない:
    /// - **記録（`PlayLog`）**: 勝敗を書くのは終局（`concludeGame` の `gameDidFinish`）だけなので、
    ///   打ち切った対局は通算成績にも Game Center の実績にも一切載らない。
    /// - **中断データ**: 直後の `startHand` → `persist` が新しい配牌で上書きするため、
    ///   捨てた対局の続きをあとから開ける経路は残らない。
    /// - **解析**: `gameDidRestart` が、1 枚でも切っていた対局に `game_end`（`quit`）を付けてから
    ///   次の `game_start` を送る（#500）。配っただけで切らずに捨てた対局は離脱に数えない。
    public func startGame(length: MahjongGameLength? = nil) {
        if let length { gameLength = length }
        scores = Array(repeating: Self.startingScore, count: Self.playerCount)
        dealer = 0
        roundNumber = 1
        honba = 0
        riichiSticks = 0
        ranking = []
        recordResult = nil
        endsAfterThisHand = false
        hasRevivedThisGame = false
        hasExtendedGame = false
        canReviveAfterBust = false
        gameEndReason = nil
        gameSerial += 1
        startHand()
        services?.gameDidRestart(gameID: gameID, mode: gameLength.analyticsMode)
    }

    /// 次の局へ進む（リザルトの「次の局へ」）。
    public func advanceToNextHand() {
        guard phase == .handResult else { return }
        if isGameOver() {
            concludeGame()
            return
        }
        startHand()
    }

    /// 1 局を配り直して始める。
    private func startHand() {
        var tiles = Self.makeWall()
        if var generator = makeGenerator() {
            tiles.shuffle(using: &generator)
            seed = generator.next()
        } else {
            tiles.shuffle()
        }
        deadWall = Array(tiles.suffix(Self.deadWallCount))
        wall = Array(tiles.dropLast(Self.deadWallCount))
        wallIndex = 0

        hands = (0..<Self.playerCount).map { player in
            let start = player * 13
            return MahjongHand(tiles: Array(wall[start..<(start + 13)]))
        }
        wallIndex = Self.playerCount * 13

        discards = Array(repeating: [], count: Self.playerCount)
        discardedKinds = Array(repeating: [], count: Self.playerCount)
        melds = Array(repeating: [], count: Self.playerCount)
        riichi = Array(repeating: false, count: Self.playerCount)
        riichiFuriten = Array(repeating: false, count: Self.playerCount)
        temporaryFuriten = Array(repeating: false, count: Self.playerCount)
        riichiTurn = Array(repeating: nil, count: Self.playerCount)
        pendingRiichi = nil
        isDeclaringRiichi = false
        ronOffer = nil
        callOffer = nil
        pendingDiscard = nil
        pendingClaims = []
        pendingKan = nil
        isRinshanDraw = false
        deadWallDraws = 0
        revealedDoraCount = 1
        handResult = nil
        turnCount = 0
        currentPlayer = dealer
        phase = .playing

        services?.feedback.impact(.medium)
        draw(for: dealer)
        persist()
    }

    /// 136 枚（34 種 × 4）の山。状態に触らない純粋な組み立てなので `nonisolated`。
    nonisolated static func makeWall() -> [MahjongTile] {
        MahjongTileOrder.all.flatMap { Array(repeating: $0, count: 4) }
    }

    private func makeGenerator() -> MahjongSeededGenerator? {
        seed.map { MahjongSeededGenerator(seed: $0) }
    }

    // MARK: - トビからの復活
    // 広告を呼ぶここは `AdsTests`（`RewardedRescueTests`）がこのファイル名で走査するので、別ファイルへ出さない。

    /// 自分がトビて最下位で終わった対局か。次の 3 つは false（そのまま終局にする）:
    /// - 最終局を終えた・アガリやめが同時に成立している → 復活しても続ける局が無い
    ///   （**一局戦（#639）はトビても必ずここに当たる**。最終局 = 東 1 局なので、復活して
    ///   続けられる局が構造的に存在しない。したがって一局戦では復活導線自体が出ない）
    /// - CPU だけがトビた → 自分は生き残っているので続ける動機が無い
    ///   （ポーカー・ブラックジャックの「自分のチップが尽きたときだけ回復を出す」形に揃える）
    /// - 自分がマイナスでも最下位ではない（複数人が同時にトビた稀なケース）→ 記録の巻き戻しが
    ///   `PlayLog.cancelLoss`（= 負けの取り消し）しか無く、負け以外を取り消す手段が無いため対象外にする
    var didBustOut: Bool {
        scores[Self.humanIndex] < 0
            && reviewOutcome == .loss
            && !endsAfterThisHand
            && roundNumber <= roundLimit
    }

    /// リワード広告を表示し、**視聴完了したときだけ**トビ終了から復活して対局を続ける（#338）。
    /// 視聴中断・ロード失敗時は何も変更せず `.notEarned` を返す（呼び出し側でユーザーに通知する）。
    /// 見終えたのに適用できなかったとき（救済できる状態でない・広告のあいだに対局が入れ替わった）は
    /// `.unavailable` を返し、視聴しなかったことと分ける（#814。ブラックジャック・ポーカーの #727 と同じ形）。
    /// services 未注入時（プレビュー・テスト）は広告機構自体が無いため従来どおり復活させる。
    ///
    /// 復活はマイナスの持ち点を初期値（25,000 点）へ戻すだけなので、点棒の合計は 100,000 点を
    /// 超える。救済措置なので合計の保存より「そのまま続けられること」を優先する。
    /// `concludeGame` でトップが回収した供託も戻さない（回収済みとして続ける）。
    public func reviveAfterAd() async -> RewardedModelOutcome {
        guard canReviveAfterBust else { return .unavailable }
        let serialBeforeAd = gameSerial
        // 画面の世代（#653）。`gameSerial` は**このモデルの中**の通し番号なので、ハブへ戻って
        // 開き直し、別の `MahjongModel` が動き出した場合には何も変わらない（下のガードを
        // 素通りする）。モデルより長生きする世代で突き合わせる。
        let generationBeforeAd = services?.screenGeneration.current
        guard await services?.showRewardedAd(gameID: gameID, purpose: .revival) ?? true else { return .notEarned }
        // ハブへ戻られていたら、この復活が乗るべき対局はもう画面に無い。適用すると、捨てられた
        // このモデルが `cancelLoss` で**いま遊んでいる対局の負け**を取り消し、`gameDidRestart` で
        // `game_start` / `game_end` の対応（#158）も崩す。
        guard services?.screenGeneration.current == generationBeforeAd else { return .unavailable }
        // 広告のロード〜視聴のあいだも画面は操作できる。そこで「新規対局」（#638）や
        // リザルトの「もう一度」を押されていたら、**入れ替わったあとの対局**に復活が乗る
        // （`RewardedRescue` が「#480 → #509 → #511 と 3 回続けて空いた穴」と呼んでいるもの）。
        // 乗ると、始めたばかりの対局の手牌が配り直され、正しく記録済みの前局の負けまで
        // `cancelLoss` で取り消される。通し番号で照合して、入れ替わっていたら適用しない
        // （`.unavailable` を返して、視聴しなかったときとは別のアラートを出させる。#814）。
        guard gameSerial == serialBeforeAd, canReviveAfterBust else { return .unavailable }
        hasRevivedThisGame = true
        canReviveAfterBust = false
        // 同じ半荘の続きなので、直前に記録した「負け」は無かったことにする（2048・マインスイーパーの
        // コンティニューと同じ扱い）。そのままだと 1 半荘が 2 回（トビの負け + 復活後の最終着順）
        // として数えられ、広告を見るほど通算成績が増える抜け道になる。
        // 取り消す先は決着を書いた記録と同じ区分でなければならない（#639）。一局戦では
        // 復活導線自体が出ない（`didBustOut`）ので現状ここは常に東風戦 = nil だが、
        // 書き込み先（`concludeGame`）と読み替え先が食い違う形を残さない。
        services?.playLog?.cancelLoss(gameID: gameID, variant: gameLength.recordVariant)
        recordResult = nil
        for player in 0..<Self.playerCount where scores[player] < 0 {
            scores[player] = Self.startingScore
        }
        ranking = []
        gameEndReason = nil
        // 局と親は決着時に次へ進んでいる（`finishHand`）ので、そのまま次の局を配る。
        startHand()
        // `game_end` はもう送信済みなので、続きは次の 1 プレイとして数える（#158。
        // こうしないと `game_start` 1 回に対して `game_end` が 2 回付き、対応が崩れる）。
        services?.gameDidRestart(gameID: gameID, mode: gameLength.analyticsMode)
        // Game Center（#289）は送信済みのぶんを取り消さない。四人打ち麻雀はリーダーボードの
        // 対象外（勝敗しか残らない対 CPU 戦のため `GameCenterLeaderboard` に登録が無い）で、
        // 実績の進捗は勝利数と遊んだゲーム数から作られる。トビ = 負けなので勝利数は増えておらず、
        // 「麻雀を遊んだ」という事実も復活で変わらないため、巻き戻す対象がそもそも無い。
        return .granted
    }

    // MARK: - 最終局の延長

    /// リワード広告を表示し、**視聴完了したときだけ**東 5 局を足して対局を続ける（#1201）。
    /// 返り値の意味と各ガードは `reviveAfterAd()` と同じ（視聴しなかったら `.notEarned`、見終えたのに
    /// 適用できなかったら `.unavailable`）。
    ///
    /// 決着で書いた「負け」は取り消す（同じ半荘の続きなので、広告を見るほど通算成績が増える抜け道に
    /// しない）。持ち点はそのまま次の局へ持ち越し、得点の操作はしない。決着で `concludeGame` が
    /// トップへ回収した供託は戻さない（回収済みとして続ける。`reviveAfterAd` と同じ）。
    public func extendAfterAd() async -> RewardedModelOutcome {
        guard canExtendAfterLastPlace else { return .unavailable }
        let serialBeforeAd = gameSerial
        let generationBeforeAd = services?.screenGeneration.current
        guard await services?.showRewardedAd(gameID: gameID, purpose: .continue) ?? true else { return .notEarned }
        guard services?.screenGeneration.current == generationBeforeAd else { return .unavailable }
        guard gameSerial == serialBeforeAd, canExtendAfterLastPlace else { return .unavailable }
        hasExtendedGame = true
        services?.playLog?.cancelLoss(gameID: gameID, variant: gameLength.recordVariant)
        recordResult = nil
        ranking = []
        gameEndReason = nil
        if endsAfterThisHand {
            // アガリやめは連荘の形（局・親が動いていない）で終わっている。延長は次の局へ進めて配る。
            endsAfterThisHand = false
            dealer = (dealer + 1) % Self.playerCount
            roundNumber += Self.extensionRounds
            honba = 0
        }
        // 局と親は最終局の決着時に次へ進んでいる（`finishHand`）ので、そのまま東 5 局を配る。
        startHand()
        // `game_end` は送信済みなので、続きは次の 1 プレイとして数える（復活と同じ・#158）。
        services?.gameDidRestart(gameID: gameID, mode: gameLength.analyticsMode)
        return .granted
    }

    // MARK: - 永続化

    func persist() {
        // `.handResult` も保存対象（#350）。東風戦の決着（`.gameResult`）だけは従来どおり消す
        // （終わった対局を「続きから」で開かない）。
        guard phase == .playing || phase == .ronOffer || phase == .handResult else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snap = MahjongSnapshot(
            wall: wall,
            wallIndex: wallIndex,
            deadWall: deadWall,
            hands: hands,
            drawnTile: drawnTile,
            discards: discards,
            riichi: riichi,
            riichiFuriten: riichiFuriten,
            scores: scores,
            dealer: dealer,
            roundNumber: roundNumber,
            honba: honba,
            riichiSticks: riichiSticks,
            currentPlayer: currentPlayer,
            turnCount: turnCount,
            melds: melds,
            discardedKinds: discardedKinds.map { Array($0).sorted() },
            revealedDoraCount: revealedDoraCount,
            deadWallDraws: deadWallDraws,
            hasRevivedThisGame: hasRevivedThisGame,
            hasExtendedGame: hasExtendedGame,
            handResult: phase == .handResult ? handResult : nil,
            endsAfterThisHand: endsAfterThisHand,
            gameLength: gameLength
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    // MARK: - テスト用

    /// テスト専用: 配りの乱数に依存せず任意の局面から検証するための組み立て口。
    func configureForTesting(
        hands: [MahjongHand],
        wall: [MahjongTile],
        deadWall: [MahjongTile] = Array(repeating: .characters(9), count: MahjongModel.deadWallCount),
        discards: [[MahjongTile]]? = nil,
        currentPlayer: Int = MahjongModel.humanIndex,
        dealer: Int = 0,
        drawnTile: MahjongTile? = nil,
        riichi: [Bool]? = nil,
        scores: [Int]? = nil,
        roundNumber: Int = 1,
        honba: Int = 0,
        melds: [[MahjongCall]]? = nil,
        length: MahjongGameLength? = nil
    ) {
        if let length { self.gameLength = length }
        self.hands = hands
        self.wall = wall
        self.wallIndex = 0
        self.deadWall = deadWall
        self.discards = discards ?? Array(repeating: [], count: Self.playerCount)
        self.discardedKinds = self.discards.map { Set($0.map(MahjongTileOrder.index(of:))) }
        self.melds = melds ?? Array(repeating: [], count: Self.playerCount)
        self.currentPlayer = currentPlayer
        self.dealer = dealer
        self.drawnTile = drawnTile
        self.riichi = riichi ?? Array(repeating: false, count: Self.playerCount)
        self.riichiFuriten = Array(repeating: false, count: Self.playerCount)
        self.temporaryFuriten = Array(repeating: false, count: Self.playerCount)
        self.riichiTurn = self.riichi.map { $0 ? 0 : nil }
        self.scores = scores ?? Array(repeating: Self.startingScore, count: Self.playerCount)
        self.roundNumber = roundNumber
        self.honba = honba
        self.ranking = []
        self.handResult = nil
        self.isDeclaringRiichi = false
        self.ronOffer = nil
        self.callOffer = nil
        self.pendingDiscard = nil
        self.pendingClaims = []
        self.pendingKan = nil
        self.isRinshanDraw = false
        self.deadWallDraws = 0
        self.revealedDoraCount = 1
        self.turnCount = 1
        self.phase = .playing
    }

    #if DEBUG
    /// 撮影・動作確認用（DEBUG 限定）: 和了のリザルト（手牌開示 #351・立直和了で裏ドラあり）を
    /// その場で作る。和了はシミュレータの自動タップでは再現できないため、非対話でこの画面を
    /// 確認する経路が要る（`simulateBustResultForTesting` と同じ理由）。
    func simulateWinResultForTesting() {
        let hand: [MahjongTile] = [
            .characters(2), .characters(3), .characters(4),
            .characters(5), .characters(6), .characters(7),
            .circles(2), .circles(2), .circles(3), .circles(4), .circles(5),
            .bamboos(6), .bamboos(7),
        ]
        handResult = MahjongHandResult(
            kind: .tsumo,
            winner: Self.humanIndex,
            loser: nil,
            yaku: ["立直 1飜", "門前清自摸和 1飜", "平和 1飜"],
            han: 3,
            fu: 20,
            limitName: nil,
            gainedPoints: 2700,
            tenpaiPlayers: [],
            pointChanges: [2700, -700, -700, -1300],
            winningHand: hand,
            winningMelds: [],
            winningTile: .bamboos(8),
            uraDoraIndicators: [.characters(9)]
        )
        phase = .handResult
    }

    /// 撮影・動作確認用（DEBUG 限定）: 打ち切りで終わったリザルト（見出し + 順位表）をその場で作る。
    /// 見出しは対局の長さで変わる（#639）が、実プレイで到達するには最後まで打つしかなく、
    /// シミュレータは自動タップができない（`simulateBustResultForTesting` と同じ理由）。
    func simulateFinalResultForTesting(length: MahjongGameLength) {
        gameLength = length
        scores = [32_000, 27_000, 23_000, 18_000]
        roundNumber = length.roundCount + 1
        handResult = nil
        concludeGame()
    }

    /// 撮影・動作確認用（DEBUG 限定）: トビ終了のリザルト（復活ボタンが出る状態）をその場で作る（#338）。
    /// トビは実プレイでは稀にしか起きず、シミュレータは自動タップができないため、非対話で
    /// この画面を確認する経路が要る（`-solitaireHintConfirm` と同じ理由・#336）。
    func simulateBustResultForTesting() {
        scores = [-1_000, 30_000, 35_000, 36_000]
        roundNumber = 2
        handResult = nil
        concludeGame()
    }
    #endif

    /// テスト専用: 人間以外の手番を 1 つだけ進める。
    func stepCPUForTesting() {
        guard phase == .playing, currentPlayer != Self.humanIndex else { return }
        performCPUTurn(currentPlayer)
    }

    /// テスト専用: 指定した人に指定した牌を切らせる（CPU の打牌選択を経由しない）。
    /// ロンの提示・フリテンの検証で「この牌がこの順で出る」ことを固定するために使う。
    func discardForTesting(_ tile: MahjongTile, by player: Int) {
        performDiscard(tile, by: player)
    }

    /// テスト専用: 人間の打牌を経由せずに局を流局させる。
    func exhaustWallForTesting() {
        wallIndex = wall.count
        concludeExhaustiveDraw()
    }
}
