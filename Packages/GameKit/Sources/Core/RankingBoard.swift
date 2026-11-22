import SwiftUI
import CoreEngine

// 定期リーダーボードの順位表と、記録を送った後に自分の行が上がる演出（#3327）。
// 柵越えおじさん（#1792・B 案「一気に飛び上がる」・会長決定 2026-10-09）の部品を、ねこさがしと共有するために上げたもの。
// スコアの単位（m・pt）は呼び出し側が `RankingBoardStyle.format` で決める。

/// 順位表の 1 行。
public struct RankingEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let score: Int
    /// Game Center の順位。アニメの間は並びの位置（index + 1）で描くので使わない。
    public let rank: Int
    public let isMe: Bool

    public init(_ row: GameCenterBoardRow) {
        id = row.id
        name = row.name.isEmpty ? tr("プレイヤー") : row.name
        score = row.score
        rank = row.rank
        isMe = row.isMe
    }

    public init(id: String, name: String, score: Int, rank: Int, isMe: Bool) {
        self.id = id
        self.name = name
        self.score = score
        self.rank = rank
        self.isMe = isMe
    }
}

/// 今回の記録で自分の行が上がるアニメの計画。
public struct RankingMotion: Equatable, Sendable {
    /// 上がる前の並び（自分は前回までの記録の位置）。
    public let entries: [RankingEntry]
    /// 今回の記録。
    public let newScore: Int
    /// 自分の行の、前の位置と後の位置（0 始まり）。
    public let from: Int
    public let to: Int

    /// 抜いた人の数。
    public var passedCount: Int { max(0, from - to) }

    /// アニメ全体の長さ（秒）。呼び出し側が「流し終わるまで次へ進まない」ために使う。
    public static let duration: Double = 3.4
}

public enum RankingPlan {
    /// 一覧に出す行。自分が上位の外なら、末尾に自分の行を足す（順位は Game Center のもの）。
    public static func entries(of board: GameCenterBoard) -> [RankingEntry] {
        var result = board.rows.map(RankingEntry.init)
        if !result.contains(where: \.isMe), let rank = board.myRank, let score = board.myScore {
            result.append(RankingEntry(id: "me", name: tr("あなた"), score: score, rank: rank, isMe: true))
        }
        return result
    }

    /// 送る前の自分の記録（`beforeScore`）と送った後の順位表から、アニメを作る（目的の位置は Game Center の順位そのもの。
    /// 同点の並びもそれに従う）。順位が変わらなくても記録が伸びたら数え上げだけ流す。アニメが無い（記録が伸びなかった・
    /// 送る前の記録が読めなかった（`beforeScore` が nil）・自分が上位の外）ときは nil で、静止の表を出す。
    public static func motion(beforeScore: Int?, after: GameCenterBoard) -> RankingMotion? {
        guard let oldScore = beforeScore, let newScore = after.myScore,
              let to = after.rows.firstIndex(where: \.isMe) else { return nil }
        let me = after.rows[to]
        guard newScore > oldScore else { return nil }
        let others = after.rows.filter { !$0.isMe }.map(RankingEntry.init)
        let from = others.filter { $0.score >= oldScore }.count
        var entries = others
        entries.insert(RankingEntry(id: me.id, name: me.name.isEmpty ? tr("プレイヤー") : me.name,
                                    score: oldScore, rank: from + 1, isMe: true), at: from)
        return RankingMotion(entries: entries, newScore: newScore, from: from, to: to)
    }
}

/// 順位表の見た目の差（単位の書式・行の高さ・行の補足）。
public struct RankingBoardStyle {
    public var rowHeight: CGFloat
    /// スコアの文字（「1,206 m」「12pt」）。
    public var format: (Int) -> String
    /// 名前の下の補足（柵越えおじさんの「月まで飛んだ」）。無ければ nil。
    public var note: (RankingEntry) -> String?
    /// スコアの文字の大きさ。
    public var scoreSize: (RankingEntry) -> CGFloat

    public init(rowHeight: CGFloat = 54, format: @escaping (Int) -> String,
                note: @escaping (RankingEntry) -> String? = { _ in nil },
                scoreSize: @escaping (RankingEntry) -> CGFloat = { _ in 18 }) {
        self.rowHeight = rowHeight
        self.format = format
        self.note = note
        self.scoreSize = scoreSize
    }
}

/// アニメの途中経過。見出しや自分のカードを呼び出し側が描くために渡す。
public struct RankingBoardState {
    /// 自分の今の順位（アニメの間は並びの位置）。表に自分がいなければ nil。
    public let myRank: Int?
    /// 今回の入れ替えで上がった段数（アニメのときだけ）。
    public let delta: Int?
    /// 自分のすぐ上の行とその順位。
    public let above: RankingEntry?
    public let aboveRank: Int?
    /// 入れ替えが終わった（アニメ無しなら最初から true）。
    public let arrived: Bool
    /// 数え上げの途中の自分のスコア。
    public let myScore: Int
    public let countFrom: Int
    public let countStart: Date?
}

