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
                    // コマの絵をパッと差し替えず、フェードで繋ぐ（#1170）。`Image` は中身の
                    // 差し替え自体はアニメーション対象にならないため、`.animation` だけでは
                    // 前後のコマが一瞬で入れ替わる。`.contentTransition` が中身の差し替えそのものを
                    // 補間対象にし、`gameAnimation` で張った `index` のアニメーションに乗る。
                    //
                    // `.contentTransition` は SwiftUI の仕様上「有効なアニメーションが張られている
                    // ときだけ」補間する（アニメーション自体は作らない）。`gameAnimation` は Reduce
                    // Motion オンで `.animation(nil, value:)` に落ちるので、追加のガード無しに
                    // クロスフェードも一緒に止まる——専用の分岐は要らない。
                    .contentTransition(.opacity)
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
                    // 台詞も絵と同じくフェードで繋ぐ（#1170）。
                    .contentTransition(.opacity)
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
                // 画面の最下部はバナー（`BannerSlot`）の帯。幕のあいだバナー自体は出さない
                // （`RunnerView.showsBanner`・#1147）が、枠の高さは空の帯として残るので、
                // ボタンはその上に置いたままにする（幕が明けた前後でボタンの位置が動かない）。
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

// MARK: - おはなしの見返し（#1092）

/// 開始シートに置く「見たおはなしをもう一度見る」の並び。
///
/// 受け入れ条件「v1.1.6 に上げた時点で 6・12・18 面をクリア済みの人は締めを見ていない。
/// **ワールドマップから、到達済みの世界の締めを見返せる**」への答え。見返せるのは
/// もう見た世界だけで（`RunnerStory.replayableScenes`）、まだの世界は並ばない
/// ——これから見る話を目次で先に見せない。
struct RunnerStoryReplayList: View {
    let playLog: PlayLog?
    let onSelect: (RunnerStoryScene) -> Void

    var body: some View {
        let scenes = RunnerStory.replayableScenes(playLog: playLog)
        VStack(spacing: 8) {
            ForEach(scenes, id: \.self) { scene in
                Button { onSelect(scene) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.inkSub)
                        Text(scene.title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 0)
                    }
                    // 上下の余白と合わせて 44pt（iOS の最小のタップ寸）。
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                            .fill(Theme.surface)
                    )
                }
                .buttonStyle(.pop)
                .accessibilityLabel("\(scene.title)をもう一度見る")
            }
        }
    }
}
