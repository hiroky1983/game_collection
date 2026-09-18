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
    /// VoiceOver が動いているか。**動いているあいだは自動でコマを送らない**（#1092・CodeRabbit 指摘）。
    ///
    /// 1.2 秒の自動送りは目で読む前提の尺で、読み上げが終わる前に次のコマへ進んでしまう。
    /// 最後のコマではそのまま閉じるので、台詞を聞き終える手立てが無かった。環境値なので
    /// 途中で VoiceOver を入れ切りしても追従する。
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private var panels: [RunnerStoryPanel] { scene.panels }
    private var panel: RunnerStoryPanel { panels[min(index, panels.count - 1)] }
    /// 自分でコマを送る（VoiceOver 中）。最後のコマなら閉じる。
    private var isLastPanel: Bool { index + 1 >= panels.count }

    private func advance() {
        if isLastPanel { onFinish() } else { index += 1 }
    }

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
                HStack(spacing: 12) {
                    // VoiceOver 中は自動で送らないので、自分で進める操作を出す。
                    if voiceOverEnabled {
                        capsuleButton(isLastPanel ? "おわり" : "つぎへ", action: advance)
                            .accessibilityHint(isLastPanel ? "おはなしを閉じます" : "次のコマへ進みます")
                    }
                    capsuleButton("とばす", action: onFinish)
                        .accessibilityHint("このおはなしを最後まで飛ばします")
                }
                // 画面の最下部はバナー（`BannerSlot`）の帯なので、その上に置く。
                // 幕がタップを受け切るので広告が誤って押されることはないが、
                // 押すボタンを広告の真上に重ねない。
                .padding(.bottom, 84)
            }
            .gameAnimation(.easeInOut(duration: 0.28), value: index)
        }
        // 絵と台詞は装飾ではなく「今読むべきもの」なので、まとめて 1 つの読み上げにする。
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(scene.title)。\(panel.line)")
        // 画面を覆っているあいだ、VoiceOver が背後のコース・ヘッダーへ回り込まないようにする
        // （シートと同じ扱い。回り込めると「ダブルタップでジャンプ」など効かない操作に触れる）。
        .accessibilityAddTraits(.isModal)
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
            // VoiceOver 中は自動で送らない。1.2 秒は目で読む前提の尺で、読み上げの途中で
            // 次のコマへ進む（最後のコマでは閉じてしまう）。送るのは「つぎへ」だけにする。
            guard !voiceOverEnabled else { return }
            // 最後のコマまで来たら、その 1 枚を見せ切ってから閉じる。
            let nanos = UInt64(RunnerStory.panelDuration * 1_000_000_000)
            guard (try? await Task.sleep(nanoseconds: nanos)) != nil else { return }
            advance()
        }
    }

    /// 下端に並べる丸いボタンの見た目（「つぎへ」「とばす」で揃える）。
    private func capsuleButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.white.opacity(0.18)))
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
