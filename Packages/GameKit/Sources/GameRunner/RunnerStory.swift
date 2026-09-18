import Core
import CoreEngine
import Foundation

// MARK: - チャリンコおじさんのストーリー（#1092）

/// 話の 1 場面。始まり（1 回だけ）と、世界の締め（6 面ごと）。
///
/// 会長決裁 2026-09-17〜18: 商店街の福引きで当たった宝くじが風に飛ばされ、どこまでも追いかけていく。
/// 世界の締めでは毎回**あと一歩で掴みかけ、何かに邪魔されて次の世界へ飛んでいく**
/// （マリオの「姫は別の城にいます」の型）。**なぜママチャリで海を渡れるのかは説明しない**。
///
/// 純データなので、出す・出さないの判定も場面の中身も SwiftUI 抜きでテストできる。
public enum RunnerStoryScene: Equatable, Hashable, Sendable {
    /// 始まり。初めてチャリンコおじさんを開いたときに 1 回だけ。
    case intro
    /// その世界の最終面（6・12・18・24・30 面）を初めてクリアしたとき。
    case ending(RunnerWorld)

    /// 始まり + 5 つの締め。並びは話の順。
    public static let all: [RunnerStoryScene] = [.intro] + RunnerWorld.allCases.map { .ending($0) }

    /// `PlayLog` に残す「見た」印の鍵。
    ///
    /// 初回ガイド（`RunnerTutorial.seenKey`）と同じ枠（`PlayLog.markGuideShown(for:)`）に入れる。
    /// ゲーム ID とぶつからない `runner.story.…` を使うのは、あちらの `runner.tutorial` と同じ作法。
    public var seenKey: String {
        switch self {
        case .intro: return "runner.story.intro"
        case .ending(let world): return "runner.story.world\(world.number)"
        }
    }

    /// この場面を出すきっかけになる「クリアした面」。始まりはクリアで出ないので nil。
    public var triggerStage: Int? {
        switch self {
        case .intro: return nil
        case .ending(let world): return world.stageRange.upperBound
        }
    }

    /// ワールドマップの見返しボタン・読み上げに使う名前。
    public var title: String {
        switch self {
        case .intro: return "はじまり"
        case .ending(let world): return "\(world.displayName)のおわり"
        }
    }

    /// 場面のコマ。先頭から順に出す。
    public var panels: [RunnerStoryPanel] {
        switch self {
        case .intro:
            return [
                RunnerStoryPanel(art: .introDraw, line: "商店街の福引きで大当たりや！"),
                RunnerStoryPanel(art: .introJoy, line: "宝くじやがな。3億円かもしれん"),
                RunnerStoryPanel(art: .introBlownAway, line: "あー！ 飛んでってもうた！"),
                RunnerStoryPanel(art: .introChase, line: "待てー！ どこまでも追いかけたるわ"),
            ]
        case .ending(.morning):
            return [
                RunnerStoryPanel(art: .morningReach, line: "もうちょい……もうちょいや！"),
                RunnerStoryPanel(art: .morningCrow, line: "こら！ カラスに持ってかれたがな"),
            ]
        case .ending(.evening):
            return [
                RunnerStoryPanel(art: .eveningDrop, line: "お、落としよった。しめた！"),
                RunnerStoryPanel(art: .eveningRiver, line: "川やんけ……待てー！"),
            ]
        case .ending(.night):
            return [
                RunnerStoryPanel(art: .nightReach, line: "やっと拾えるわ"),
                RunnerStoryPanel(art: .nightTruck, line: "トラックに貼り付いた！ 田舎行きかいな"),
            ]
        case .ending(.satoyama):
            return [
                RunnerStoryPanel(art: .satoyamaReach, line: "今度こそ、今度こそや"),
                RunnerStoryPanel(art: .satoyamaDitch, line: "用水路……海まで流れてまうやん！"),
            ]
        case .ending(.harbor):
            return [
                RunnerStoryPanel(art: .harborReach, line: "もう逃がさへんで"),
                RunnerStoryPanel(art: .harborShip, line: "船に……乗りよった"),
                RunnerStoryPanel(art: .harborWatch, line: "どこまで行く気や。ほな、追いかけよか"),
                RunnerStoryPanel(art: .harborToBeContinued, line: "つづく"),
            ]
        }
    }
}

/// 場面の 1 コマ。絵（`RunnerStoryArt.Panel`）と関西弁の短い台詞。
public struct RunnerStoryPanel: Equatable, Sendable {
    /// 絵。
    let art: RunnerStoryArt.Panel
    /// 台詞。1 コマ 1 行で、iPhone SE（第 3 世代）の幅でも 2 行に収まる長さにする
    /// （`RunnerStoryTests.linesAreShortEnough` が上限を固定）。
    public let line: String

    init(art: RunnerStoryArt.Panel, line: String) {
        self.art = art
        self.line = line
    }
}

// MARK: - 出す・出さないの判定

