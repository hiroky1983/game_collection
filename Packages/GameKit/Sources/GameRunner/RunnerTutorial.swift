import Core
import CoreGraphics
import Foundation
import SwiftUI

// MARK: - 初回プレイの操作ガイド（#988）

/// 走り出す前のスタート画面（#931）に重ねる操作ガイド。
///
/// これまでの導線（`?` の 3 行と盤の下の 1 行ヒント）はどちらも**読ませる**ものだったので、
/// 二段ジャンプと長押しの大ジャンプが文章に埋もれて伝わらなかった（会長指示 2026-09-15）。
/// ここでは覚えてほしい 3 つだけを、短い文と小さな絵で 1 画面に出す。
///
/// **対話型にはしない**（タップするまで進めない、はやらない）。1 画面読んで「はじめる」で
/// そのまま走り出す。文言・絵はこの型に集め、スタート画面と `?` の「くわしいルール」の
/// 両方から同じものを出す。
enum RunnerTutorial {
    /// 手順 1 つぶん。
    struct Step: Identifiable, Equatable, Sendable {
        /// 手順の番号（1 始まり）。VoiceOver で「1、タップでジャンプ」と読ませるのに使う。
        let id: Int
        /// 短い文（15 字程度）。
        let text: String
        /// 添える小さな絵（SF Symbols）。走者のドット絵はカードの頭に 1 枚置くので、
        /// 各手順にはドットを描き起こさず記号で補う。
        let symbol: String
        /// 1 行に収まらない手順の 2 行目（小さい文字）。
        ///
        /// iPhone SE では本文に 190pt ほどしか無く、13pt で 14 字までしか載らない。折り返しに
        /// 任せると「二段ジャンプ」が途中で割れるので、割る場所をこちらで決める。
        var note: String?
    }

    /// 覚えてほしい 3 つ。増やさない（1 画面に収まらなくなる）。
    static let steps: [Step] = [
        Step(id: 1, text: "タップでジャンプ", symbol: "hand.tap.fill"),
        Step(id: 2, text: "長く押すほど高く跳ぶ", symbol: "arrow.up.circle.fill"),
        Step(id: 3, text: "空中でもう一度タップ", symbol: "2.circle.fill", note: "二段ジャンプ"),
    ]

    /// 「見た」印のキー。保存先を増やさず `PlayLog` のミニガイドと同じ棚に置く。
    ///
    /// ゲーム ID（`"runner"`）とは**別のキー**にする——盤の下の 1 行ヒント（`HowToPlayHint`）が
    /// 画面を開いた時点で `"runner"` を消費してしまうため、共有すると初回でも出せない。
    static let seenKey = "runner.tutorial"

    /// 初回プレイのガイドを出すか。判定と「見せた」の記録は `PlayLog` が 1 回で済ませる
    /// （`HowToPlayHint` と同じ作法。2 回目以降は false）。
    ///
    /// - Parameter arguments: 起動引数。既定は実プロセスのもので、テストが撮影モードを固定するために差し替える。
    @MainActor
    static func shouldShow(
        playLog: PlayLog?,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        // 撮影モード（`-screenshotMode`）では出さない——App Store 用のスクリーンショットに
        // 写り込む。印も消費しないので、撮影のあとに実機で遊べば初回として出る。
        // QA・撮影用の画面（`-simulateRunner`）でも同じ（#1063）——`-screenshotMode` を付けずに
        // `showcase` 等を初回起動すると、見たい画にガイドのモーダルが被っていた。
        guard !arguments.contains("-screenshotMode"), !arguments.contains("-simulateRunner") else { return false }
        return playLog?.markGuideShown(for: seenKey) ?? false
    }

    // MARK: ドット絵

    /// 走者の「跳ぶ」コマ（`OjisanPixel.RiderFrame.jump`）。ガイドのために新しい絵は描き起こさない。
    static let riderJumpSprite = OjisanPixel.rider(.jump)

    /// 起動後 1 回だけビットマップ化する（`OjisanPixel.faceImages` と同じ作法）。
    private static let riderJumpImage: CGImage? = riderJumpSprite.cgImage(scale: 4)

    /// 高さ `height` pt で走者のドット絵を置く。幅はドット数の比率から決める（1 ドットが
    /// 縦横で違う大きさにならないように）。装飾なので VoiceOver は読まない。
    @ViewBuilder
    static func riderJump(height: CGFloat) -> some View {
        if let cg = riderJumpImage {
            let ratio = CGFloat(riderJumpSprite.width) / CGFloat(max(riderJumpSprite.height, 1))
            Image(decorative: cg, scale: 1)
                .resizable()
                .interpolation(.none)
                .frame(width: height * ratio, height: height)
        }
    }
}

// MARK: - 手順の 3 行

/// `RunnerTutorial.steps` を縦に並べる。スタート画面のカードと `?` の詳細ページで同じものを使う。
///
/// 1 行 = VoiceOver の 1 要素。番号を読み上げの頭に付けて、3 つの手順が順に読まれるようにする。
struct RunnerTutorialSteps: View {
    /// 文字の大きさ。狭いスタート画面（iPhone SE で本文の幅は 220pt ほど）は 13、
    /// シートの詳細ページは 15。
    var fontSize: CGFloat = 13

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(RunnerTutorial.steps) { step in
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: step.symbol)
                        .font(.system(size: fontSize + 7, weight: .heavy))
                        .foregroundStyle(Theme.coral)
                        .frame(width: fontSize + 11)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.text)
                            .font(.system(size: fontSize, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        if let note = step.note {
                            Text(note)
                                .font(.system(size: fontSize - 2, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.coral)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(step.id)、\(step.text)\(step.note.map { "、\($0)" } ?? "")")
            }
        }
    }
}

// MARK: - `?` の「くわしいルール」

/// `?` シートの「くわしいルール」から開く操作ガイド（#988 の「いつでも開き直せる」）。
///
/// 中身はスタート画面のカードと同じ 3 つ。初回に読み飛ばした人が戻ってこられる場所なので、
/// 文字と絵はこちらのほうを大きくする。
struct RunnerTutorialPage: View {
    var body: some View {
        RuleListSheet(rules: []) {
            RunnerTutorial.riderJump(height: 74)
            RuleFigureCard(title: "そうさのしかた") {
                RunnerTutorialSteps(fontSize: 15)
            }
        }
    }
}

// MARK: - 初回の操作ガイド（#988 → #1027 でモーダルへ）

/// 初回プレイだけ出す操作ガイドのモーダル。
///
/// #988 ではコースの上のカードで出していたが、カードの「はじめる」がステージ制で走り出す
/// 作りだったため、**初回だけモードを選べない**（右上からエンドレスを選んでも、ガードの
/// 「はじめる」がステージ制で上書きする）という穴があった（会長指摘 2026-09-16）。
/// モーダルにして「読む」だけに徹し、閉じたら開始シートへ送る。
///
/// 中身は「？」から開くページ（`RunnerTutorialPage`）と同じものを使う——同じ内容を 2 通りの
/// 見た目で持たない（基盤規約「同じ役割の UI は同じ見た目に」）。
struct RunnerTutorialSheet: View {
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RunnerTutorialPage()
                Button(action: onClose) {
                    Text("はじめる").themeBody(18).frame(maxWidth: .infinity)
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
                .padding(Theme.pad)
            }
            .popBackground()
        }
        .presentationDetents([.large])
    }
}
