import SwiftUI
import Core
import HomerunCore

/// 今週のランキングのページ（#1792）。10 球の結果の演出 → **ここ** → 結果ページの順に挟む
/// （Game Center にサインインしている人だけ。会長決定 2026-10-08）。結果ページの「今週のランキング」の行からも開ける。
///
/// 画面と入れ替えアニメはモック（`docs/design/homerun-ranking/`・会長確認済み 2026-10-09）の形。
/// アニメは B 案「一気に飛び上がる」: 総飛距離が数え上がる → 自分の行が 1 回のバネ運動で目的の順位へ →
/// 抜かれた行がまとめて 1 つ下がり光る → 順位の数字が直接めくれる。Reduce Motion では最終の並びをそのまま出す。
struct HomerunRankingPage: View {
    enum Content: Equatable {
        /// 順位表を読んでいる最中。
        case loading
        /// 読めなかった（オフライン・Game Center の不調）。
        case failed
        /// 読めた。`motion` があれば入れ替えアニメを流す。
        case ready(board: GameCenterBoard, motion: HomerunRankingMotion?)
    }

    let content: Content
    let nextTitle: String
    let onNext: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                switch content {
                case .loading:
                    statusCard(icon: nil, text: "今週の順位を読み込んでいます")
                case .failed:
                    statusCard(icon: "wifi.slash", text: "ランキングを取得できませんでした。通信状況を確かめて、結果ページの「今週のランキング」からもう一度開いてください")
                case .ready(let board, let motion):
                    HomerunRankingBoardView(board: board, motion: motion)
                }
                notes
                Button(action: onNext) {
                    HStack(spacing: 8) {
                        Text(nextTitle).themeBody(18)
                        Image(systemName: "chevron.right").scaledFont(15, weight: .bold)
                    }
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(Theme.Fill.coral)
                .padding(.top, 6)
            }
            .padding(Theme.pad)
        }
        .popBackground()
    }

    private func statusCard(icon: String?, text: String) -> some View {
        VStack(spacing: 12) {
            if let icon {
                Image(systemName: icon).scaledFont(30, weight: .bold).foregroundStyle(Theme.inkSub)
            } else {
                ProgressView()
            }
            Text(text).themeBody(14).foregroundStyle(Theme.inkSub).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .popCard()
    }

    private var notes: some View {
        VStack(spacing: 4) {
            Text("毎週月曜 0:00 に切り替わります。1 人 1 件（その週の自己ベスト）。月まで飛んだ打球は 384,400 km として数えます")
            Text("ランキングは予告なく終了する場合があります")
        }
        .themeCaption(11).foregroundStyle(Theme.inkSub)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// Game Center にサインインしていない人のランキングページ（会長決定 2026-10-08: 「登録すると見られます」の案内だけ）。
struct HomerunRankingSignedOutPage: View {
    let nextTitle: String
    let onNext: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 12) {
                    HomerunOjisanImageView().frame(width: 120, height: 120)
                    Text("ランキングは Game Center に登録すると見られます")
                        .themeBody(17, weight: .heavy).foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                    Text("週間ランキングは Game Center の仕組みを使っています。設定アプリで Game Center にサインインすると、次の挑戦から今週の順位が出ます。")
                        .themeBody(13).foregroundStyle(Theme.inkSub)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .popCard()

                VStack(spacing: 4) {
                    Text("毎週月曜 0:00 に切り替わります。1 人 1 件（その週の自己ベスト）")
                    Text("ランキングは予告なく終了する場合があります")
                }
                .themeCaption(11).foregroundStyle(Theme.inkSub)
                .multilineTextAlignment(.center)

                Button(action: onNext) {
                    HStack(spacing: 8) {
                        Text(nextTitle).themeBody(18)
                        Image(systemName: "chevron.right").scaledFont(15, weight: .bold)
                    }
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(Theme.Fill.coral)
                .padding(.top, 6)
            }
            .padding(Theme.pad)
        }
        .popBackground()
    }
}