/// 順位表。`content` の下に一覧を置き、入れ替えアニメはここが持つ。
public struct RankingBoardView<Content: View>: View {
    let board: GameCenterBoard
    let motion: RankingMotion?
    let style: RankingBoardStyle
    let content: (RankingBoardState) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 行の並び（id → 0 始まりの位置）。アニメで動かす。
    @State private var order: [String: Int] = [:]
    @State private var myScore = 0
    @State private var countStart: Date?
    @State private var countFrom = 0
    @State private var flying = false
    @State private var arrived = false
    @State private var passedFlash: Set<String> = []
    @State private var animating = false

    public init(board: GameCenterBoard, motion: RankingMotion?, style: RankingBoardStyle,
                @ViewBuilder content: @escaping (RankingBoardState) -> Content) {
        self.board = board
        self.motion = motion
        self.style = style
        self.content = content
    }

    private var entries: [RankingEntry] { motion?.entries ?? RankingPlan.entries(of: board) }
    private var me: RankingEntry? { entries.first(where: \.isMe) }

    /// 行の順位。アニメの間は並びの位置、静止では Game Center の順位（上位の外の自分の行もそのまま出せる）。
    private func rank(of entry: RankingEntry) -> Int {
        animating ? (order[entry.id] ?? 0) + 1 : entry.rank
    }

    private var state: RankingBoardState {
        let myRank = me.map(rank(of:))
        var aboveEntry: RankingEntry?
        if let myRank, myRank > 1 { aboveEntry = entries.first(where: { order[$0.id] == myRank - 2 }) }
        let delta = motion.flatMap { motion in myRank.map { motion.from + 1 - $0 } }
        return RankingBoardState(myRank: myRank, delta: delta, above: aboveEntry,
                                 aboveRank: aboveEntry == nil ? nil : myRank.map { $0 - 1 },
                                 arrived: arrived, myScore: myScore, countFrom: countFrom, countStart: countStart)
    }

    public var body: some View {
        VStack(spacing: 14) {
            content(state)
            listCard
        }
        .onAppear(perform: setup)
    }

    // MARK: - 一覧

    private var listCard: some View {
        ZStack(alignment: .top) {
            ForEach(entries) { entry in
                let index = order[entry.id] ?? entries.firstIndex(of: entry) ?? 0
                RankingRow(entry: entry, rank: rank(of: entry), score: entry.isMe ? myScore : entry.score,
                           style: style, countFrom: countFrom, countStart: entry.isMe ? countStart : nil,
                           isFlying: entry.isMe && flying, isFlashing: passedFlash.contains(entry.id),
                           isLast: index == entries.count - 1)
                    .frame(height: style.rowHeight)
                    .offset(y: CGFloat(index) * style.rowHeight)
                    .zIndex(entry.isMe ? 10 : 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: style.rowHeight * CGFloat(entries.count),
               maxHeight: style.rowHeight * CGFloat(entries.count), alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .popCard()
    }

    // MARK: - アニメ

    private func setup() {
        order = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($1.id, $0) })
        myScore = me?.score ?? 0
        countFrom = myScore
        arrived = true
        guard let motion, !reduceMotion else {
            // アニメ無し: 最終の並びと記録をそのまま出す。
            if let motion { settle(motion) }
            return
        }
        arrived = false
        animating = true
        Task { await run(motion) }
    }

    /// 最終の並びに置く（Reduce Motion、または画面を離れたあと）。
    private func settle(_ motion: RankingMotion) {
        guard let meID = me?.id else { return }
        let passed = motion.entries.indices.filter { $0 >= motion.to && $0 < motion.from }.map { motion.entries[$0].id }
        for id in passed { order[id]? += 1 }
        order[meID] = motion.to
        myScore = motion.newScore
        countFrom = motion.newScore
        animating = true
    }

    @MainActor
    private func run(_ motion: RankingMotion) async {
        guard let meID = me?.id else { return }
        try? await Task.sleep(for: .seconds(0.7))
        // 1) スコアの数え上げ（自分の行と上のカードの両方）。
        countStart = Date()
        withGameAnimation(.easeOut(duration: 0.9)) { myScore = motion.newScore }
        try? await Task.sleep(for: .seconds(1.0))
        let from = motion.from, to = motion.to
        guard to < from else { arrived = true; return }
        // 2) 浮かせてから一気に。抜かれた行はまとめて 1 つ下がる。
        withGameAnimation(.spring(duration: 0.25, bounce: 0.3)) { flying = true }
        try? await Task.sleep(for: .seconds(0.3))
        let passedIDs = motion.entries.indices.filter { $0 >= to && $0 < from }.map { motion.entries[$0].id }
        withGameAnimation(.spring(duration: 0.75, bounce: 0.2)) {
            for id in passedIDs { order[id]? += 1 }
            order[meID] = to
        }
        try? await Task.sleep(for: .seconds(0.6))
        passedFlash = Set(passedIDs)
        withGameAnimation(.spring(duration: 0.4, bounce: 0.45)) { flying = false; arrived = true }
        try? await Task.sleep(for: .seconds(0.35))
        withGameAnimation(.easeOut(duration: 0.4)) { passedFlash = [] }
    }
}

/// 一覧の 1 行。順位の丸（1〜3 位は金・銀・銅）・名前・スコア。自分の行は黄色の面と左の赤い帯。
public struct RankingRow: View {
    let entry: RankingEntry
    let rank: Int
    let score: Int
    let style: RankingBoardStyle
    var countFrom = 0
    var countStart: Date?
    var isFlying = false
    var isFlashing = false
    var isLast = false

