import SwiftUI

/// 入れ替えアニメの案。
enum RankAnimationPlan: String {
    /// A: 1 段ずつ抜く（抜かれた行がそのたびに 1 つ下がる・順位の数字が 1 つずつ減る）。
    case stepwise
    /// B: 数字を数え上げてから一気に飛び上がる（抜かれた行はまとめて下がる）。
    case swoop
}

enum RankingMode: Equatable {
    /// 静止（数字は確定済み）。
    case still
    /// 入れ替えアニメ（`before` → 今回の結果で自分の行が上がる）。
    case animate(RankAnimationPlan)
}

/// 週間ランキングのページ。リザルト（演出）→ **ここ** → 結果ページ（#1792）。
struct RankingPage: View {
    let entries: [RankEntry]
    let mode: RankingMode
    var newMeters: Int? = nil
    var lastWeekRank: Int? = 12
    var onNext: () -> Void = {}

    /// 行の並び（id → 0 始まりの順位）。アニメで動かす。
    @State private var order: [Int: Int] = [:]
    @State private var myMeters: Int = 0
    @State private var countStart: Date? = nil
    @State private var countFrom: Int = 0
    @State private var flying = false
    @State private var arrived = false
    @State private var passedFlash: Set<Int> = []

    static let rowHeight: CGFloat = 54

    private var me: RankEntry { entries.first { $0.isMe } ?? entries[0] }
    private var myRank: Int { (order[me.id] ?? 0) + 1 }
    private var participants: Int { entries.count }

