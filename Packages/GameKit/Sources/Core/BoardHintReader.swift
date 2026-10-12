import Foundation
import Observation

/// 答えを「合法か・勝てない盤か」で振り分けた結果。`BoardHintReader` が回数を消費するかの判断に使う。
public enum BoardHintVerdict: Sendable {
    /// 勝てない盤。知らせるだけで回数を減らさない。
    case hopeless
    /// 今の盤で指せる手。
    case legal
    /// 読んでから盤が変わって指せなくなった手。
    case illegal
}

/// ソリティア・スパイダー・フリーセルの「勝ち筋を読んで 1 手示す」流れ（#2125）。
///
/// 盤の版番号・読みの Task・読み中の旗・広告経路の順序（先に読む → 勝てない盤なら広告を出さない → 見終えたら消費）を持つ。
/// ゲームごとに違うもの（探索・合法判定・示す手の保持・続きの控え）は `Context` の closure で渡す。
@MainActor
@Observable
public final class BoardHintReader<Answer: Sendable> {

    /// ゲームが渡す、読みと適用の部品。呼ぶたびにモデルから組み直す（盤の最新を読むため）。
    public struct Context {
        public let services: GameServices?
        public let gameID: String
        /// いまヒントを押せるか。
        public let canUse: Bool
        /// 次の 1 回に広告が要るか。
        public let needsAd: Bool
        /// 遊んでいる最中か。
        public let isPlaying: Bool
        /// 前に示した筋の続きに着いていれば、解き直さずその答え。
        public let cachedAnswer: () -> Answer?
        /// 盤を控えて、**メインアクターの外で走らせる**探索を返す（`Task.isCancelled` で取り消しを見る）。
        public let makeSearch: () -> @Sendable () -> Answer?
        /// 読みを終えた直後（テスト用の合図）。
        public let searchDidFinish: () -> Void
        public let verdict: (Answer) -> BoardHintVerdict
        /// 手を示す（`hintMove` と続きの控えを持つ）。
        public let show: (Answer) -> Void
        public let persist: () -> Void
        public let consumeFree: () -> Bool
        public let consumeAd: () -> Bool

        public init(
            services: GameServices?, gameID: String, canUse: Bool, needsAd: Bool, isPlaying: Bool,
            cachedAnswer: @escaping () -> Answer?,
            makeSearch: @escaping () -> @Sendable () -> Answer?,
            searchDidFinish: @escaping () -> Void,
            verdict: @escaping (Answer) -> BoardHintVerdict,
            show: @escaping (Answer) -> Void,
            persist: @escaping () -> Void,
            consumeFree: @escaping () -> Bool,
            consumeAd: @escaping () -> Bool
        ) {
            self.services = services
            self.gameID = gameID
            self.canUse = canUse
            self.needsAd = needsAd
            self.isPlaying = isPlaying
            self.cachedAnswer = cachedAnswer
            self.makeSearch = makeSearch
            self.searchDidFinish = searchDidFinish
            self.verdict = verdict
            self.show = show
            self.persist = persist
            self.consumeFree = consumeFree
            self.consumeAd = consumeAd
        }
    }

    /// 読みの最中か。
    public private(set) var isThinking = false
    /// 勝てない盤と分かった知らせを出しているか。
    public var showsHopeless = false

    @ObservationIgnored private var boardVersion = 0
    @ObservationIgnored private var search: Task<Answer?, Never>?

    public init() {}

    /// 盤が変わった。走っている読みは古いので取り消す（示していた手の後始末はゲーム側）。
    public func boardDidChange() {
        boardVersion += 1
        search?.cancel()
        search = nil
        isThinking = false
    }

    /// 局を替えるときに知らせを下ろす。
    public func reset() { showsHopeless = false }

    /// 無料の 1 回。**求まらなかった・盤が変わった・勝てない盤では回数を減らさない**。
    public func requestFree(_ context: Context) async {
        guard context.canUse, !context.needsAd else { return }
        guard let answer = await read(context) else { return }
        _ = apply(answer, context: context, consume: context.consumeFree)
    }

    /// 無料枠を使い切った後、広告を見て 1 回ぶん追加する。
    ///
    /// **先に読む**: 勝てない盤では広告を流さない。読み終えてから広告を出し、見終えたところで回数を消費して印を出す。
    /// - Parameter readDidFinish: 読みを終え、広告を出す直前に呼ぶ（読みの間は計時を止めないため・#2125）。
    /// - Returns: `.granted` は「この要求を終えた」（勝てない盤と分かり広告を出さずに知らせた場合も含む）。
    ///   `.superseded` は広告を出す前に読みが捨てられたとき（盤が変わった・画面を離れた）。
    public func requestAd(_ context: Context, readDidFinish: () -> Void = {}) async -> RewardedModelOutcome {
        guard context.canUse, context.needsAd else { return .unavailable }
        // 広告のあいだに画面を離れたら、このモデルは捨てられている（#653）。
        let generationBeforeAd = context.services?.screenGeneration.current
        let version = boardVersion
        // 広告を見せる前に読みが捨てられた = 利用者はまだ広告を見ていない。「広告を見ているあいだに」とは出さない。
        guard let answer = await read(context),
              context.services?.screenGeneration.current == generationBeforeAd, version == boardVersion
        else { return .superseded }
        if context.verdict(answer) == .hopeless {
            showsHopeless = true
            return .granted
        }
        readDidFinish()
        guard await context.services?.showRewardedAd(gameID: context.gameID, purpose: .hint) ?? false else { return .notEarned }
        guard context.services?.screenGeneration.current == generationBeforeAd, version == boardVersion,
              apply(answer, context: context, consume: context.consumeAd) else { return .unavailable }
        return .granted
    }

    /// 今の盤で勝ち筋を探す。盤が動いた・離脱で取り消された・読み終える前に別の読みが入ったときは nil。
    private func read(_ context: Context) async -> Answer? {
        // 前に示した筋の続きに着いていれば、解き直さずその続きを示す（往復しない・待たせない）。
        if let next = context.cachedAnswer() { return next }
        let version = boardVersion
        let work = context.makeSearch()
        isThinking = true
        let task = Task.detached(priority: .userInitiated) { work() }
        search = task
        let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        context.searchDidFinish()
        // 盤が変わっていれば `boardDidChange` が旗の持ち主を替えている。下ろすのは同じ盤のままのときだけ。
        guard version == boardVersion else { return nil }
        isThinking = false
        search = nil
        guard !Task.isCancelled else { return nil }
        return result
    }

    /// 答えを盤に反映する。勝てない盤は知らせるだけで回数を減らさない。
    private func apply(_ answer: Answer, context: Context, consume: () -> Bool) -> Bool {
        guard context.isPlaying else { return false }
        switch context.verdict(answer) {
        case .hopeless:
            showsHopeless = true
            return false
        case .illegal:
            return false
        case .legal:
            guard consume() else { return false }
            context.show(answer)
            context.services?.gameDidUseHint(gameID: context.gameID)
            context.services?.feedback.impact(.light)
            context.persist()
            return true
        }
    }
}
