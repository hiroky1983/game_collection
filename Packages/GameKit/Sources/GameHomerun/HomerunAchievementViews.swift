import SwiftUI
import Core
import HomerunCore

/// 打席前の実績一覧（#1794）。**名前も条件も、解除するまでは「？？？」**で伏せ、解除したものだけ名前と条件が出る。
/// 一覧はいつも端末の記録（`HomerunModel.achievements`）を見て描く（Game Center の連携・通信の有無に関係なく見られる）。
struct HomerunAchievementsCard: View {
    let model: HomerunModel

    /// Game Center に連携していない人への注意（機種変更・アプリの削除で端末の記録が消えるため）。
    static let unlinkedNotice = "Game Center と連携していないと、機種変更やアプリの削除で実績が消えます"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("実績").themeBody(16).foregroundStyle(Theme.ink)
                Spacer()
                Text(verbatim: "\(model.achievements.count) / \(HomerunAchievement.allCases.count)")
                    .themeBody(16, weight: .heavy)
                    .foregroundStyle(Theme.inkSub)
            }
            // 1 列の縦並び（文字を大きく読ませる・会長指示 2026-10-04。以前は横 2 列のグリッド）。
            VStack(alignment: .leading, spacing: 12) {
                ForEach(HomerunAchievement.allCases, id: \.self) { achievement in
                    tile(achievement)
                }
            }
            if !model.gameCenterLinked {
                Text(Self.unlinkedNotice)
                    .themeCaption(11)
                    .foregroundStyle(Theme.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .popCard()
    }

    private func tile(_ achievement: HomerunAchievement) -> some View {
        let unlocked = model.achievements.contains(achievement)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: unlocked ? "trophy.fill" : "lock.fill")
                .font(.system(size: 22))
                .foregroundStyle(unlocked ? Theme.yellow : Theme.inkSub.opacity(0.5))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: unlocked ? achievement.title : "？？？")
                    .themeBody(17, weight: .heavy)
                    .foregroundStyle(unlocked ? Theme.ink : Theme.inkSub)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if unlocked {
                    Text(verbatim: achievement.detail)
                        .themeCaption(13)
                        .foregroundStyle(Theme.inkSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(unlocked ? "\(achievement.title)。\(achievement.detail)" : "未解除の実績")
    }
}

/// 打席に重ねる「実績解禁」（#1794）。1 球の結果の演出が終わってから、次の球の構えのあいだに出す。
struct HomerunUnlockBanner: View {
    let items: [HomerunAchievement]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("実績解禁！").themeCaption(12).foregroundStyle(Theme.coral)
                ForEach(items, id: \.self) { item in
                    Text(verbatim: item.title)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .popCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("実績解禁。" + items.map(\.title).joined(separator: "、"))
    }
}

/// 10 球の結果に並べる、この挑戦で解除した実績（#1794）。
struct HomerunUnlockedCard: View {
    let items: [HomerunAchievement]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("実績解禁！", systemImage: "trophy.fill")
                    .themeBody(16, weight: .heavy)
                    .foregroundStyle(Theme.ink)
                ForEach(items, id: \.self) { item in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: item.title).themeBody(15, weight: .heavy).foregroundStyle(Theme.coral)
                        Text(verbatim: item.detail).themeCaption(11).foregroundStyle(Theme.inkSub)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .popCard()
        }
    }
}