    /// 現在の並びで自分の 1 つ上の人。
    private var above: (entry: RankEntry, rank: Int)? {
        guard myRank > 1, let e = entries.first(where: { order[$0.id] == myRank - 2 }) else { return nil }
        return (e, myRank - 1)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard
                myCard
                listCard
                note
                actions
                    .padding(.top, 6)
            }
            .padding(Theme.pad)
        }
        .popBackground()
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
                Text(verbatim: "10/5（月）〜 10/11（日）　あと 3 日")
                    .themeCaption(12).foregroundStyle(Theme.inkSub)
            }
            Spacer(minLength: 0)
            Chip(text: "\(participants) 人", systemImage: "person.2.fill", fill: Theme.Fill.teal)
        }
        .padding(14)
        .popCard()
    }

    // MARK: - 自分

    private var myCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("今週のあなた").themeCaption(12).foregroundStyle(Theme.inkSub)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(verbatim: "\(myRank)")
                        .scaledFont(46, weight: .black, design: .rounded).monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    Text("位").scaledFont(22, weight: .heavy, design: .rounded)
                    if arrived, let delta = lastDelta, delta > 0 {
                        Chip(text: "↑ \(delta)", fill: Theme.Fill.pink)
                            .padding(.leading, 8)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .foregroundStyle(Theme.ink)
                CountUpText(from: countFrom, to: myMeters, start: countStart, duration: 0.9)
                    .scaledFont(22, weight: .heavy, design: .rounded).monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                if let lastWeekRank {
                    Text(verbatim: "先週は \(lastWeekRank)位").themeCaption(12).foregroundStyle(Theme.inkSub)
                }
                if !arrived {
                    Text(verbatim: " ").themeCaption(13)
                } else if let above {
                    Text(verbatim: RankText.gap(to: above.entry, from: RankEntry(id: 0, name: "", meters: myMeters), aboveRank: above.rank))
                        .themeCaption(13).foregroundStyle(Theme.coral)
                        .multilineTextAlignment(.trailing)
                } else {
                    Text("今週の 1 位！").themeCaption(13).foregroundStyle(Theme.coral)
                }
            }
        }
        .padding(14)
        .popCard()
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
            .strokeBorder(Theme.Fill.coral, lineWidth: 2))
    }

    /// 今回の入れ替えで上がった段数（アニメのときだけ）。
    private var lastDelta: Int? {
        guard case .animate = mode, let before = entries.firstIndex(where: { $0.isMe }) else { return nil }
        return before + 1 - myRank
    }

    // MARK: - 一覧

    private var listCard: some View {
        ZStack(alignment: .top) {
            ForEach(entries) { entry in
                let index = order[entry.id] ?? 0
                RankRow(entry: entry, rank: index + 1, meters: entry.isMe ? myMeters : entry.meters,
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

    private var note: some View {
        VStack(spacing: 4) {
            Text("毎週月曜 0:00 に切り替わります。1 人 1 件（その週の自己ベスト）。月まで飛んだ打球は 384,400 km として数えます")
                .themeCaption(11).foregroundStyle(Theme.inkSub)
            Text("ランキングは予告なく終了する場合があります")
                .themeCaption(11).foregroundStyle(Theme.inkSub)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        Button(action: onNext) {
            HStack(spacing: 8) {
                Text("結果を見る").themeBody(18)
                Image(systemName: "chevron.right").scaledFont(15, weight: .bold)
            }
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .tint(Theme.Fill.coral)
    }

    // MARK: - アニメ

    private func setup() {
        order = Dictionary(uniqueKeysWithValues: entries.indices.map { (entries[$0].id, $0) })
        myMeters = me.meters
        countFrom = me.meters
        guard case .animate(let plan) = mode, let newMeters else { arrived = true; return }
        Task { await run(plan, newMeters: newMeters) }
    }

    /// 新しい記録での自分の順位（0 始まり）。
    private func targetIndex(newMeters: Int) -> Int {
        entries.filter { !$0.isMe && $0.meters > newMeters }.count
    }

    @MainActor
    private func run(_ plan: RankAnimationPlan, newMeters: Int) async {
        try? await Task.sleep(for: .seconds(0.7))
        // 1) 距離の数え上げ（自分の行と上のカードの両方）。
        countStart = Date()
        withAnimation(.easeOut(duration: 0.9)) { myMeters = newMeters }
        try? await Task.sleep(for: .seconds(1.0))
        let from = order[me.id] ?? 0
        let to = targetIndex(newMeters: newMeters)
        guard to < from else { arrived = true; return }
        switch plan {
        case .stepwise:
            // 2A) 1 段ずつ抜く。抜かれた行はそのたびに 1 つ下がる。段数が多いほど少し速く（合計 1.6 秒まで）。
            let step = min(0.3, 1.6 / Double(from - to))
            withAnimation(.easeOut(duration: 0.2)) { flying = true }
            for i in stride(from: from - 1, through: to, by: -1) {
                let passed = entries.first { order[$0.id] == i }!
                withAnimation(.spring(duration: step * 1.2, bounce: 0.25)) {
                    order[passed.id] = i + 1
                    order[me.id] = i
                }
                passedFlash.insert(passed.id)
                try? await Task.sleep(for: .seconds(step))
                passedFlash.remove(passed.id)
            }
            withAnimation(.spring(duration: 0.4, bounce: 0.4)) { flying = false; arrived = true }
        case .swoop:
            // 2B) 浮かせてから一気に。抜かれた行はまとめて 1 つ下がる。
            withAnimation(.spring(duration: 0.25, bounce: 0.3)) { flying = true }
            try? await Task.sleep(for: .seconds(0.3))
            let passedIDs = entries.filter { order[$0.id]! >= to && order[$0.id]! < from }.map(\.id)
            withAnimation(.spring(duration: 0.75, bounce: 0.2)) {
                for id in passedIDs { order[id]! += 1 }
                order[me.id] = to
            }
            try? await Task.sleep(for: .seconds(0.6))
            passedFlash = Set(passedIDs)
            withAnimation(.spring(duration: 0.4, bounce: 0.45)) { flying = false; arrived = true }
            try? await Task.sleep(for: .seconds(0.35))
            withAnimation(.easeOut(duration: 0.4)) { passedFlash = [] }
        }
    }
}

/// 一覧の 1 行。順位の丸（1〜3 位は金・銀・銅）・名前・距離。自分の行は黄色の面と左の赤い帯。
struct RankRow: View {
    let entry: RankEntry
    let rank: Int
    let meters: Int
    var countFrom: Int = 0
    var countStart: Date? = nil
    var isFlying = false
    var isFlashing = false
    var isLast = false

    var body: some View {
        HStack(spacing: 12) {
            rankBadge
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: entry.name).themeBody(15, weight: .heavy).foregroundStyle(Theme.ink)
                    if entry.isMe {
                        Text("あなた").themeCaption(10)
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.Fill.coral))
                    }
                }
                if let note = RankText.moonNote(entry) {
                    Label(note, systemImage: "moon.stars.fill")
                        .themeCaption(11).foregroundStyle(Theme.purple)
                }
            }
            Spacer(minLength: 8)
            if entry.isMe {
                CountUpText(from: countFrom, to: meters, start: countStart, duration: 0.9)
                    .scaledFont(entry.moonCount > 0 ? 17 : 18, weight: .heavy, design: .rounded).monospacedDigit()
                    .foregroundStyle(Theme.ink)
            } else {
                Text(verbatim: RankText.distance(meters))
                    .scaledFont(entry.moonCount > 0 ? 17 : 18, weight: .heavy, design: .rounded).monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
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
    }

    private var rowBackground: some View {
        ZStack {
            if entry.isMe { Theme.Fill.yellow.opacity(isFlying ? 0.5 : 0.25) }
            if isFlashing { Theme.Fill.pink.opacity(0.18) }
        }
    }

    private var rankBadge: some View {
        let medal: Color? = rank == 1 ? hexColor(0xFFC24B) : rank == 2 ? hexColor(0xC9C9CF) : rank == 3 ? hexColor(0xD9A066) : nil
        return ZStack {
            if let medal {
                Circle().fill(medal)
                Text(verbatim: "\(rank)")
                    .scaledFont(15, weight: .black, design: .rounded)
                    .foregroundStyle(Theme.onAccent)
                    .contentTransition(.numericText(countsDown: true))
            } else {
                Circle().strokeBorder(Theme.inkSub.opacity(0.5), lineWidth: 1.5)
                Text(verbatim: "\(rank)")
                    .scaledFont(14, weight: .heavy, design: .rounded)
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(countsDown: true))
            }
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
        TimelineView(.animation(paused: start == nil)) { ctx in
            let value: Int = {
                guard let start else { return to }
                let p = min(1, max(0, ctx.date.timeIntervalSince(start) / duration))
                let e = 1 - pow(1 - p, 3)
                return from + Int((Double(to - from) * e).rounded())
            }()
            Text(verbatim: RankText.distance(value))
        }
    }
}
