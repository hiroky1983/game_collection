import Core
import SwiftUI

/// `RunnerView` の画面上部（面の見出し・スピード・進み具合と一時停止ボタン）。
///
/// #1106 で `RunnerView.swift` から分けた。`RunnerScene` を `+Course` / `+Hazards` へ割った
/// #830 と同じ extension 方式で、**見た目は 1 ビットも変えていない**。
extension RunnerView {
    // MARK: - ヘッダー

    /// 面の見出し・スピード・進み具合を 1 行にまとめた画面上部のセクション。
    ///
    /// #931 で**秒数（タイム・ベストタイム）を外した**（会長決裁「ステージのタイムは要らない」。
    /// ステージ制は難しい横スクロールを攻略して先へ進むのが主役で、秒を縮める遊びではない）。
    /// 代わりに「いまどの面を走っているか」（`RunnerAccessibility.stageHeadline`）を主役にする。
    /// ベストタイムのチップ一覧も無くなったので 1 行だけになり、浮いた縦幅は `course` が取る。
    /// **モードを切り替えても高さが変わらない**よう、ステージ制とエンドレスで同じ 3 区画の並び
    /// （左: 見出し / 中: スピード / 右: 進み具合か自己ベスト）にしてある。
    var topSummary: some View {
        header
            .padding(.horizontal, 16).padding(.vertical, 10)
            .popCard(corner: Theme.cornerSmall)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            switch model.mode {
            case .stages:  stageHeadline
            case .endless: distanceReadout
            }
            speedMeter
            Spacer(minLength: 0)
            switch model.mode {
            case .stages:  progressReadout
            case .endless: endlessBestReadout
            }
        }
    }

    /// ステージ制の見出し。「ステージ 9 / 18」の小さな行の下に「2-3」（#931。面の名前は #946 で
    /// 外し、番号だけ）。
    private var stageHeadline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(RunnerAccessibility.stageLabel(number: model.stageNumber, total: RunnerRules.stageCount))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            Text(stageHeadlineText)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement()
        // 番号に世界の名前（#703）と「世界-面」の表記を添える——画面では背景の色で分かる
        // 「どこを走っているか」を、見えない人にも言葉で伝える。
        .accessibilityLabel(
            RunnerAccessibility.stageLabelWithWorld(number: model.stageNumber, total: RunnerRules.stageCount)
                + "、" + stageHeadlineText
        )
    }

    /// ステージ制の進み具合。ゲージだけでは何のゲージか分からないので「ゴールまで」の見出しを添える。
    private var progressReadout: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("ゴールまで")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            progressBar
        }
        .accessibilityElement()
        .accessibilityLabel(RunnerAccessibility.progressLabel(model.field.progress))
    }

    /// エンドレス（#675）は「ステージ N / 18」と進み具合の代わりに走行距離を出す。
    /// コースに終わりは無い（#1086）ので、進み具合という物差しそのものが無い。
    private var distanceReadout: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("走行距離")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            shrinkingNumber(distanceText(model.distanceMeters), size: 22)
        }
        .accessibilityElement()
        .accessibilityLabel(RunnerAccessibility.distanceLabel(model.distanceMeters))
    }

    /// エンドレスの自己ベスト（走行距離）。走りながら「あとどれだけで更新か」を読めるように残す。
    private var endlessBestReadout: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("自己ベスト")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            shrinkingNumber(model.endlessBestDistance.map(distanceText) ?? "–", size: 15, alignment: .trailing)
        }
        .accessibilityElement()
        .accessibilityLabel(RunnerAccessibility.bestDistanceLabel(model.endlessBestDistance))
    }

    /// ヘッダーの数字。入りきらない幅では切らずに縮める（#1086）。
    ///
    /// コースに終わりが無いので走行距離は 7 桁以上になる。SE の幅で走行距離と自己ベストが両方 7 桁のとき、
    /// 縮めずにいると「2,500,…」と切れた（実測）。縮めるとその行が低くなりヘッダーの高さ＝コースの大きさが
    /// 桁の増えた瞬間に変わるので、**縮める前の 1 行の高さを隠した型で取っておく**。
    private func shrinkingNumber(_ text: String, size: CGFloat, alignment: Alignment = .leading) -> some View {
        let font = Font.system(size: size, weight: .heavy, design: .rounded).monospacedDigit()
        return ZStack(alignment: alignment) {
            Text(verbatim: "0").font(font).hidden()
            Text(text)
                .font(font)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    /// 走行距離の表示（`1,234 m`）。単位はワールド単位だが、数字に「m」を添えて距離と分かるようにする。
    func distanceText(_ distance: Int) -> String {
        "\(RecordFormat.number(max(0, distance))) m"
    }

    /// ペダルの乗り（#569）。
    ///
    /// **いま速いのか遅いのか**を走りながら読めるようにする。倍率の数字は走行中に読めないので、
    /// 進み具合と同じ形のゲージにして伸び縮みだけで伝える。
    private var speedMeter: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("スピード")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Fill.coral.opacity(0.2))
                    Capsule().fill(Theme.Fill.coral)
                        .frame(width: geo.size.width * speedRatio)
                }
            }
            .frame(width: 64, height: 6)
        }
        .padding(.leading, 8)
        .accessibilityElement()
        .accessibilityLabel(RunnerAccessibility.speedLabel(ratio: speedRatio))
    }

    /// ゲージの割合。0 が基準の速さ、1 が上限。
    private var speedRatio: Double {
        let span = RunnerRules.maxPedalBoost - 1
        guard span > 0 else { return 0 }
        return min(1, max(0, (model.field.pedalBoost - 1) / span))
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Fill.coral.opacity(0.2))
                Capsule().fill(Theme.Fill.coral)
                    .frame(width: geo.size.width * model.field.progress)
            }
        }
        .frame(width: 88, height: 6)
    }

    var pauseButton: some View {
        Button {
            if model.phase == .paused { model.resume() } else { model.pause() }
        } label: {
            Image(systemName: model.phase == .paused ? "play.fill" : "pause.fill")
                .font(.system(size: 16, weight: .bold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.Fill.coral))
                .foregroundStyle(Theme.onAccent)
        }
        .buttonStyle(.pop)
        .accessibilityLabel(model.phase == .paused ? "再開" : "一時停止")
        // 止めるものが無い状態では押せない（締めの演出中 `.story` も同じ・#1092）。
        .disabled(
            model.phase.isSettling || model.phase == .story || model.phase == .failed
                || model.phase == .cleared || model.phase == .allCleared
        )
    }
}