/// 見出し・自分のカード・一覧。入れ替えアニメはここが持つ。
struct HomerunRankingBoardView: View {
    let board: GameCenterBoard
    let motion: HomerunRankingMotion?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 行の並び（id → 0 始まりの位置）。アニメで動かす。
    @State private var order: [String: Int] = [:]
    @State private var myMeters = 0
    @State private var countStart: Date?
    @State private var countFrom = 0
    @State private var flying = false
    @State private var arrived = false
    @State private var passedFlash: Set<String> = []
    @State private var animating = false

    static let rowHeight: CGFloat = 54

    private var entries: [HomerunRankEntry] { motion?.entries ?? HomerunRankingPlan.entries(of: board) }
    private var me: HomerunRankEntry? { entries.first(where: \.isMe) }

    /// 行の順位。アニメの間は並びの位置、静止では Game Center の順位（上位の外の自分の行もそのまま出せる）。
    private func rank(of entry: HomerunRankEntry) -> Int {
        animating ? (order[entry.id] ?? 0) + 1 : entry.rank
    }

    private var myRank: Int? { me.map(rank(of:)) }

    private var above: (entry: HomerunRankEntry, rank: Int)? {
        guard let myRank, myRank > 1, let e = entries.first(where: { order[$0.id] == myRank - 2 }) else { return nil }
        return (e, myRank - 1)
    }

    /// 今回の入れ替えで上がった段数（アニメのときだけ）。
    private var delta: Int? {
        guard let motion, let myRank else { return nil }
        return motion.from + 1 - myRank
    }

    var body: some View {
        VStack(spacing: 14) {
            headerCard
            myCard
            listCard
        }
        .onAppear(perform: setup)
    }

    // MARK: - 見出し

