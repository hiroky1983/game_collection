import SwiftUI

/// 起動引数 `-scene <名前>` で出す画面を選ぶ。
/// few / many / signedout / animA / animB / flow / flow-b
@main
struct RankingMockApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    private let scene: String = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-scene"), i + 1 < args.count { return args[i + 1] }
        return "many"
    }()

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {} label: { Label("戻る", systemImage: "chevron.left") }
                    }
                    ToolbarItem(placement: .principal) {
                        Text("柵越えおじさん").themeBody(20, weight: .bold)
                    }
                }
                .toolbarBackground(Theme.background, for: .navigationBar)
                .tint(Theme.coral)
        }
    }

    @ViewBuilder private var content: some View {
        switch scene {
        case "few":
            RankingPage(entries: MockData.few, mode: .still, lastWeekRank: 3)
        case "signedout":
            SignedOutRankingPage()
        case "animA":
            RankingPage(entries: MockData.animBefore, mode: .animate(.stepwise), newMeters: MockData.animNewMeters)
        case "animB":
            RankingPage(entries: MockData.animBefore, mode: .animate(.swoop), newMeters: MockData.animNewMeters)
        case "flow":
            FlowView(plan: .stepwise)
        case "flow-b":
            FlowView(plan: .swoop)
        default:
            RankingPage(entries: MockData.many, mode: .still)
        }
    }
}

/// リザルト（演出）→ ランキング → 結果 の流れ。自動で進む（録画用）。
struct FlowView: View {
    let plan: RankAnimationPlan
    @State private var step = 0

    var body: some View {
        ZStack {
            switch step {
            case 0:
                FinaleMockPage(homers: 6, total: MockData.animNewMeters) { advance() }
                    .toolbar(.hidden, for: .navigationBar)
                    .transition(.opacity)
            case 1:
                RankingPage(entries: MockData.animBefore, mode: .animate(plan), newMeters: MockData.animNewMeters) { advance() }
                    .transition(.opacity)
            default:
                ResultMockPage(homers: 6, total: MockData.animNewMeters, rank: 4, rankDelta: 5)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
        .task {
            try? await Task.sleep(for: .seconds(2.6))
            if step == 0 { advance() }
            try? await Task.sleep(for: .seconds(5.5))
            if step == 1 { advance() }
        }
    }

    private func advance() { step += 1 }
}
