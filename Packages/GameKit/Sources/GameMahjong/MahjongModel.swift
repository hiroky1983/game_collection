import Foundation
import Observation
import Core
import MahjongTiles

// MARK: - 進行の段階

public enum MahjongPhase: String, Equatable, Sendable, Codable {
    /// 開始前（スタートシート表示中）。
    case idle
    /// 対局中。
    case playing
    /// 自分がロンできる牌が出て、宣言するか見逃すかを待っている。
    case ronOffer
    /// 自分が鳴ける牌が出て、鳴くかスルーするかを待っている。
    case callOffer
    /// 1 局の決着（和了 or 流局）を見せている。
    case handResult
    /// 東風戦そのものの終了（順位が出ている）。
    case gameResult
}

/// 1 局の決着の内訳。リザルト表示にそのまま使う。
public struct MahjongHandResult: Equatable, Sendable, Codable {
    public enum Kind: String, Equatable, Sendable, Codable {
        case tsumo, ron, exhaustiveDraw
    }
    public let kind: Kind
    /// 和了した人。流局なら nil。
    public let winner: Int?
    /// 放銃した人。ツモ・流局なら nil。
    public let loser: Int?
    /// 成立した役（表示用の名前と飜数）。
    public let yaku: [String]
    public let han: Int
    public let fu: Int
    /// 満貫以上の呼び名。
    public let limitName: String?
    /// 和了者が受け取った点（本場・供託を含む）。
    public let gainedPoints: Int
    /// 流局時に聴牌していた人。
    public let tenpaiPlayers: [Int]
    /// この局で各プレイヤーの点数がどれだけ動いたか（添字はプレイヤー番号、この局の直前からの差分）。
    /// 和了者はプラス、放銃・ツモ払い・流局のノーテン罰符はマイナス。会長指摘「誰が誰に振り込んだか
    /// わかるようにしてほしい」への対応で、リザルト画面の得点表に添える。
    public let pointChanges: [Int]
}

// MARK: - 永続化

struct MahjongSnapshot: Codable {
    let wall: [MahjongTile]
    let wallIndex: Int
    let deadWall: [MahjongTile]
    let hands: [MahjongHand]
    let drawnTile: MahjongTile?
    let discards: [[MahjongTile]]
    let riichi: [Bool]
    let riichiFuriten: [Bool]
    let scores: [Int]
    let dealer: Int
    let roundNumber: Int
    let honba: Int
    let riichiSticks: Int
    let currentPlayer: Int
    let turnCount: Int
    // 鳴き（#263）で足した項目。**古い中断データを読めなくしないため任意**にする
    // （必須にすると更新直後の 1 局が黙って消える）。
    let melds: [[MahjongCall]]?
    /// フリテンの判定に使う「これまでに捨てた牌の種類」。鳴かれて河から消えた牌も残す。
    let discardedKinds: [[Int]]?
    let revealedDoraCount: Int?
    let deadWallDraws: Int?
    /// トビ復活（#338）を使い切ったか。中断を挟んでも「1 半荘 1 回まで」を守るために持ち回る。
    /// 上と同じ理由で任意（古い中断データは「まだ使っていない」扱いになる）。
    let hasRevivedThisGame: Bool?
}

// MARK: - Model

/// 四人打ち麻雀・東風戦（CPU 3 人との対局）。プレイヤーは常に番号 0。
///
/// 決裁 A（#106・2026-08-24）の段階実装に、#263 で**鳴き（ポン・チー・カン）**を足した:
/// **東風戦 / 鳴きあり / 主要な一飜・二飜役 + 七対子 / 簡易点数計算**。半荘は次版以降。
///
/// 鳴きの範囲外としたもの（#263 の PR に明記）: 立直後のカン（暗槓を含む）・食い替えの禁止・
/// 四開槓・流し満貫。
///
/// ルール判定（シャンテン・和了・役・点数・CPU の打牌）はすべて純粋関数側
/// （`MahjongShanten` / `MahjongScoring` / `MahjongAI`）に寄せ、この型は**進行・永続化・演出**だけを持つ。
@MainActor
@Observable
public final class MahjongModel {
    /// 人間プレイヤーの番号。
    public static let humanIndex = 0
    /// 参加人数。
    public static let playerCount = 4
    /// 持ち点の初期値。
    public static let startingScore = 25_000
    /// 王牌（14 枚）。ここからは自摸らない。
    public static let deadWallCount = 14

