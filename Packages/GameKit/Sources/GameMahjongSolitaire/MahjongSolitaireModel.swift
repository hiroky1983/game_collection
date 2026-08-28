import Foundation
import Observation
import Core
import MahjongTiles

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
    /// アンドゥの利用回数（#198）。**任意項目**にしてあるのは、この項目を持たない
    /// 既存のスナップショットが復号に失敗して中断中の盤面を捨ててしまわないようにするため。
    let undoCount: Int?
    /// どのレイアウトの盤面か（#239）。`undoCount` と同じ理由で**任意項目**にしてあり、
    /// これを持たない古いスナップショットは亀甲として復元する（`MahjongSolitaireLayout.named`）。
    let layoutID: String?
}

/// 直前に取った 2 枚。位置は不変なので、添字と絵柄を戻せば盤面はそのまま復元できる。
/// 花牌・季節牌は「組では合うが絵柄は違う」ことがあるため、2 枚ぶんの絵柄を別々に持つ。
private struct MahjongSolitaireTake {
    let firstIndex: Int
    let firstFace: MahjongFace
    let secondIndex: Int
    let secondFace: MahjongFace
}

@MainActor
@Observable
public final class MahjongSolitaireModel {
    /// いま遊んでいる盤面のかたち（#239）。添字の意味がこれで決まるので、`faces` と必ず対で扱う。
    public private(set) var layout: MahjongSolitaireLayout
    /// 位置ごとの絵柄。取り除いた位置は nil。添字は `layout.positions` と対応する。
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
    /// アンドゥの利用回数（#198）。リザルトに出して記録の公平性を保つ。
    public private(set) var undoCount: Int = 0
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
    /// アンドゥで戻せる 1 手。**深さは常に 1 手ぶん**で、戻したら空になる（連続で巻き戻せない）。
    /// 並べ替え・新規ゲーム・クリアでは位置と絵柄の対応が変わる（または局が終わる）ので破棄する。
    /// 中断スナップショットには積まない = 再開直後は戻せない（オセロ・五目並べの「待った」と同じ扱い）。
    private var lastTake: MahjongSolitaireTake?

    /// 手詰まり（牌は残っているのに取れる組が無い）。
    public var isDeadlocked: Bool {
        phase == .playing && remainingCount > 0 && availablePairCount == 0
    }

    /// 1 手戻せるか。取った直後だけ true。
    public var canUndo: Bool { phase == .playing && lastTake != nil }

    /// 残りの組数（表示用）。
    public var remainingPairCount: Int { remainingCount / 2 }

