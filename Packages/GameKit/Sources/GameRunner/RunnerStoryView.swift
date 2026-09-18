import Core
import SwiftUI

// MARK: - ストーリーの場面（#1092）

/// 始まり・世界の締めを流すオーバーレイ。
///
/// 画面いっぱいを覆い、コマを `RunnerStory.panelDuration` 秒ずつ送る。**どこをタップしても
/// 場面ごと飛ばせる**（受け入れ条件「タップで飛ばせる」）。VoiceOver では台詞を読み、
/// 「とばす」ボタンで抜けられる。
///
/// **Reduce Motion（視差効果を減らす）がオンのときは、コマの入れ替えを動かさない**
/// （`gameAnimation` 経由。会長決裁の受け入れ条件 B）。コマ送りそのものは止めない
/// ——止めると話が読めなくなるので、「動きを止めた 1 枚絵＋台詞」を順に見せる形にする。
struct RunnerStoryView: View {
    let scene: RunnerStoryScene
    /// 見終えた / 飛ばした。
    let onFinish: () -> Void
    /// 撮影・QA で止めるコマ（`-simulateRunner story-intro:3`）。nil ならふつうにコマ送りする。
    var frozenPanel: Int?

    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var panels: [RunnerStoryPanel] { scene.panels }
    private var panel: RunnerStoryPanel { panels[min(index, panels.count - 1)] }

    var body: some View {
        ZStack {
            // 場面のあいだはコースを隠す（絵が主役。下の SpriteKit が透けると読めない）。
            Color.black.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                RunnerStoryArt.image(panel.art)
                    .aspectRatio(
                        CGFloat(RunnerStoryArt.panelWidth) / CGFloat(RunnerStoryArt.panelHeight),
                        contentMode: .fit
                    )
                    .frame(maxWidth: 440)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                Text(panel.line)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 440)
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.14))
                    )
                    .padding(.horizontal, 16)
                progressDots
                Spacer(minLength: 0)
                Button("とばす", action: onFinish)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
                    .padding(.bottom, 24)
                    .accessibilityHint("このおはなしを最後まで飛ばします")
            }
            .gameAnimation(.easeInOut(duration: 0.28), value: index)
        }
        // 絵と台詞は装飾ではなく「今読むべきもの」なので、まとめて 1 つの読み上げにする。
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(scene.title)。\(panel.line)")
        // ボタンの外側はどこを押しても飛ばせる（ボタン自身のタップはボタンが先に取る）。
        .contentShape(Rectangle())
        .onTapGesture(perform: onFinish)
        .task(id: index) {
            // 撮影・QA で 1 コマに止めているあいだは送らない（走るゲームと同じで、
            // 流したままだとシャッターを切る前に次のコマへ進む）。
            if let frozenPanel {
                index = min(max(0, frozenPanel), panels.count - 1)
                return
            }
            // 最後のコマまで来たら、その 1 枚を見せ切ってから閉じる。
            let nanos = UInt64(RunnerStory.panelDuration * 1_000_000_000)
            guard (try? await Task.sleep(nanoseconds: nanos)) != nil else { return }
            if index + 1 < panels.count { index += 1 } else { onFinish() }
        }
    }

    /// 撮影・QA で 1 コマに止める（`-simulateRunner story-intro:3`）。製品では渡らない。
    func frozenStoryPanel(_ index: Int?) -> RunnerStoryView {
        var copy = self
        copy.frozenPanel = index
        return copy
    }

    /// 何コマ目かの点。VoiceOver には読ませない（台詞のほうを読む）。
    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(panels.indices, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(i == index ? 0.9 : 0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}
