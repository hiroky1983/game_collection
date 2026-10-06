import SwiftUI
import Core
import HomerunCore

/// 打席前に置く「記録と実績 ›」の 1 行（会長指示 2026-10-04）。押すと `HomerunRecordsPage` へ移る。
struct HomerunRecordsLink: View {
    let model: HomerunModel
    let ads: AdService

    var body: some View {
        NavigationLink {
            HomerunRecordsPage(model: model, ads: ads)
        } label: {
            HStack {
                Label("記録と実績", systemImage: "trophy.fill")
                    .themeBody(16)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(verbatim: "\(model.achievements.count) / \(HomerunAchievement.allCases.count)")
                    .themeBody(16, weight: .heavy)
                    .foregroundStyle(Theme.inkSub)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.inkSub)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .popCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("記録と実績。実績 \(model.achievements.count) / \(HomerunAchievement.allCases.count)")
        .accessibilityHint("記録と実績の一覧を開きます")
    }
}

/// 「記録と実績」のページ（会長指示 2026-10-04）。上に通算の記録、その下に実績の一覧（`HomerunAchievementsCard`）。
/// 記録と実績のあいだに 300×250 の広告を 1 枠（会長決裁 2026-10-04）。このページは画面下の固定バナーを置かない（広告は 1 枠）。
/// 戻るボタン・押せる要素から離すため、広告の上下に `HomerunRecordsAdGap.around` の余白を取る（#1749）。
struct HomerunRecordsPage: View {
    let model: HomerunModel
    let ads: AdService

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HomerunRecordsCard(records: model.records)
                MediumRectangleSlot(ads: ads)
                    .padding(.vertical, HomerunRecordsAdGap.around)
                HomerunAchievementsCard(model: model)
            }
            .padding(Theme.pad)
        }
        .popBackground()
        .navigationTitle("記録と実績")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// 「記録と実績」ページの広告の上下に足す余白（#1749。VStack の間隔 14pt と合わせて上下とも 38pt 空く）。
enum HomerunRecordsAdGap {
    static let around: CGFloat = 24
}

/// 通算の記録（`HomerunRecords` の既存の値）を、実績と同じ大きめの文字で 1 列に並べる。
/// 月の 2 行は隠し要素なので、0 回のあいだは名前も回数も「？？？」で伏せる（行そのものは常に出す）。
struct HomerunRecordsCard: View {
    let records: HomerunRecords

    /// 1 行ぶん（名前・値）。`isHidden` は「？？？」の伏せ行。
    struct Row: Equatable {
        let title: String
        let value: String
        var isHidden = false
    }

    static func rows(_ r: HomerunRecords) -> [Row] {
        [
            Row(title: "自己ベスト（1 挑戦の合計）", value: HomerunText.meters(Double(r.bestTotalTenths) / 10)),
            Row(title: "最長の 1 本", value: HomerunText.meters(Double(r.longestTenths) / 10)),
            Row(title: "通算の飛距離", value: HomerunText.meters(Double(r.totalDistanceTenths) / 10)),
            Row(title: "通算 柵越え", value: "\(r.homers) 本"),
            Row(title: "挑戦回数", value: "\(r.challenges) 回"),
            hidden("月まで飛ばした", count: r.moonShots),
            hidden("月を割った", count: r.moonBreaks),
        ]
    }

    private static func hidden(_ title: String, count: Int) -> Row {
        count > 0 ? Row(title: title, value: "\(count) 回") : Row(title: "？？？", value: "？？？", isHidden: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("記録").themeBody(16).foregroundStyle(Theme.ink)
            ForEach(Array(Self.rows(records).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: row.title)
                        .themeBody(17, weight: .heavy)
                        .foregroundStyle(row.isHidden ? Theme.inkSub : Theme.ink)
                    Spacer(minLength: 8)
                    Text(verbatim: row.value)
                        .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(row.isHidden ? Theme.inkSub : Theme.ink)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(row.isHidden ? "まだ見つけていない記録" : "\(row.title) \(row.value)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popCard()
    }
}
