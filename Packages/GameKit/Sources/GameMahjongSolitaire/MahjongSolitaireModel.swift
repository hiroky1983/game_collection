import Foundation
import Observation
import Core

public enum MahjongSolitairePhase: String, Codable, Sendable, Equatable {
    /// 取り進めている最中。
    case playing
    /// 全部取り切った。
    case won
}

/// 中断スナップショット。位置は不変なので絵柄の配列と経過時間だけで盤面を復元できる。
struct MahjongSolitaireSnapshot: Codable {
    let faces: [MahjongFace?]
    let elapsedSeconds: Int
    let shuffleCount: Int
    let hintCount: Int
}

@MainActor
@Observable
public final class MahjongSolitaireModel {
    /// 位置ごとの絵柄。取り除いた位置は nil。添字は `MahjongSolitaireRules.layout` と対応する。
    public private(set) var faces: [MahjongFace?]
    /// 位置ごとに「いま取れるか」。描画で 144 回引くので毎回計算せず変化時にまとめて更新する。
    public private(set) var isFreeByIndex: [Bool] = []
    public private(set) var phase: MahjongSolitairePhase = .playing
    /// 選択中の牌（1 枚目）。
    public private(set) var selectedIndex: Int?
    /// ヒントで光らせている 2 枚。
    public private(set) var hintPair: [Int] = []
    public private(set) var remainingCount: Int = 0
    /// いま取れる組の数。0 なら手詰まり。
    public private(set) var availablePairCount: Int = 0
    public private(set) var elapsedSeconds: Int = 0
    public private(set) var shuffleCount: Int = 0
    public private(set) var hintCount: Int = 0
    /// 生成直後（およびシャッフル直後）の盤面を取り切れる順序。
    /// **クリア可能な盤面しか配っていないことの根拠**であり、テストではこの順にタップして完走させる。
    /// プレイヤーが別の順で取り始めた時点で無効になる（ヒントはこの順序ではなく現在の盤面から探す）。
    public private(set) var solution: [[Int]] = []
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに1行出す。
    public private(set) var recordResult: RecordResult?

    private var timerTask: Task<Void, Never>?
    private let services: GameServices?
    private var seed: UInt64?
    private let gameID = "mahjong"

    /// 手詰まり（牌は残っているのに取れる組が無い）。
    public var isDeadlocked: Bool {
        phase == .playing && remainingCount > 0 && availablePairCount == 0
    }

    /// 残りの組数（表示用）。
    public var remainingPairCount: Int { remainingCount / 2 }

    /// - Parameters:
    ///   - seed: テスト用の固定種。nil ならシステムの乱数を使う。
    ///   - faces: テスト用に盤面を直接与える経路（本番では使わない）。
    public init(
        services: GameServices? = nil,
        seed: UInt64? = nil,
        faces: [MahjongFace?]? = nil
    ) {
        self.services = services
        self.seed = seed

        if let snapshot = services?.snapshots.load(MahjongSolitaireSnapshot.self, for: gameID),
           snapshot.faces.count == MahjongSolitaireRules.layout.count {
            self.faces = snapshot.faces
            self.elapsedSeconds = snapshot.elapsedSeconds
            self.shuffleCount = snapshot.shuffleCount
            self.hintCount = snapshot.hintCount
        } else if let faces, faces.count == MahjongSolitaireRules.layout.count {
            self.faces = faces
        } else {
            let dealt = MahjongSolitaireModel.makeBoard(seed: seed)
            self.faces = dealt.board.faces
            self.solution = dealt.board.solution
            self.seed = dealt.nextSeed   // 次の盤面が同じにならないよう種を進める
        }

        self.remainingCount = self.faces.reduce(into: 0) { $0 += ($1 == nil ? 0 : 1) }
        refreshDerivedState()
        if remainingCount == 0 { phase = .won }
    }

    // MARK: - 操作

    /// 牌をタップしたとき。取れない牌は拒否し、合う 2 枚が揃ったら取り除く。
    public func tap(_ index: Int) {
        guard phase == .playing, index >= 0, index < faces.count else { return }
        guard let face = faces[index] else { return }
        guard isFreeByIndex[index] else {
            services?.feedback.notify(.warning)   // 上に載っている・両隣が塞がっている牌は取れない
            return
        }
        hintPair = []

        if selectedIndex == index {
            selectedIndex = nil
            services?.feedback.impact(.rigid)
            return
        }
        guard let first = selectedIndex, let firstFace = faces[first], firstFace.matches(face) else {
            // 合わない牌をタップしたときは選び直しとして扱う（拒否にはしない）。
            selectedIndex = index
            services?.feedback.impact(.rigid)
            return
        }

        faces[first] = nil
        faces[index] = nil
        remainingCount -= 2
        selectedIndex = nil
        services?.feedback.impact(.medium)
        refreshDerivedState()

        if remainingCount == 0 {
            finish()
        } else {
            if isDeadlocked { services?.feedback.notify(.warning) }
            persist()
        }
    }