    public init(entry: RankingEntry, rank: Int, score: Int, style: RankingBoardStyle, countFrom: Int = 0,
                countStart: Date? = nil, isFlying: Bool = false, isFlashing: Bool = false, isLast: Bool = false) {
        self.entry = entry
        self.rank = rank
        self.score = score
        self.style = style
        self.countFrom = countFrom
        self.countStart = countStart
        self.isFlying = isFlying
        self.isFlashing = isFlashing
        self.isLast = isLast
    }

    public var body: some View {
        HStack(spacing: 12) {
            rankBadge
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: entry.name).themeBody(15, weight: .heavy).foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if entry.isMe {
                        Text(tr("あなた")).themeCaption(10)
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.Fill.coral))
                    }
                }
                if let note = style.note(entry) {
                    Label(note, systemImage: "moon.stars.fill")
                        .themeCaption(11).foregroundStyle(entry.isMe ? Theme.purpleOnMeRowText : Theme.purpleText)
                }
            }
            Spacer(minLength: 8)
            Group {
                if entry.isMe {
                    CountUpText(from: countFrom, to: score, start: countStart, duration: 0.9, format: style.format)
                } else {
                    Text(verbatim: style.format(score))
                }
            }
            .scaledFont(style.scoreSize(entry), weight: .heavy, design: .rounded, maxScale: 1.2).monospacedDigit()
            .foregroundStyle(Theme.ink)
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if entry.isMe { Rectangle().fill(Theme.coral).frame(width: 4) }
        }
        .overlay(alignment: .bottom) {
            if !isLast { Rectangle().fill(Theme.inkSub.opacity(0.18)).frame(height: 1).padding(.leading, 56) }
        }
        .scaleEffect(isFlying ? 1.04 : 1)
        .shadow(color: .black.opacity(isFlying ? 0.18 : 0), radius: 10, y: 6)
        .accessibilityElement(children: .combine)
    }

    private var rowBackground: some View {
        ZStack {
            if entry.isMe { Theme.Fill.yellow.opacity(isFlying ? 0.5 : 0.25) }
            if isFlashing { Theme.Fill.pink.opacity(0.18) }
        }
    }

    private var rankBadge: some View {
        let medal: Color? = rank == 1 ? Color(hex: 0xFFC24B) : rank == 2 ? Color(hex: 0xC9C9CF) : rank == 3 ? Color(hex: 0xD9A066) : nil
        return ZStack {
            if let medal {
                Circle().fill(medal)
            } else {
                Circle().strokeBorder(Theme.inkSub.opacity(0.5), lineWidth: 1.5)
            }
            Text(verbatim: "\(rank)")
                .scaledFont(rank <= 3 ? 15 : 14, weight: rank <= 3 ? .black : .heavy, design: .rounded)
                .foregroundStyle(medal == nil ? Theme.ink : Theme.onAccent)
                .contentTransition(.numericText(countsDown: true))
        }
        .frame(width: 30, height: 30)
    }
}

/// `start` から `duration` 秒かけて `from` → `to` に数え上げるスコアの文字。`start` が nil なら `to` を出す。
public struct CountUpText: View {
    let from: Int
    let to: Int
    let start: Date?
    let duration: Double
    let format: (Int) -> String

    public init(from: Int, to: Int, start: Date?, duration: Double, format: @escaping (Int) -> String) {
        self.from = from
        self.to = to
        self.start = start
        self.duration = duration
        self.format = format
    }

    public var body: some View {
        TimelineView(AnimationTimelineSchedule(minimumInterval: nil, paused: start == nil)) { context in
            Text(verbatim: format(value(at: context.date)))
        }
    }

    private func value(at date: Date) -> Int {
        guard let start else { return to }
        let p = min(1, max(0, date.timeIntervalSince(start) / duration))
        let eased = 1 - pow(1 - p, 3)
        return from + Int((Double(to - from) * eased).rounded())
    }
}