    /// 門前の手牌。副露した面子は含まない（`melds` 側に入る）。
    public private(set) var hands: [MahjongHand] = Array(repeating: MahjongHand(), count: playerCount)
    /// 各家が晒している副露。
    public private(set) var melds: [[MahjongCall]] = Array(repeating: [], count: playerCount)
    /// いま自摸ってきた牌（手出しと区別して見せるため手牌とは別に持つ）。
    public private(set) var drawnTile: MahjongTile?
    public private(set) var discards: [[MahjongTile]] = Array(repeating: [], count: playerCount)
    public private(set) var riichi: [Bool] = Array(repeating: false, count: playerCount)
    public private(set) var scores: [Int] = Array(repeating: startingScore, count: playerCount)
    public private(set) var phase: MahjongPhase = .idle
    public private(set) var currentPlayer: Int = 0
    /// 親（0 = 自分）。
    public private(set) var dealer: Int = 0
    /// 東何局か（1〜4）。
    public private(set) var roundNumber: Int = 1
    public private(set) var honba: Int = 0
    /// 供託されている立直棒の本数。
    public private(set) var riichiSticks: Int = 0
    public private(set) var handResult: MahjongHandResult?
    /// 東風戦の最終順位（1 位から順のプレイヤー番号）。対局中は空。
    public private(set) var ranking: [Int] = []
    public private(set) var recordResult: RecordResult?
    /// 立直を宣言しようとしていて、切る牌の選択を待っている状態。
    public private(set) var isDeclaringRiichi = false
    /// ロンできる牌が出たときの提示内容（`phase == .ronOffer` のとき有効）。
    public private(set) var ronOffer: RonOffer?
    /// 鳴ける牌が出たときの提示内容（`phase == .callOffer` のとき有効）。
    public private(set) var callOffer: CallOffer?
    /// CPU 起動用の通し番号 × 手数。
    public private(set) var turnCount = 0
    public private(set) var gameSerial = 0
    /// トビで終わった対局を、リワード広告を見て続けられる状態か（#338）。
    /// 1 半荘 1 回までで、自分がトビたときにだけ立つ。
    public private(set) var canReviveAfterBust = false

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
    private struct PendingClaim {
        let player: Int
        let options: [MahjongCall]
    }

    private var wall: [MahjongTile] = []
    private var wallIndex = 0
    /// 王牌 14 枚。前から `[表ドラ, 裏ドラ] × 5` で、末尾 4 枚が嶺上牌。
    private var deadWall: [MahjongTile] = []
    /// 嶺上牌を何枚引いたか（= カンの回数）。引いたぶん自摸れる枚数が減る。
    private var deadWallDraws = 0
    /// めくれている表ドラ表示牌の数。カンのたびに 1 増える。
    private var revealedDoraCount = 1
    /// フリテンの判定に使う「これまでに捨てた牌の種類」。鳴かれて河から消えた牌もここには残る。
    private var discardedKinds: [Set<Int>] = Array(repeating: [], count: playerCount)
    /// いま処理中の打牌（鳴きの主張を順に聞いている間だけ有効）。
    private var pendingDiscard: (tile: MahjongTile, by: Int)?
    private var pendingClaims: [PendingClaim] = []
    /// 槍槓のロンを提示している間、保留している加槓。見逃されたら続きを実行する。
    private var pendingKan: (call: MahjongCall, player: Int)?
    /// いまのツモ牌が嶺上牌か（嶺上開花の判定に使う）。
    private var isRinshanDraw = false
    /// 立直後に自分の待ち牌が河に流れたときの永続フリテン。
    private var riichiFuriten: [Bool] = Array(repeating: false, count: playerCount)
    /// 見逃しによる同巡内フリテン（次の自摸で解ける）。
    private var temporaryFuriten: [Bool] = Array(repeating: false, count: playerCount)
    /// 立直の宣言巡（一発の判定に使う）。`nil` は未立直。
    private var riichiTurn: [Int?] = Array(repeating: nil, count: playerCount)
    /// アガリやめが成立し、この局で東風戦を終えるか。
    private var endsAfterThisHand = false
    /// この半荘でトビ復活（#338）を既に使ったか。1 半荘 1 回までの制限に使う。
    private var hasRevivedThisGame = false