public enum RunnerStory {
    /// 1 コマの尺（秒）。`panels` の枚数を掛けたものが 1 場面の長さで、いちばん長い港町
    /// （4 コマ）でも 5 秒に収まる（会長決裁「1 場面は長くても 5 秒程度」）。
    public static let panelDuration: Double = 1.2

    /// 台詞の上限（文字）。iPhone SE（第 3 世代・幅 375pt）の吹き出しで 2 行に収まる長さ。
    public static let lineLimit = 24

    /// 始まりを出すか。**判定と同時に「見た」印を付ける**（`RunnerTutorial.shouldShow` と同じ作法）。
    ///
    /// v1.1.5 以前から遊んでいる人にも 1 回流れる——印は v1.1.6 で新設した鍵なので、
    /// 既に 18 面まで進んでいる人でも初めて開いた時点では未設定になる（話を知らないまま先へ進ませない）。
    /// 撮影・QA（`-screenshotMode` / `-simulateRunner`）では流さない（#1063 と同じ理由。
    /// ASO の絵に被せない）。
    @MainActor
    public static func shouldShowIntro(
        playLog: PlayLog?,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        guard !arguments.contains("-screenshotMode"), !arguments.contains("-simulateRunner") else { return false }
        return playLog?.markGuideShown(for: RunnerStoryScene.intro.seenKey) ?? false
    }

    /// `stage` 面をクリアしたときに流す締め。流すものが無ければ nil。
    ///
    /// **判定と同時に「見た」印を付ける**ので、2 回目以降のクリアでは nil になる
    /// （受け入れ条件「2 回目以降のクリアでは流さない」。そのときは毎面のゴール演出が流れる）。
    /// 撮影・QA では流さない。
    @MainActor
    public static func endingToPlay(
        clearedStage stage: Int,
        playLog: PlayLog?,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> RunnerStoryScene? {
        guard !arguments.contains("-screenshotMode"), !arguments.contains("-simulateRunner") else { return nil }
        guard let scene = ending(forClearedStage: stage) else { return nil }
        guard playLog?.markGuideShown(for: scene.seenKey) == true else { return nil }
        return scene
    }

    /// `stage` 面が世界の最終面なら、その世界の締め。そうでなければ nil（印は見ない純関数）。
    public static func ending(forClearedStage stage: Int) -> RunnerStoryScene? {
        guard RunnerWorld.contains(stage: stage) else { return nil }
        let world = RunnerWorld.world(forStage: stage)
        guard world.stageRange.upperBound == stage else { return nil }
        return .ending(world)
    }

    /// ワールドマップから見返せる場面（受け入れ条件「到達済みの世界の締めを見返せる」）。
    ///
    /// 始まりは常に見返せる（ここまで来た人は必ず見ている）。締めは**その世界を抜けた人だけ**
    /// ——最終面をクリアすると到達点が次の面へ進むので、`reachedStage` が世界の最終面を超えたかで見る。
    /// 30 面（最後の世界の最終面）をクリアしても到達点はそこで頭打ちになるので、
    /// **到達点が最終面に並んだ時点でも見返せる**ようにしてある（そうしないと最後の締めだけ
    /// 見返せない）。
    public static func replayableScenes(reachedStage: Int) -> [RunnerStoryScene] {
        [.intro] + RunnerWorld.allCases.compactMap { world in
            let last = world.stageRange.upperBound
            let cleared = reachedStage > last || (reachedStage == last && last == RunnerRules.stageCount)
            return cleared ? .ending(world) : nil
        }
    }

    #if DEBUG
    /// 撮影・QA 用の起動引数（`-simulateRunner story-intro` / `story-world1`〜`story-world5`）を場面に写す。
    ///
    /// **末尾に `:N` を付けると N コマ目で止まる**（`story-intro:3`）。走るゲームと同じ理屈で、
    /// コマ送りを流したまま撮ろうとするとシャッターを切る前に次のコマへ進んでしまう
    /// （#1063 と同じ「動くものは止めてから撮る」）。
    public static func debugScene(for value: String) -> RunnerStoryScene? {
        let name = value.split(separator: ":", maxSplits: 1).first.map(String.init) ?? value
        if name == "story-intro" { return .intro }
        guard name.hasPrefix("story-world"), let n = Int(name.dropFirst("story-world".count)) else { return nil }
        return RunnerWorld.allCases.first { $0.number == n }.map { .ending($0) }
    }

    /// 止めるコマの番号（0 始まり）。`:N` が無ければ nil（ふつうにコマ送りする）。
    /// 場面のコマ数を超える指定は最後のコマに丸める（撮り直しのたびに落ちないように）。
    public static func debugPanelIndex(for value: String) -> Int? {
        guard let scene = debugScene(for: value) else { return nil }
        let parts = value.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let n = Int(parts[1]), n >= 1 else { return nil }
        return min(n, scene.panels.count) - 1
    }
    #endif
}
