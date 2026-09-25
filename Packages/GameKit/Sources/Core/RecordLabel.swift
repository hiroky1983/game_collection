import SwiftUI

/// リザルトに 1 行だけ添える自己ベストの表示（#115）。
///
/// **非モーダル・1 行**。既存のリザルト表示（「もう一度」ボタンや結果カード）の邪魔をしないよう、
/// 見出しではなく添え書きの大きさに留める。記録がまだ無ければ何も描画しない。
///
/// 自己ベストを更新した回だけ、行の末尾に共有ボタンを添える（#1043）。ボタンを出すかは
/// ハブが配る `RecordShareContext` の有無で決まり、テスト・プレビュー（配られない）では出ない。
public struct RecordLabel: View {
    private let result: RecordResult?
    private let accent: Color
    private let textColor: Color
    @Environment(\.recordShare) private var share

    /// - Parameters:
    ///   - result: `GameServices.gameDidFinish` の戻り値。nil なら何も出さない。
    ///   - accent: 「自己ベスト更新！」バッジの差し色。`Theme.Fill` 側を渡す（#220）。
    ///   - textColor: 記録本文の色。暗いオーバーレイの上に直接置く画面（2048 など）は
    ///     `.white` を渡す。既定は明るい背景向けの補助文字色（オセロのように暗幕の上でも
    ///     明るいカードに乗る画面はこちらでよい）。
    public init(_ result: RecordResult?, accent: Color = Theme.Fill.coral, textColor: Color = Theme.inkSub) {
        self.result = result
        self.accent = accent
        self.textColor = textColor
    }

    public var body: some View {
        if let result, let line = RecordFormat.resultLine(result.record) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    if result.update.isNewBest {
                        RecordBadge("自己ベスト更新！", accent: accent)
                    }
                    Text(line)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(textColor)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(result.update.isNewBest ? "自己ベスト更新。\(line)" : line)

                // 共有ボタンは読み上げの結合の**外**に置く（中に入れると 1 つの要素に畳まれて押せなくなる）。
                if result.update.isNewBest, let share,
                   let message = RecordFormat.shareMessage(title: share.gameTitle, record: result.record) {
                    RecordShareButton(message: message, context: share, accent: accent)
                }
            }
        }
    }
}

/// 自己ベスト更新のリザルトから記録を共有するための、ゲーム画面単位の情報（#1043）。
///
/// `RecordLabel` は 20 本のゲームから `RecordLabel(model.recordResult)` の形で呼ばれていて、
/// どのゲームか・解析へどう伝えるかを知らない。呼び出し側を 1 本ずつ直す代わりに、
/// ゲーム画面を作るハブ（`HubView` の `navigationDestination`）が環境値で 1 か所から配る。
public struct RecordShareContext: Sendable {
    /// ハブに出しているゲームの表示名（`GameModule.title`）。共有文言に入る。
    public let gameTitle: String
    /// 共有シートに添える URL（App Store の商品ページ）。
    public let url: URL
    /// 共有ボタンを押したときに呼ぶ。ハブが `GameServices.gameDidTapShare` へつなぐ（`share_tap`）。
    public let didTap: @MainActor @Sendable () -> Void

    public init(gameTitle: String, url: URL, didTap: @escaping @MainActor @Sendable () -> Void) {
        self.gameTitle = gameTitle
        self.url = url
        self.didTap = didTap
    }
}

private struct RecordShareContextKey: EnvironmentKey {
    /// 配られていない画面（テスト・プレビュー・撮影用の単独表示）では共有ボタンを出さない。
    static let defaultValue: RecordShareContext? = nil
}

public extension EnvironmentValues {
    /// リザルトの共有ボタンに使う情報（#1043）。ハブがゲーム画面ごとに配る。
    var recordShare: RecordShareContext? {
        get { self[RecordShareContextKey.self] }
        set { self[RecordShareContextKey.self] = newValue }
    }
}

/// `RecordLabel` の行末に添える共有ボタン（#1043）。
///
/// - 記録の行は多くのゲームで「決着で行を増やさない」1 行の帯に同居している（#139・#148）。
///   そのためボタンは記号だけにし、**見た目は「自己ベスト更新！」バッジと同じ高さ**に収める。
/// - 当たり判定の 44pt の枠はボタンの中（label）に入れ、帯の高さへの影響はボタンの**外**の負の余白で
///   打ち消す（検討ナビの ◀ ▶ と同じ組み方・#713。中で詰めると詰めた外側が反応しない）。
/// - 押せる物に見えるよう差し色で塗る（バッジは塗らない枠線なので見分けが付く・会長 QA 2026-09-14）。
struct RecordShareButton: View {
    let message: String
    let context: RecordShareContext
    let accent: Color

    /// 見た目の円の直径。「自己ベスト更新！」バッジ（12pt の文字 + 上下 4pt・約 22〜23pt）を超えない高さにする
    /// （24pt にすると行が 1〜2pt 伸びた。PR #1057 の検証）。
    static let symbolSide: CGFloat = 22
    /// 当たり判定の枠。
    static let tapTarget: CGFloat = 44

    var body: some View {
        ShareLink(item: context.url, subject: Text("あそびば"), message: Text(verbatim: message)) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: Self.symbolSide, height: Self.symbolSide)
                .background(Circle().fill(accent))
                .frame(width: Self.tapTarget, height: Self.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // ShareLink は押したことを知らせる口を持たないので、同時に効くタップで拾う（共有シートの表示は妨げない）。
        .simultaneousGesture(TapGesture().onEnded { context.didTap() })
        .padding(.vertical, -(Self.tapTarget - Self.symbolSide) / 2)
        .padding(.horizontal, -(Self.tapTarget - Self.symbolSide) / 4)
        .accessibilityLabel("記録をシェア")
    }
}

/// 「自己ベスト更新！」「ベストタイム更新！」の**バッジ**。
///
/// 以前は差し色で塗りつぶしたカプセルだったが、このアプリのボタン（`actionButton` 等）も差し色の
/// 塗りつぶしなので、リザルトで「次のステージへ」の隣に並ぶと押せるものに見えた
/// （会長 QA 2026-09-14「ボタンと一緒だけど押せる？」）。塗らずに**細い枠線と薄い下地、星印**で
/// 「印」として描き、ボタンと見分けが付くようにする。明るいカードでも暗いオーバーレイでも
/// 差し色の文字で読める。
public struct RecordBadge: View {
    private let text: String
    private let accent: Color

    public init(_ text: String, accent: Color = Theme.Fill.coral) {
        self.text = text
        self.accent = accent
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(accent.opacity(0.14)))
        .overlay(Capsule().strokeBorder(accent, lineWidth: 1.2))
        // 押せる物ではないことを読み上げにも反映する（ボタンの特性を付けない）
        .accessibilityElement(children: .combine)
    }
}