    private var headerCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .scaledFont(26, weight: .bold)
                .foregroundStyle(Theme.yellow)
            VStack(alignment: .leading, spacing: 3) {
                Text("今週のランキング").themeBody(16).foregroundStyle(Theme.ink)
                if let range = HomerunRankingText.weekRange(start: board.start, end: board.end, now: Date()) {
                    Text(verbatim: range).themeCaption(12).foregroundStyle(Theme.inkSub)
                }
            }
            Spacer(minLength: 0)
            Label(String(board.participants) + " 人", systemImage: "person.2.fill")
                .labelStyle(ChipLabelStyle(fill: Theme.Fill.teal))
        }
        .padding(14)
        .popCard()
    }

    // MARK: - 自分

    @ViewBuilder private var myCard: some View {
        if let myRank {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今週のあなた").themeCaption(12).foregroundStyle(Theme.inkSub)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(verbatim: "\(myRank)")
                            .scaledFont(46, weight: .black, design: .rounded, maxScale: 1.2).monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                        Text("位").scaledFont(22, weight: .heavy, design: .rounded, maxScale: 1.2)
                        if arrived, let delta, delta > 0 {
                            ChipText(text: "↑ \(delta)", fill: Theme.Fill.pink)
                                .padding(.leading, 8)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .foregroundStyle(Theme.ink)
                    CountUpText(from: countFrom, to: myMeters, start: countStart, duration: 0.9)
                        .scaledFont(22, weight: .heavy, design: .rounded, maxScale: 1.2).monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    if let lastWeek = board.lastWeekRank {
                        Text(verbatim: "先週は \(lastWeek)位").themeCaption(12).foregroundStyle(Theme.inkSub)
                    }
                    if !arrived {
                        Text(verbatim: " ").themeCaption(13)
                    } else if let above {
                        Text(verbatim: HomerunRankingText.gap(aboveMeters: above.entry.meters, myMeters: myMeters, aboveRank: above.rank))
                            .themeCaption(13).foregroundStyle(Theme.coral)
                            .multilineTextAlignment(.trailing)
                    } else if myRank == 1 {
                        Text("今週の 1 位！").themeCaption(13).foregroundStyle(Theme.coral)
                    }
                }
            }
            .padding(14)
            .popCard()
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(Theme.Fill.coral, lineWidth: 2))
        } else {
            HStack {
                Text("今週はまだ記録がありません").themeBody(15).foregroundStyle(Theme.inkSub)
                Spacer(minLength: 0)
            }
            .padding(14)
            .popCard()
        }
    }

    // MARK: - 一覧

    private var listCard: some View {
        ZStack(alignment: .top) {
            ForEach(entries) { entry in
                let index = order[entry.id] ?? entries.firstIndex(of: entry) ?? 0
                HomerunRankRow(entry: entry, rank: rank(of: entry), meters: entry.isMe ? myMeters : entry.meters,
                               countFrom: countFrom, countStart: entry.isMe ? countStart : nil,
                               isFlying: entry.isMe && flying, isFlashing: passedFlash.contains(entry.id),
                               isLast: index == entries.count - 1)
                    .frame(height: Self.rowHeight)
                    .offset(y: CGFloat(index) * Self.rowHeight)
                    .zIndex(entry.isMe ? 10 : 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight * CGFloat(entries.count),
               maxHeight: Self.rowHeight * CGFloat(entries.count), alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .popCard()
    }

    // MARK: - アニメ

    private func setup() {
        order = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($1.id, $0) })
        myMeters = me?.meters ?? 0
        countFrom = myMeters
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
    private func settle(_ motion: HomerunRankingMotion) {
        guard let meID = me?.id else { return }
        let passed = motion.entries.indices.filter { $0 >= motion.to && $0 < motion.from }.map { motion.entries[$0].id }
        for id in passed { order[id]? += 1 }
        order[meID] = motion.to
        myMeters = motion.newMeters
        countFrom = motion.newMeters
        animating = true
    }

    @MainActor
    private func run(_ motion: HomerunRankingMotion) async {
        guard let meID = me?.id else { return }
        try? await Task.sleep(for: .seconds(0.7))
        // 1) 距離の数え上げ（自分の行と上のカードの両方）。
        countStart = Date()
        withGameAnimation(.easeOut(duration: 0.9)) { myMeters = motion.newMeters }
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

/// 一覧の 1 行。順位の丸（1〜3 位は金・銀・銅）・名前・距離。自分の行は黄色の面と左の赤い帯。
struct HomerunRankRow: View {
    let entry: HomerunRankEntry
    let rank: Int
    let meters: Int
    var countFrom = 0
    var countStart: Date?
    var isFlying = false
    var isFlashing = false
    var isLast = false

    var body: some View {
        HStack(spacing: 12) {
            rankBadge
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: entry.name).themeBody(15, weight: .heavy).foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if entry.isMe {
                        Text("あなた").themeCaption(10)
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.Fill.coral))
                    }
                }
                if let note = HomerunRankingText.moonNote(entry) {
                    Label(note, systemImage: "moon.stars.fill")
                        .themeCaption(11).foregroundStyle(Theme.purple)
                }
            }
            Spacer(minLength: 8)
            Group {
                if entry.isMe {
                    CountUpText(from: countFrom, to: meters, start: countStart, duration: 0.9)
                } else {
                    Text(verbatim: HomerunRankingText.distance(meters))
                }
            }
            .scaledFont(entry.moonCount > 0 ? 17 : 18, weight: .heavy, design: .rounded, maxScale: 1.2).monospacedDigit()
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

/// `start` から `duration` 秒かけて `from` → `to` に数え上げる距離の文字。`start` が nil なら `to` を出す。
struct CountUpText: View {
    let from: Int
    let to: Int
    let start: Date?
    let duration: Double

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { context in
            Text(verbatim: HomerunRankingText.distance(value(at: context.date)))
        }
    }

    private func value(at date: Date) -> Int {
        guard let start else { return to }
        let p = min(1, max(0, date.timeIntervalSince(start) / duration))
        let eased = 1 - pow(1 - p, 3)
        return from + Int((Double(to - from) * eased).rounded())
    }
}

/// 差し色のチップ（結果画面の `chip` と同じ見た目）。
struct ChipText: View {
    let text: String
    var fill: Color = Theme.Fill.yellow
    var body: some View {
        Text(verbatim: text)
            .themeCaption(12)
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(fill))
    }
}

struct ChipLabelStyle: LabelStyle {
    let fill: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
        .themeCaption(12)
        .foregroundStyle(Theme.onAccent)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(fill))
    }
}