    /// - Parameters:
    ///   - seed: テスト用の固定種。nil ならシステムの乱数を使う。
    ///   - faces: テスト用に盤面を直接与える経路（本番では使わない）。
    ///   - layout: 配る盤面のかたち。中断データがあればそちらのレイアウトが優先される。
    public init(
        services: GameServices? = nil,
        seed: UInt64? = nil,
        faces: [MahjongFace?]? = nil,
        layout: MahjongSolitaireLayout = .turtle
    ) {
        self.services = services
        self.seed = seed
        // 盤面を新しく用意したか（= 新しいプレイの開始か）。復元のときだけ false。
        var isFreshBoard = true

        let snapshot = services?.snapshots.load(MahjongSolitaireSnapshot.self, for: gameID)
        // レイアウト識別子を持たない古いスナップショットは亀甲として読む（`named` が nil を倒す）。
        let snapshotLayout = snapshot.map { MahjongSolitaireLayout.named($0.layoutID) }

        if let snapshot, let snapshotLayout, snapshot.faces.count == snapshotLayout.count {
            self.layout = snapshotLayout
            self.faces = snapshot.faces
            self.elapsedSeconds = snapshot.elapsedSeconds
            self.shuffleCount = snapshot.shuffleCount
            self.hintCount = snapshot.hintCount
            self.undoCount = snapshot.undoCount ?? 0
            isFreshBoard = false
        } else if let faces, faces.count == layout.count {
            self.layout = layout
            self.faces = faces
        } else {
            self.layout = layout
            let dealt = MahjongSolitaireModel.makeBoard(seed: seed, layout: layout)
            self.faces = dealt.board.faces
            self.solution = dealt.board.solution
            self.seed = dealt.nextSeed   // 次の盤面が同じにならないよう種を進める
        }

        self.remainingCount = self.faces.reduce(into: 0) { $0 += ($1 == nil ? 0 : 1) }
        refreshDerivedState()
        if remainingCount == 0 { phase = .won }
        // 中断からの復元は「新しいプレイ」ではないので数えない（#158）。
        // 再描画で init が何度走っても増えない（`gameDidStart` は冪等）。
        if isFreshBoard { services?.gameDidStart(gameID: gameID) }
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

        lastTake = MahjongSolitaireTake(
            firstIndex: first, firstFace: firstFace,
            secondIndex: index, secondFace: face
        )
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

    /// 直前に取った 2 枚を盤に戻す（#198）。誤タップと、取った結果の手詰まりの取り消し手段。
    ///
    /// 戻せるのは 1 手ぶんだけで、戻した時点で履歴は空になる。並べ替えや新規ゲームを挟むと戻せない。
    /// 利用回数は `undoCount` に積み、リザルトに出す（ヒント・並べ替えと同じ扱い。記録からは除外しない）。
    @discardableResult
    public func undoLastTake() -> Bool {
        guard phase == .playing, let take = lastTake else {
            services?.feedback.notify(.warning)
            return false
        }
        faces[take.firstIndex] = take.firstFace
        faces[take.secondIndex] = take.secondFace
        remainingCount += 2
        lastTake = nil
        selectedIndex = nil
        hintPair = []
        undoCount += 1
        services?.feedback.impact(.medium)
        refreshDerivedState()
        // 1 手目を戻して満杯に戻った場合、`persist()` は「配ったばかりの盤面」として保存を消す。
        // ハブに「続きから」を出さないための既存のガードで、意図どおり（利用回数はメモリ上に残るので
        // この局のリザルトには出る。中断を挟むと 0 に戻るが、盤面ごと配り直しになる状態のため矛盾しない）。
        persist()
        return true
    }

    /// 取れる組を 1 組だけ光らせる。
    public func showHint() {
        guard phase == .playing else { return }
        guard let pair = MahjongSolitaireRules.availablePairs(faces: faces, layout: layout).first else {
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
        let rearranged = MahjongSolitaireModel.rearrange(faces: faces, seed: seed, layout: layout)
        seed = rearranged.nextSeed
        guard let board = rearranged.board else { return false }
        faces = board.faces
        solution = board.solution
        selectedIndex = nil
        hintPair = []
        // 位置と絵柄の対応が総取り替えになるので、戻せる 1 手は無効になる。
        lastTake = nil
        shuffleCount += 1
        services?.feedback.impact(.medium)
        refreshDerivedState()
        persist()
        return true
    }

    /// 新しい盤面を配る（結果は記録しない）。
    ///
    /// - Parameter layout: 配る盤面のかたち。**nil なら今と同じかたちのまま配り直す**（#239）。
    public func newGame(layout newLayout: MahjongSolitaireLayout? = nil) {
        if let newLayout { layout = newLayout }
        let dealt = MahjongSolitaireModel.makeBoard(seed: seed, layout: layout)
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
        undoCount = 0
        lastTake = nil
        recordResult = nil
        refreshDerivedState()
        // 画面は開いたままなので、ここで計時を入れ直す（View の `.task` は初回表示のときしか走らない）。
        timerTask?.cancel()
        timerTask = nil
        startTimer()
        services?.feedback.impact(.medium)
        services?.snapshots.clear(for: gameID)
        services?.gameDidRestart(gameID: gameID)
    }

    /// 手詰まりで「最初から」を選んだとき。取り切れずに終わったので敗北として記録し、盤面を配り直す。
    public func giveUpAndRestart() {
        guard phase == .playing else { return }
        services?.feedback.notify(.error)
        // 手詰まりでの投了。タイムは勝ったときだけ記録されるので、ここでは通算回数だけが増える。
        // 直後の newGame() が盤面ごとリザルト表示を畳むため、戻り値（recordResult）は使わない。
        services?.gameDidFinish(gameID: gameID, outcome: .loss, score: currentScore)
        newGame()
    }

    /// 計時が動いているか（テスト用）。
    public var isCounting: Bool { timerTask != nil }

    /// 今の対局の成績。クリアタイムは勝ったときだけ自己ベストに取り込まれる（`PlayRecord.applying`）。
    ///
    /// **記録はレイアウトごとに分ける**（#239）。かたちが違えば取り切るまでの手数も難度も違うため、
    /// 同じ「最短タイム」に混ぜると自己ベストが比べものにならない。区分の仕組みは
    /// マインスイーパーの難易度と同じ `GameScore.variant` を使うので、保存の形式は増えない。
    private var currentScore: GameScore {
        GameScore(
            metric: .shortestTime,
            seconds: elapsedSeconds,
            variant: layout.id,
            variantLabel: layout.displayName
        )
    }

    /// 中断から復帰したときに計時を再開する（View の `.task` から呼ぶ）。
    public func resumeTimerIfNeeded() {
        guard phase == .playing, timerTask == nil else { return }
        startTimer()
    }

    public func clearSnapshot() { services?.snapshots.clear(for: gameID) }

    // MARK: - 内部

    /// 盤面を 1 つ配る。種を渡した場合は「次に使う種」も返し、同じ配りが続かないようにする。
    private static func makeBoard(
        seed: UInt64?,
        layout: MahjongSolitaireLayout
    ) -> (board: MahjongSolitaireRules.Board, nextSeed: UInt64?) {
        guard let seed else {
            var system = SystemRandomNumberGenerator()
            return (MahjongSolitaireRules.generate(using: &system, layout: layout), nil)
        }
        var generator = MahjongSeededGenerator(seed: seed)
        let board = MahjongSolitaireRules.generate(using: &generator, layout: layout)
        return (board, generator.next())
    }

    private static func rearrange(
        faces: [MahjongFace?],
        seed: UInt64?,
        layout: MahjongSolitaireLayout
    ) -> (board: MahjongSolitaireRules.Board?, nextSeed: UInt64?) {
        guard let seed else {
            var system = SystemRandomNumberGenerator()
            return (MahjongSolitaireRules.rearrange(faces: faces, using: &system, layout: layout), nil)
        }
        var generator = MahjongSeededGenerator(seed: seed)
        let board = MahjongSolitaireRules.rearrange(faces: faces, using: &generator, layout: layout)
        return (board, generator.next())
    }

    private func finish() {
        phase = .won
        timerTask?.cancel()
        timerTask = nil
        selectedIndex = nil
        hintPair = []
        // 取り切った局はもう戻せない（記録が確定した後に盤面を巻き戻せてしまわないように）。
        lastTake = nil
        services?.feedback.notify(.success)
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: .win, score: currentScore)
        services?.snapshots.clear(for: gameID)
    }

    private func refreshDerivedState() {
        let remaining = MahjongSolitaireRules.remainingFlags(faces: faces)
        isFreeByIndex = (0..<faces.count).map {
            MahjongSolitaireRules.isFree($0, remaining: remaining, layout: layout)
        }
        availablePairCount = MahjongSolitaireRules.availablePairs(faces: faces, layout: layout).count
    }

    private func persist() {
        // 配ったばかりの盤面は保存しない（ハブに「続きから」が出続けるのを避ける）。
        guard phase == .playing, remainingCount < layout.count else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snapshot = MahjongSolitaireSnapshot(
            faces: faces,
            elapsedSeconds: elapsedSeconds,
            shuffleCount: shuffleCount,
            hintCount: hintCount,
            undoCount: undoCount,
            layoutID: layout.id
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