    /// 取れる組を 1 組だけ光らせる。
    public func showHint() {
        guard phase == .playing else { return }
        guard let pair = MahjongSolitaireRules.availablePairs(faces: faces).first else {
            services?.feedback.notify(.warning)
            return
        }
        hintPair = [pair.0, pair.1]
        hintCount += 1
        services?.feedback.impact(.light)
        persist()
    }

    /// 残っている牌を並べ替えて、そこから必ず取り切れる配置に作り直す。
    /// 位置の組み合わせ自体が取り切れない場合は false を返す（この場合は最初からやり直すしかない）。
    @discardableResult
    public func shuffleRemaining() -> Bool {
        guard phase == .playing, remainingCount > 0 else { return false }
        let rearranged = MahjongSolitaireModel.rearrange(faces: faces, seed: seed)
        seed = rearranged.nextSeed
        guard let board = rearranged.board else { return false }
        faces = board.faces
        solution = board.solution
        selectedIndex = nil
        hintPair = []
        shuffleCount += 1
        services?.feedback.impact(.medium)
        refreshDerivedState()
        persist()
        return true
    }

    /// 新しい盤面を配る（結果は記録しない）。
    public func newGame() {
        let dealt = MahjongSolitaireModel.makeBoard(seed: seed)
        seed = dealt.nextSeed
        faces = dealt.board.faces
        solution = dealt.board.solution
        remainingCount = faces.reduce(into: 0) { $0 += ($1 == nil ? 0 : 1) }
        phase = .playing
        selectedIndex = nil
        hintPair = []
        elapsedSeconds = 0
        shuffleCount = 0
        hintCount = 0
        recordResult = nil
        refreshDerivedState()
        // 画面は開いたままなので、ここで計時を入れ直す（View の `.task` は初回表示のときしか走らない）。
        timerTask?.cancel()
        timerTask = nil
        startTimer()
        services?.feedback.impact(.medium)
        services?.snapshots.clear(for: gameID)
    }

    /// 手詰まりで「最初から」を選んだとき。取り切れずに終わったので敗北として記録し、盤面を配り直す。
    public func giveUpAndRestart() {
        guard phase == .playing else { return }
        services?.feedback.notify(.error)
        // 手詰まりでの投了。タイムは勝ったときだけ記録されるので、ここでは通算回数だけが増える。
        services?.gameDidFinish(gameID: gameID, outcome: .loss, score: currentScore)
        newGame()
    }

    /// 計時が動いているか（テスト用）。
    public var isCounting: Bool { timerTask != nil }

    /// 今の対局の成績。クリアタイムは勝ったときだけ自己ベストに取り込まれる（`PlayRecord.applying`）。
    private var currentScore: GameScore {
        GameScore(metric: .shortestTime, seconds: elapsedSeconds)
    }

    /// 中断から復帰したときに計時を再開する（View の `.task` から呼ぶ）。
    public func resumeTimerIfNeeded() {
        guard phase == .playing, timerTask == nil else { return }
        startTimer()
    }

    public func clearSnapshot() { services?.snapshots.clear(for: gameID) }

    // MARK: - 内部

    /// 盤面を 1 つ配る。種を渡した場合は「次に使う種」も返し、同じ配りが続かないようにする。
    private static func makeBoard(seed: UInt64?) -> (board: MahjongSolitaireRules.Board, nextSeed: UInt64?) {
        guard let seed else {
            var system = SystemRandomNumberGenerator()
            return (MahjongSolitaireRules.generate(using: &system), nil)
        }
        var generator = MahjongSeededGenerator(seed: seed)
        let board = MahjongSolitaireRules.generate(using: &generator)
        return (board, generator.next())
    }

    private static func rearrange(
        faces: [MahjongFace?],
        seed: UInt64?
    ) -> (board: MahjongSolitaireRules.Board?, nextSeed: UInt64?) {
        guard let seed else {
            var system = SystemRandomNumberGenerator()
            return (MahjongSolitaireRules.rearrange(faces: faces, using: &system), nil)
        }
        var generator = MahjongSeededGenerator(seed: seed)
        let board = MahjongSolitaireRules.rearrange(faces: faces, using: &generator)
        return (board, generator.next())
    }

    private func finish() {
        phase = .won
        timerTask?.cancel()
        timerTask = nil
        selectedIndex = nil
        hintPair = []
        services?.feedback.notify(.success)
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: .win, score: currentScore)
        services?.snapshots.clear(for: gameID)
    }

    private func refreshDerivedState() {
        let remaining = MahjongSolitaireRules.remainingFlags(faces: faces)
        isFreeByIndex = (0..<faces.count).map { MahjongSolitaireRules.isFree($0, remaining: remaining) }
        availablePairCount = MahjongSolitaireRules.availablePairs(faces: faces).count
    }

    private func persist() {
        // 配ったばかりの盤面は保存しない（ハブに「続きから」が出続けるのを避ける）。
        guard phase == .playing, remainingCount < MahjongSolitaireRules.layout.count else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snapshot = MahjongSolitaireSnapshot(
            faces: faces,
            elapsedSeconds: elapsedSeconds,
            shuffleCount: shuffleCount,
            hintCount: hintCount
        )
        try? services?.snapshots.save(snapshot, for: gameID)
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                elapsedSeconds += 1
            }
        }
    }
}