    private let services: GameServices?
    private let gameID = "mahjong4"
    private let cpuDelay: Duration
    private var seed: UInt64?
    private let hints: FeedbackPreference
    private var isRunningCPUTurns = false
    /// デバッグ用: 自分の手番・鳴き判断・ロン判断も CPU と同じロジックで自動的に進める。
    /// `MahjongView` から起動引数（`-mahjongAutoPlay`）のときだけ有効化され、通常プレイでは
    /// 常に false。会長がシミュレータで毎回手動プレイして確認する手間を省くための機能。
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
            phase = .playing
        }
    }

    /// 自分の手番以降もすべて CPU 判断で自動的に進めるようにする。一度有効にしたら
    /// 対局が終わるまで無効化する手段は用意していない（デバッグ用途のみのため）。
    public func enableAutoPlay() {
        autoPlayEnabled = true
    }

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
    private var uraIndicators: [MahjongTile] {
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

    // MARK: - 対局の開始

    /// 東風戦を最初から始める。
    public func startGame() {
        scores = Array(repeating: Self.startingScore, count: Self.playerCount)
        dealer = 0
        roundNumber = 1
        honba = 0
        riichiSticks = 0
        ranking = []
        recordResult = nil
        endsAfterThisHand = false
        hasRevivedThisGame = false
        canReviveAfterBust = false
        gameSerial += 1
        startHand()
        services?.gameDidRestart(gameID: gameID)
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

    // MARK: - 自摸と打牌

    private func draw(for player: Int) {
        // カンのたびに山の末尾 1 枚が王牌へ回るので、自摸れる範囲も同じだけ短くなる。
        guard wallIndex < wall.count - deadWallDraws else {
            concludeExhaustiveDraw()
            return
        }
        temporaryFuriten[player] = false
        isRinshanDraw = false
        drawnTile = wall[wallIndex]
        wallIndex += 1
        currentPlayer = player
        turnCount += 1
    }

    /// カンの直後に嶺上牌を引く。王牌の末尾から順に使う。
    private func drawFromDeadWall(for player: Int) {
        guard deadWallDraws < 4, deadWall.count >= Self.deadWallCount else {
            concludeExhaustiveDraw()
            return
        }
        temporaryFuriten[player] = false
        drawnTile = deadWall[deadWall.count - 1 - deadWallDraws]
        deadWallDraws += 1
        isRinshanDraw = true
        currentPlayer = player
        turnCount += 1
    }

    /// カンで新しいドラをめくる（王牌は表裏 5 組ぶん用意してある）。
    private func revealKanDora() {
        revealedDoraCount = min(5, revealedDoraCount + 1)
    }

    /// 人間が牌を切る。`tile` は手牌かツモ牌のどちらでもよい。
    public func discard(_ tile: MahjongTile) {
        guard isPlayerTurn, discardableTiles.contains(tile) else {
            services?.feedback.notify(.warning)
            return
        }
        services?.feedback.impact(.light)
        if isDeclaringRiichi { commitRiichi(for: Self.humanIndex) }
        performDiscard(tile, by: Self.humanIndex)
    }

    /// 立直を宣言する。実際に成立するのは、続けて切る牌を選んだ時点。
    public func declareRiichi() {
        guard canDeclareRiichi else {
            services?.feedback.notify(.warning)
            return
        }
        isDeclaringRiichi = true
        services?.feedback.impact(.rigid)
    }

    /// 立直の宣言を取り消す。
    public func cancelRiichiDeclaration() {
        isDeclaringRiichi = false
    }

    /// ツモ和了を宣言する。
    public func declareTsumo() {
        guard canDeclareTsumo, let drawn = drawnTile else {
            services?.feedback.notify(.warning)
            return
        }
        concludeWin(
            winner: Self.humanIndex, loser: nil, winningTile: drawn,
            isTsumo: true, isRinshan: isRinshanDraw
        )
    }

    /// 提示されているロンを宣言する。
    public func declareRon() {
        guard phase == .ronOffer, let offer = ronOffer else { return }
        ronOffer = nil
        pendingKan = nil
        concludeWin(
            winner: Self.humanIndex, loser: offer.discarder, winningTile: offer.tile,
            isTsumo: false, isChankan: offer.isChankan
        )
    }

    /// 提示されているロンを見逃す。同巡内はロンできなくなり、立直中なら以後もロンできない。
    public func declineRon() {
        guard phase == .ronOffer, let offer = ronOffer else { return }
        ronOffer = nil
        temporaryFuriten[Self.humanIndex] = true
        if riichi[Self.humanIndex] { riichiFuriten[Self.humanIndex] = true }
        phase = .playing
        services?.feedback.impact(.light)
        // 槍槓を見逃した場合は、止めていた加槓をそのまま成立させて続ける。
        if let pending = pendingKan {
            completeSelfKan(pending.call, by: pending.player)
            return
        }
        // 打牌に対するロンを見逃したときは、続けて鳴きの主張を順に聞く
        // （ロンを見逃した牌をポンすること自体は妨げられない）。
        pendingDiscard = (offer.tile, offer.discarder)
        pendingClaims = claimOrder(for: offer.tile, discardedBy: offer.discarder)
        resolveNextClaim()
    }

    private func commitRiichi(for player: Int) {
        isDeclaringRiichi = false
        riichi[player] = true
        riichiTurn[player] = turnCount
        scores[player] -= 1000
        riichiSticks += 1
        services?.feedback.notify(.success)
    }

    /// 牌を河に置き、他家のロンと鳴きを確かめる。
    private func performDiscard(_ tile: MahjongTile, by player: Int) {
        if drawnTile == tile {
            drawnTile = nil
        } else {
            hands[player].remove(tile)
            if let drawn = drawnTile {
                hands[player].add(drawn)
                drawnTile = nil
            }
        }
        isRinshanDraw = false
        discards[player].append(tile)
        discardedKinds[player].insert(MahjongTileOrder.index(of: tile))

        // 立直者の待ちがこの牌なら、以後その人はロンできない（見逃しと同じ扱い）。
        for other in 0..<Self.playerCount where other != player && riichi[other] {
            let waits = MahjongShanten.waits(hands[other], meldCount: melds[other].count)
            if waits.contains(tile) && !canWin(other, tile: tile) {
                riichiFuriten[other] = true
            }
        }

        if let claimant = ronClaimant(for: tile, discardedBy: player) {
            if claimant == Self.humanIndex, !autoPlayEnabled {
                ronOffer = RonOffer(tile: tile, discarder: player)
                phase = .ronOffer
                services?.feedback.notify(.success)
                return
            }
            concludeWin(winner: claimant, loser: player, winningTile: tile, isTsumo: false)
            return
        }

        pendingDiscard = (tile, player)
        pendingClaims = claimOrder(for: tile, discardedBy: player)
        resolveNextClaim()
    }

    /// 打牌を鳴ける家を優先度順に並べる。
    ///
    /// ポン・カンは誰でも主張できるが**チーは下家だけ**で、ポン・カンのほうが優先される。
    /// 同じ優先度が重なることは無い（同じ牌を 2 人がポンできるのは牌が 4 枚しか無い以上
    /// ありえるが、その場合は放銃者に近い家が取る = 席順で先に来る）。
    private func claimOrder(for tile: MahjongTile, discardedBy discarder: Int) -> [PendingClaim] {
        var tripletClaims: [PendingClaim] = []
        var runClaims: [PendingClaim] = []
        for step in 1..<Self.playerCount {
            let player = (discarder + step) % Self.playerCount
            // 立直している人は手牌を変えられないので鳴けない。
            guard !riichi[player] else { continue }
            let options = MahjongCallFinder.claimOptions(
                hand: hands[player], tile: tile, from: discarder, allowsChi: step == 1
            )
            guard !options.isEmpty else { continue }
            let triplets = options.filter { $0.kind != .chi }
            let runs = options.filter { $0.kind == .chi }
            if !triplets.isEmpty {
                tripletClaims.append(PendingClaim(player: player, options: triplets))
            }
            if !runs.isEmpty {
                runClaims.append(PendingClaim(player: player, options: runs))
            }
        }
        return tripletClaims + runClaims
    }

    /// 優先度の高い家から順に「鳴くか」を聞く。誰も鳴かなければ手番を次へ送る。
    private func resolveNextClaim() {
        while !pendingClaims.isEmpty, let pending = pendingDiscard {
            let claim = pendingClaims.removeFirst()
            if claim.player == Self.humanIndex, !autoPlayEnabled {
                callOffer = CallOffer(
                    tile: pending.tile, discarder: pending.by, options: claim.options
                )
                phase = .callOffer
                services?.feedback.impact(.rigid)
                return
            }
            let chosen = MahjongAI.chooseCall(
                options: claim.options,
                hand: hands[claim.player],
                melds: melds[claim.player],
                seatWind: seatWind(claim.player),
                roundWind: 0
            )
            if let chosen {
                performCall(chosen, by: claim.player)
                return
            }
        }
        let discarder = pendingDiscard?.by ?? currentPlayer
        pendingDiscard = nil
        pendingClaims = []
        continueAfterDiscard(by: discarder)
    }

    /// ロンも鳴きも起きなかったときに手番を次へ送る。
    private func continueAfterDiscard(by player: Int) {
        persist()
        guard phase == .playing else { return }
        draw(for: (player + 1) % Self.playerCount)
        persist()
    }

    // MARK: - 鳴き

    /// 提示されている鳴きのうち 1 つを成立させる。
    public func acceptCall(_ call: MahjongCall) {
        guard phase == .callOffer, let offer = callOffer, offer.options.contains(call) else {
            services?.feedback.notify(.warning)
            return
        }
        performCall(call, by: Self.humanIndex)
    }

    /// 提示されている鳴きを見送る。下家のチーなど、優先度の低い主張があればそちらへ回る。
    public func declineCall() {
        guard phase == .callOffer else { return }
        callOffer = nil
        phase = .playing
        services?.feedback.impact(.light)
        resolveNextClaim()
    }

    /// 鳴きを成立させ、手番をその人へ移す。
    private func performCall(_ call: MahjongCall, by player: Int) {
        guard let pending = pendingDiscard else { return }
        pendingDiscard = nil
        pendingClaims = []
        callOffer = nil
        phase = .playing

        // 鳴かれた牌は河から取り上げる。フリテンの判定に使う `discardedKinds` には残す
        // （実際に捨てた事実は消えないため）。
        if !discards[pending.by].isEmpty { discards[pending.by].removeLast() }
        for tile in call.tilesFromHand { hands[player].remove(tile) }
        melds[player].append(call)

        cancelIppatsu()
        currentPlayer = player
        drawnTile = nil
        isRinshanDraw = false
        turnCount += 1
        services?.feedback.impact(.medium)

        if call.kind == .openKan {
            revealKanDora()
            drawFromDeadWall(for: player)
        }
        persist()
    }

    /// 自分の手番でカン（暗槓・加槓）を宣言する。
    public func declareKan(_ call: MahjongCall) {
        guard availableSelfKans.contains(call) else {
            services?.feedback.notify(.warning)
            return
        }
        performSelfKan(call, by: Self.humanIndex)
    }

    private func performSelfKan(_ call: MahjongCall, by player: Int) {
        // 加槓は槍槓（他家が横取りするロン）の対象になる。暗槓は対象外。
        if call.kind == .addedKan, let claimant = ronClaimant(
            for: call.tile, discardedBy: player, isChankan: true
        ) {
            if claimant == Self.humanIndex, !autoPlayEnabled {
                pendingKan = (call, player)
                ronOffer = RonOffer(tile: call.tile, discarder: player, isChankan: true)
                phase = .ronOffer
                services?.feedback.notify(.success)
                return
            }
            concludeWin(
                winner: claimant, loser: player, winningTile: call.tile,
                isTsumo: false, isChankan: true
            )
            return
        }
        completeSelfKan(call, by: player)
    }

    private func completeSelfKan(_ call: MahjongCall, by player: Int) {
        pendingKan = nil
        // ツモ牌もいったん手牌に入れてから、槓に使う牌を抜く。
        if let drawn = drawnTile {
            hands[player].add(drawn)
            drawnTile = nil
        }
        for tile in call.tilesFromHand { hands[player].remove(tile) }
        if call.kind == .addedKan,
           let index = melds[player].firstIndex(where: { $0.kind == .pon && $0.tile == call.tile }) {
            melds[player][index] = call
        } else {
            melds[player].append(call)
        }
        cancelIppatsu()
        services?.feedback.impact(.medium)
        revealKanDora()
        drawFromDeadWall(for: player)
        persist()
    }

    /// 鳴きが入ると一発は消える。立直そのものは続く。
    private func cancelIppatsu() {
        riichiTurn = Array(repeating: nil, count: Self.playerCount)
    }

    // MARK: - 和了の判定

    /// この牌でロンできる人。放銃者の下家から順に見て最初の 1 人（頭跳ね）。
    private func ronClaimant(
        for tile: MahjongTile, discardedBy discarder: Int, isChankan: Bool = false
    ) -> Int? {
        for step in 1..<Self.playerCount {
            let player = (discarder + step) % Self.playerCount
            if canWin(player, tile: tile, isChankan: isChankan) { return player }
        }
        return nil
    }

    /// その牌でロンできるか（和了形 + 役 + フリテンでない）。
    private func canWin(_ player: Int, tile: MahjongTile, isChankan: Bool = false) -> Bool {
        guard !isFuriten(player) else { return false }
        return winScore(
            for: player, winningTile: tile, isTsumo: false, isChankan: isChankan
        ) != nil
    }

    /// フリテンか。自分が捨てた牌に待ち牌が 1 つでもあれば該当する。
    ///
    /// 判定には河ではなく `discardedKinds`（捨てた牌の種類の記録）を使う。鳴かれた牌は河から
    /// 消えるが、**捨てた事実は消えない**のでフリテンは続くため。
    func isFuriten(_ player: Int) -> Bool {
        if riichiFuriten[player] || temporaryFuriten[player] { return true }
        let waits = MahjongShanten.waits(hands[player], meldCount: melds[player].count)
        guard !waits.isEmpty else { return false }
        return waits.contains { discardedKinds[player].contains(MahjongTileOrder.index(of: $0)) }
    }

    /// 和了点。役が無ければ nil（= 和了できない）。
    private func winScore(
        for player: Int,
        winningTile: MahjongTile,
        isTsumo: Bool,
        isRinshan: Bool = false,
        isChankan: Bool = false
    ) -> MahjongScore? {
        let calls = melds[player]
        let hand = hands[player].adding(winningTile)
        guard hand.total == 14 - calls.count * 3 else { return nil }
        let context = MahjongWinContext(
            winningTile: winningTile,
            isTsumo: isTsumo,
            isRiichi: riichi[player],
            isIppatsu: isIppatsu(player),
            isLastTile: remainingTiles == 0,
            isRinshan: isRinshan,
            isChankan: isChankan,
            seatWind: seatWind(player),
            roundWind: 0,
            doraIndicators: doraIndicators,
            uraIndicators: uraIndicators
        )
        return MahjongScoring.score(hand: hand, calls: calls, context: context)
    }

    /// 一発か。立直の宣言から 1 巡以内の和了。
    ///
    /// `turnCount` は自摸のたびに 1 増える通し番号で、`declaredAt` は宣言者が立直を宣言した
    /// 手番の値。他家のロンは差が 1〜3、**宣言者自身の次の自摸によるツモは差がちょうど 4**
    /// （= 参加人数）になるため、境界は `< playerCount` ではなく `<= playerCount`。
    /// `<` にすると立直後の第一ツモだけ一発が付かない。
    private func isIppatsu(_ player: Int) -> Bool {
        guard riichi[player], let declaredAt = riichiTurn[player] else { return false }
        return turnCount - declaredAt <= Self.playerCount
    }

    // MARK: - 局の決着

    private func concludeWin(
        winner: Int,
        loser: Int?,
        winningTile: MahjongTile,
        isTsumo: Bool,
        isRinshan: Bool = false,
        isChankan: Bool = false
    ) {
        guard let score = winScore(
            for: winner, winningTile: winningTile, isTsumo: isTsumo,
            isRinshan: isRinshan, isChankan: isChankan
        ) else { return }
        pendingDiscard = nil
        pendingClaims = []
        pendingKan = nil
        callOffer = nil
        let scoresBefore = scores

        var gained = score.total
        // 本場は 1 本につき 300 点（ツモなら 100 点ずつ）。
        let honbaBonus = honba * 300
        if let loser {
            scores[loser] -= score.ronPayment + honbaBonus
        } else {
            for player in 0..<Self.playerCount where player != winner {
                let payment = player == dealer ? score.tsumoFromDealer : score.tsumoFromNonDealer
                scores[player] -= payment + honba * 100
            }
        }
        gained += honbaBonus
        // 供託の立直棒はすべて和了者のもの。
        gained += riichiSticks * 1000
        scores[winner] += gained
        riichiSticks = 0

        handResult = MahjongHandResult(
            kind: isTsumo ? .tsumo : .ron,
            winner: winner,
            loser: loser,
            yaku: score.yaku.map { "\($0.name) \($0.isYakuman ? "役満" : "\($0.han)飜")" },
            han: score.han,
            fu: score.fu,
            limitName: score.limitName,
            gainedPoints: gained,
            tenpaiPlayers: [],
            pointChanges: (0..<Self.playerCount).map { scores[$0] - scoresBefore[$0] }
        )
        // 和了牌を手牌に入れた状態で見せる（リザルトで役を確かめられるように）。
        hands[winner] = hands[winner].adding(winningTile)
        drawnTile = nil
        finishHand(dealerContinues: winner == dealer)
    }

    private func concludeExhaustiveDraw() {
        drawnTile = nil
        pendingDiscard = nil
        pendingClaims = []
        pendingKan = nil
        callOffer = nil
        let tenpai = (0..<Self.playerCount).filter {
            MahjongShanten.isTenpai(hands[$0], meldCount: melds[$0].count)
        }
        let scoresBefore = scores
        applyExhaustiveDrawPayments(tenpaiPlayers: tenpai)
        handResult = MahjongHandResult(
            kind: .exhaustiveDraw,
            winner: nil,
            loser: nil,
            yaku: [],
            han: 0,
            fu: 0,
            limitName: nil,
            gainedPoints: 0,
            tenpaiPlayers: tenpai,
            pointChanges: (0..<Self.playerCount).map { scores[$0] - scoresBefore[$0] }
        )
        finishHand(dealerContinues: tenpai.contains(dealer))
    }

    /// 荒牌平局の点棒授受。聴牌者で 3000 点を分け合う（全員聴牌・全員ノーテンなら動かない）。
    func applyExhaustiveDrawPayments(tenpaiPlayers: [Int]) {
        let tenpaiCount = tenpaiPlayers.count
        guard tenpaiCount > 0, tenpaiCount < Self.playerCount else { return }
        let notenCount = Self.playerCount - tenpaiCount
        let gain = 3000 / tenpaiCount
        let loss = 3000 / notenCount
        for player in 0..<Self.playerCount {
            scores[player] += tenpaiPlayers.contains(player) ? gain : -loss
        }
    }

    private func finishHand(dealerContinues: Bool) {
        phase = .handResult
        services?.snapshots.clear(for: gameID)
        // アガリやめ: 東 4 局で親が連荘する条件を満たしていても、その親がトップなら終局する。
        // これを入れないと、勝っている親が連荘し続けるかぎり東風戦が終わらない。
        let isFinalRound = roundNumber >= Self.playerCount
        if dealerContinues && isFinalRound && isTopPlayer(dealer) {
            endsAfterThisHand = true
        }
        if dealerContinues {
            honba += 1
        } else {
            honba = 0
            dealer = (dealer + 1) % Self.playerCount
            roundNumber += 1
        }
        switch handResult?.winner {
        case Self.humanIndex: services?.feedback.notify(.success)
        case .some:           services?.feedback.notify(.error)
        case nil:             services?.feedback.notify(.warning)
        }
    }

    /// 東風戦が終わったか。東 4 局を終えた（= 5 局目に入る）か、アガリやめか、誰かが飛んだとき。
    private func isGameOver() -> Bool {
        endsAfterThisHand || roundNumber > Self.playerCount || scores.contains { $0 < 0 }
    }

    /// その人が単独・同点を問わず最高点か。
    func isTopPlayer(_ player: Int) -> Bool {
        scores[player] == scores.max()
    }

    private func concludeGame() {
        // 同点は席順（親から近い順）で上位にする。
        ranking = (0..<Self.playerCount).sorted {
            (scores[$0], -seatWind($0)) > (scores[$1], -seatWind($1))
        }
        // 最後の局が流局で終わると供託（立直棒）が残る。誰にも渡さないと点棒が消えるので、
        // 一般的なルールどおりトップが回収する（回収してもトップは入れ替わらない）。
        // 最後の局が流局で終わると供託（立直棒）が残る。誰にも渡さないと点棒が消えるので、
        // 一般的なルールどおりトップが回収する（回収してもトップは入れ替わらない）。
        if riichiSticks > 0, let top = ranking.first {
            scores[top] += riichiSticks * 1000
            riichiSticks = 0
        }
        phase = .gameResult
        services?.snapshots.clear(for: gameID)
        switch reviewOutcome {
        case .win:  services?.feedback.notify(.success)
        case .loss: services?.feedback.notify(.error)
        case .draw: services?.feedback.notify(.warning)
        }
        recordResult = services?.gameDidFinish(
            gameID: gameID, outcome: reviewOutcome, score: GameScore(metric: .winLoss)
        )
        // 自分がトビて終わった対局は、リワード広告で 1 半荘 1 回だけ続けられる（#338）。
        // 決着の通知（`gameDidFinish`）はここまでで従来どおり済ませ、復活したときに
        // 記録側だけを巻き戻す（2048・マインスイーパーのコンティニューと同じ扱い。`reviveAfterAd`）。
        canReviveAfterBust = didBustOut && !hasRevivedThisGame
    }

    /// 自分がトビて最下位で終わった対局か。次の 3 つは false（そのまま終局にする）:
    /// - 東 4 局を終えた・アガリやめが同時に成立している → 復活しても続ける局が無い
    /// - CPU だけがトビた → 自分は生き残っているので続ける動機が無い
    ///   （ポーカー・ブラックジャックの「自分のチップが尽きたときだけ回復を出す」形に揃える）
    /// - 自分がマイナスでも最下位ではない（複数人が同時にトビた稀なケース）→ 記録の巻き戻しが
    ///   `PlayLog.cancelLoss`（= 負けの取り消し）しか無く、負け以外を取り消す手段が無いため対象外にする
    private var didBustOut: Bool {
        scores[Self.humanIndex] < 0
            && reviewOutcome == .loss
            && !endsAfterThisHand
            && roundNumber <= Self.playerCount
    }

    /// リワード広告を表示し、**視聴完了したときだけ**トビ終了から復活して対局を続ける（#338）。
    /// 視聴中断・ロード失敗時は何も変更せず false を返す（呼び出し側でユーザーに通知する）。
    /// services 未注入時（プレビュー・テスト）は広告機構自体が無いため従来どおり復活させる。
    ///
    /// 復活はマイナスの持ち点を初期値（25,000 点）へ戻すだけなので、点棒の合計は 100,000 点を
    /// 超える。救済措置なので合計の保存より「そのまま続けられること」を優先する。
    /// `concludeGame` でトップが回収した供託も戻さない（回収済みとして続ける）。
    @discardableResult
    public func reviveAfterAd() async -> Bool {
        guard canReviveAfterBust else { return false }
        guard await services?.ads.showRewardedAd() ?? true else { return false }
        hasRevivedThisGame = true
        canReviveAfterBust = false
        // 同じ半荘の続きなので、直前に記録した「負け」は無かったことにする（2048・マインスイーパーの
        // コンティニューと同じ扱い）。そのままだと 1 半荘が 2 回（トビの負け + 復活後の最終着順）
        // として数えられ、広告を見るほど通算成績が増える抜け道になる。
        services?.playLog?.cancelLoss(gameID: gameID)
        recordResult = nil
        for player in 0..<Self.playerCount where scores[player] < 0 {
            scores[player] = Self.startingScore
        }
        ranking = []
        // 局と親は決着時に次へ進んでいる（`finishHand`）ので、そのまま次の局を配る。
        startHand()
        // `game_end` はもう送信済みなので、続きは次の 1 プレイとして数える（#158。
        // こうしないと `game_start` 1 回に対して `game_end` が 2 回付き、対応が崩れる）。
        services?.gameDidRestart(gameID: gameID)
        // Game Center（#289）は送信済みのぶんを取り消さない。四人打ち麻雀はリーダーボードの
        // 対象外（勝敗しか残らない対 CPU 戦のため `GameCenterLeaderboard` に登録が無い）で、
        // 実績の進捗は勝利数と遊んだゲーム数から作られる。トビ = 負けなので勝利数は増えておらず、
        // 「麻雀を遊んだ」という事実も復活で変わらないため、巻き戻す対象がそもそも無い。
        return true
    }

    // MARK: - CPU

    /// 自動で進む手番が続く限り進める。自分が選ぶ番になるか、局が決着したら止まる。
    /// View から複数の契機で呼ばれても内部で 1 本に制限する。
    ///
    /// `autoPlayEnabled` のときは、局が終わって `.handResult` になっても止まらず、
    /// そのまま「次の局へ」を自動で押した扱いにして次の局のCPU手番も続けて進める
    /// （対局全体が終わる `.gameResult` まで無人で進む）。
    public func runCPUTurnsIfNeeded() async {
        // 多重起動防止。ただし「先行タスクがいたら即リターン」にすると、`.task(id:)` の
        // 差し替え時に「新タスクが先に走る → 先行タスクがまだフラグを持っていて即リターン →
        // 直後に先行タスクがキャンセルで抜ける」の順になったとき走者が誰もいなくなり、
        // `turnKey` はもう変わらないので再起動も掛からず手番が止まる（レース）。
        // 先行タスクの終了を待ってから引き継ぐ。待機中に自分がキャンセルされたら
        // （さらに次のタスクへ差し替えられたら）そちらに譲って抜ける。
        while isRunningCPUTurns {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        isRunningCPUTurns = true
        defer { isRunningCPUTurns = false }

        while true {
            while phase == .playing, isAutomaticTurn, awaitsDiscard(currentPlayer) {
                if cpuDelay > .zero {
                    try? await Task.sleep(for: cpuDelay)
                    // `try?` がキャンセルのエラーを握り潰すため、キャンセル後は
                    // `Task.sleep` が即座に返る。ここで抜けないと、`.task(id:)` に
                    // 差し替えられた古いタスクが `cpuDelay` を一切待たずに残りの手番を
                    // 走り抜けてしまう（CodeRabbit 指摘）。
                    guard !Task.isCancelled else { return }
                    guard phase == .playing, isAutomaticTurn, awaitsDiscard(currentPlayer) else { return }
                }
                advanceAutomaticTurn()
            }
            guard autoPlayEnabled, phase == .handResult else { return }
            if cpuDelay > .zero {
                try? await Task.sleep(for: cpuDelay)
                guard !Task.isCancelled else { return }
                guard autoPlayEnabled, phase == .handResult else { return }
            }
            advanceToNextHand()
        }
    }

    /// 人の選択を要さない手番か。CPU の手番と、**立直後でツモ和了もできない自分の手番**
    /// （宣言後は自摸切りしかできないので選ばせる意味が無い）。`autoPlayEnabled` のときは
    /// 自分の手番も含めすべて自動。
    private var isAutomaticTurn: Bool {
        if currentPlayer != Self.humanIndex { return true }
        if autoPlayEnabled { return true }
        return riichi[Self.humanIndex] && !canDeclareTsumo
    }

    private func advanceAutomaticTurn() {
        if currentPlayer == Self.humanIndex, !autoPlayEnabled {
            guard let drawn = drawnTile else { return }
            performDiscard(drawn, by: Self.humanIndex)   // 立直中の自摸切り
            return
        }
        performCPUTurn(currentPlayer)
    }

    private func performCPUTurn(_ player: Int) {
        let meldCount = melds[player].count
        if let drawn = drawnTile {
            // ツモ和了できるなら必ず和了する。
            if winScore(
                for: player, winningTile: drawn, isTsumo: true, isRinshan: isRinshanDraw
            ) != nil {
                concludeWin(
                    winner: player, loser: nil, winningTile: drawn,
                    isTsumo: true, isRinshan: isRinshanDraw
                )
                return
            }
            if riichi[player] {
                performDiscard(drawn, by: player)
                return
            }
            // 形が悪くならないカン（暗槓・加槓）はしてよい。
            if deadWallDraws < 4, remainingTiles > 0 {
                let options = MahjongCallFinder.selfKanOptions(
                    hand: hands[player], drawnTile: drawn, melds: melds[player]
                )
                if let kan = MahjongAI.chooseSelfKan(
                    options: options, hand: hands[player], drawnTile: drawn, melds: melds[player]
                ) {
                    performSelfKan(kan, by: player)
                    return
                }
            }
        }
        // 鳴いた直後はツモ牌が無く、手牌がそのまま 1 枚多い状態になっている。
        var full = hands[player]
        if let drawn = drawnTile { full.add(drawn) }
        let choice = MahjongAI.chooseDiscard(
            from: full, meldCount: meldCount, visible: visibleCounts(for: player)
        )
        // 立直の条件（門前・聴牌・点棒・残り牌）が揃っていれば宣言してから切る。
        if drawnTile != nil, melds[player].allSatisfy({ !$0.breaksConcealment }),
           MahjongAI.shouldDeclareRiichi(hand: full.removing(choice.tile)),
           scores[player] >= 1000, remainingTiles >= Self.playerCount {
            commitRiichi(for: player)
        }
        performDiscard(choice.tile, by: player)
    }

    /// その人から見えている牌の枚数（自分の手牌 + 全員の河と副露 + ドラ表示牌）。
    private func visibleCounts(for player: Int) -> [Int] {
        var counts = hands[player].counts
        if let drawn = drawnTile, player == currentPlayer {
            counts[MahjongTileOrder.index(of: drawn)] += 1
        }
        for pile in discards {
            for tile in pile { counts[MahjongTileOrder.index(of: tile)] += 1 }
        }
        for calls in melds {
            for tile in calls.flatMap(\.tiles) { counts[MahjongTileOrder.index(of: tile)] += 1 }
        }
        for indicator in doraIndicators { counts[MahjongTileOrder.index(of: indicator)] += 1 }
        return counts
    }

    // MARK: - 永続化

    private func persist() {
        guard phase == .playing || phase == .ronOffer else {
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
            hasRevivedThisGame: hasRevivedThisGame
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
        melds: [[MahjongCall]]? = nil
    ) {
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

    /// テスト専用: 自分の手番でのカン（暗槓・加槓）を経由させる。
    func declareKanForTesting(_ call: MahjongCall, by player: Int) {
        performSelfKan(call, by: player)
    }

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

// MARK: - Seeded RNG

/// テスト用の決定的な乱数生成器（SplitMix64）。本番は `seed` を渡さないので system の乱数を使う。
struct MahjongSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
