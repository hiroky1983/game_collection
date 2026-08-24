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
}

// MARK: - Model

/// 四人打ち麻雀・東風戦（CPU 3 人との対局）。プレイヤーは常に番号 0。
///
/// 決裁 A（#106・2026-08-24）の段階実装:
/// **東風戦 / 鳴きなし（門前のみ）/ 主要な一飜・二飜役 + 七対子 / 簡易点数計算**。
/// 鳴き（ポン・チー・カン）と半荘は次版以降。
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

    public private(set) var hands: [MahjongHand] = Array(repeating: MahjongHand(), count: playerCount)
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
    /// CPU 起動用の通し番号 × 手数。
    public private(set) var turnCount = 0
    public private(set) var gameSerial = 0

    /// ロンの提示。
    public struct RonOffer: Equatable, Sendable {
        public let tile: MahjongTile
        public let discarder: Int
    }

    private var wall: [MahjongTile] = []
    private var wallIndex = 0
    private var deadWall: [MahjongTile] = []
    /// 立直後に自分の待ち牌が河に流れたときの永続フリテン。
    private var riichiFuriten: [Bool] = Array(repeating: false, count: playerCount)
    /// 見逃しによる同巡内フリテン（次の自摸で解ける）。
    private var temporaryFuriten: [Bool] = Array(repeating: false, count: playerCount)
    /// 立直の宣言巡（一発の判定に使う）。`nil` は未立直。
    private var riichiTurn: [Int?] = Array(repeating: nil, count: playerCount)
    /// アガリやめが成立し、この局で東風戦を終えるか。
    private var endsAfterThisHand = false

    private let services: GameServices?
    private let gameID = "mahjong4"
    private let cpuDelay: Duration
    private var seed: UInt64?
    private let hints: FeedbackPreference
    private var isRunningCPUTurns = false

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
            phase = .playing
        }
    }

    // MARK: - 公開状態

    public var playerHand: MahjongHand { hands[Self.humanIndex] }

    /// 自分の手番で、打牌を選べる状態か。
    public var isPlayerTurn: Bool {
        phase == .playing && currentPlayer == Self.humanIndex && drawnTile != nil
    }

    /// 山に残っている自摸れる枚数。
    public var remainingTiles: Int { max(0, wall.count - wallIndex) }

    /// ドラ表示牌（段階実装では 1 枚）。
    public var doraIndicators: [MahjongTile] {
        deadWall.isEmpty ? [] : [deadWall[0]]
    }

    /// 裏ドラ表示牌。和了の精算でだけ使い、対局中は見せない。
    private var uraIndicators: [MahjongTile] {
        deadWall.count > 1 ? [deadWall[1]] : []
    }

    /// 自分がツモ和了できるか。
    public var canDeclareTsumo: Bool {
        guard isPlayerTurn, let drawn = drawnTile else { return false }
        return winScore(for: Self.humanIndex, winningTile: drawn, isTsumo: true) != nil
    }

    /// 立直を宣言できるか。門前のみなので鳴きの判定は要らない。
    public var canDeclareRiichi: Bool {
        guard isPlayerTurn, !riichi[Self.humanIndex], !isDeclaringRiichi else { return false }
        guard scores[Self.humanIndex] >= 1000, remainingTiles >= Self.playerCount else { return false }
        return !riichiDiscardCandidates.isEmpty
    }

    /// 立直の宣言牌にできる牌（切ったあとも聴牌が保てる牌）。
    public var riichiDiscardCandidates: Set<MahjongTile> {
        guard let drawn = drawnTile else { return [] }
        let full = hands[Self.humanIndex].adding(drawn)
        var result: Set<MahjongTile> = []
        for index in 0..<MahjongTileOrder.kindCount where full.counts[index] > 0 {
            let tile = MahjongTileOrder.tile(at: index)
            if MahjongShanten.isTenpai(full.removing(tile)) { result.insert(tile) }
        }
        return result
    }

    /// いま切れる牌。立直中は自摸切りのみ、立直宣言中は聴牌を保てる牌のみ。
    public var discardableTiles: Set<MahjongTile> {
        guard isPlayerTurn, let drawn = drawnTile else { return [] }
        if isDeclaringRiichi { return riichiDiscardCandidates }
        if riichi[Self.humanIndex] { return [drawn] }
        var result = Set(hands[Self.humanIndex].tiles)
        result.insert(drawn)
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
        return MahjongShanten.waits(hand)
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
        riichi = Array(repeating: false, count: Self.playerCount)
        riichiFuriten = Array(repeating: false, count: Self.playerCount)
        temporaryFuriten = Array(repeating: false, count: Self.playerCount)
        riichiTurn = Array(repeating: nil, count: Self.playerCount)
        isDeclaringRiichi = false
        ronOffer = nil
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
        guard wallIndex < wall.count else {
            concludeExhaustiveDraw()
            return
        }
        temporaryFuriten[player] = false
        drawnTile = wall[wallIndex]
        wallIndex += 1
        currentPlayer = player
        turnCount += 1
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
        concludeWin(winner: Self.humanIndex, loser: nil, winningTile: drawn, isTsumo: true)
    }

    /// 提示されているロンを宣言する。
    public func declareRon() {
        guard phase == .ronOffer, let offer = ronOffer else { return }
        ronOffer = nil
        concludeWin(
            winner: Self.humanIndex, loser: offer.discarder, winningTile: offer.tile, isTsumo: false
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
        continueAfterDiscard(by: offer.discarder)
    }

    private func commitRiichi(for player: Int) {
        isDeclaringRiichi = false
        riichi[player] = true
        riichiTurn[player] = turnCount
        scores[player] -= 1000
        riichiSticks += 1
        services?.feedback.notify(.success)
    }

    /// 牌を河に置き、他家のロンを確かめる。
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
        discards[player].append(tile)

        // 立直者の待ちがこの牌なら、以後その人はロンできない（見逃しと同じ扱い）。
        for other in 0..<Self.playerCount where other != player && riichi[other] {
            if MahjongShanten.waits(hands[other]).contains(tile) && !canWin(other, tile: tile) {
                riichiFuriten[other] = true
            }
        }

        if let claimant = ronClaimant(for: tile, discardedBy: player) {
            if claimant == Self.humanIndex {
                ronOffer = RonOffer(tile: tile, discarder: player)
                phase = .ronOffer
                services?.feedback.notify(.success)
                return
            }
            concludeWin(winner: claimant, loser: player, winningTile: tile, isTsumo: false)
            return
        }
        continueAfterDiscard(by: player)
    }

    /// ロンが起きなかったときに手番を次へ送る。
    private func continueAfterDiscard(by player: Int) {
        persist()
        guard phase == .playing else { return }
        draw(for: (player + 1) % Self.playerCount)
        persist()
    }

    // MARK: - 和了の判定

    /// この牌でロンできる人。放銃者の下家から順に見て最初の 1 人（頭跳ね）。
    private func ronClaimant(for tile: MahjongTile, discardedBy discarder: Int) -> Int? {
        for step in 1..<Self.playerCount {
            let player = (discarder + step) % Self.playerCount
            if canWin(player, tile: tile) { return player }
        }
        return nil
    }

    /// その牌でロンできるか（和了形 + 役 + フリテンでない）。
    private func canWin(_ player: Int, tile: MahjongTile) -> Bool {
        guard !isFuriten(player) else { return false }
        return winScore(for: player, winningTile: tile, isTsumo: false) != nil
    }

    /// フリテンか。自分の河に待ち牌が 1 つでもあれば該当する。
    func isFuriten(_ player: Int) -> Bool {
        if riichiFuriten[player] || temporaryFuriten[player] { return true }
        let waits = Set(MahjongShanten.waits(hands[player]))
        guard !waits.isEmpty else { return false }
        return discards[player].contains { waits.contains($0) }
    }

    /// 和了点。役が無ければ nil（= 和了できない）。
    private func winScore(for player: Int, winningTile: MahjongTile, isTsumo: Bool) -> MahjongScore? {
        let hand = hands[player].adding(winningTile)
        guard hand.total == 14 else { return nil }
        let context = MahjongWinContext(
            winningTile: winningTile,
            isTsumo: isTsumo,
            isRiichi: riichi[player],
            isIppatsu: isIppatsu(player),
            isLastTile: remainingTiles == 0,
            seatWind: seatWind(player),
            roundWind: 0,
            doraIndicators: doraIndicators,
            uraIndicators: uraIndicators
        )
        return MahjongScoring.score(hand: hand, context: context)
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

    private func concludeWin(winner: Int, loser: Int?, winningTile: MahjongTile, isTsumo: Bool) {
        guard let score = winScore(for: winner, winningTile: winningTile, isTsumo: isTsumo) else { return }

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
            tenpaiPlayers: []
        )
        // 和了牌を手牌に入れた状態で見せる（リザルトで役を確かめられるように）。
        hands[winner] = hands[winner].adding(winningTile)
        drawnTile = nil
        finishHand(dealerContinues: winner == dealer)
    }

    private func concludeExhaustiveDraw() {
        drawnTile = nil
        let tenpai = (0..<Self.playerCount).filter { MahjongShanten.isTenpai(hands[$0]) }
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
            tenpaiPlayers: tenpai
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
    }

    // MARK: - CPU

    /// 自動で進む手番が続く限り進める。自分が選ぶ番になるか、局が決着したら止まる。
    /// View から複数の契機で呼ばれても内部で 1 本に制限する。
    public func runCPUTurnsIfNeeded() async {
        guard !isRunningCPUTurns else { return }
        isRunningCPUTurns = true
        defer { isRunningCPUTurns = false }

        while phase == .playing, drawnTile != nil, isAutomaticTurn {
            if cpuDelay > .zero {
                try? await Task.sleep(for: cpuDelay)
                guard phase == .playing, drawnTile != nil, isAutomaticTurn else { return }
            }
            advanceAutomaticTurn()
        }
    }

    /// 人の選択を要さない手番か。CPU の手番と、**立直後でツモ和了もできない自分の手番**
    /// （宣言後は自摸切りしかできないので選ばせる意味が無い）。
    private var isAutomaticTurn: Bool {
        if currentPlayer != Self.humanIndex { return true }
        return riichi[Self.humanIndex] && !canDeclareTsumo
    }

    private func advanceAutomaticTurn() {
        guard let drawn = drawnTile else { return }
        if currentPlayer == Self.humanIndex {
            performDiscard(drawn, by: Self.humanIndex)   // 立直中の自摸切り
            return
        }
        performCPUTurn(currentPlayer)
    }

    private func performCPUTurn(_ player: Int) {
        guard let drawn = drawnTile else { return }
        // ツモ和了できるなら必ず和了する。
        if winScore(for: player, winningTile: drawn, isTsumo: true) != nil {
            concludeWin(winner: player, loser: nil, winningTile: drawn, isTsumo: true)
            return
        }
        let full = hands[player].adding(drawn)
        if riichi[player] {
            performDiscard(drawn, by: player)
            return
        }
        let choice = MahjongAI.chooseDiscard(from: full, visible: visibleCounts(for: player))
        // 立直の条件（聴牌・点棒・残り牌）が揃っていれば宣言してから切る。
        if MahjongAI.shouldDeclareRiichi(hand: full.removing(choice.tile)),
           scores[player] >= 1000, remainingTiles >= Self.playerCount {
            commitRiichi(for: player)
        }
        performDiscard(choice.tile, by: player)
    }

    /// その人から見えている牌の枚数（自分の手牌 + 全員の河 + ドラ表示牌）。
    private func visibleCounts(for player: Int) -> [Int] {
        var counts = hands[player].counts
        if let drawn = drawnTile, player == currentPlayer {
            counts[MahjongTileOrder.index(of: drawn)] += 1
        }
        for pile in discards {
            for tile in pile { counts[MahjongTileOrder.index(of: tile)] += 1 }
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
            turnCount: turnCount
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
        honba: Int = 0
    ) {
        self.hands = hands
        self.wall = wall
        self.wallIndex = 0
        self.deadWall = deadWall
        self.discards = discards ?? Array(repeating: [], count: Self.playerCount)
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
        self.turnCount = 1
        self.phase = .playing
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
