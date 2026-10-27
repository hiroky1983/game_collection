import SwiftUI

/// 盤ゲーム（将棋・チェス・囲碁・五目並べ）の終局を盤に重ねて大きく示す結果カード（#1753）。
///
/// 見た目はオセロの結果オーバーレイ（暗幕＋素材のカード）を手本にし、**4 本で完全に同じ**にする。
/// 載せるのは勝敗・理由・（あれば）決め手と補足行・自己ベスト。終局後のボタン（もう一回・設定を変える）は
/// 盤の下の既存部品（`GameReplayBar`）のままで、ここには置かない。
/// 「盤を見る」で閉じて盤面を見返せる。閉じたかどうかは呼び出し側の `@State` が持つ。
public struct BoardGameResultCard: View {
    public enum Verdict: Equatable, Sendable {
        case win, loss, draw

        public var title: String {
            switch self {
            case .win: return tr("あなたの勝ち！")
            case .loss: return tr("あなたの負け")
            case .draw: return tr("引き分け")
            }
        }

        /// 帯（`GameStatusBar`）の終局ラベルに使う SF Symbol。引き分けだけ別の 1 つに揃える（#2484）。
        public var bandSymbol: String {
            self == .draw ? "equal.circle.fill" : "flag.checkered"
        }
    }

    private let verdict: Verdict
    private let headline: String?
    private let reason: String
    private let decisiveMove: String?
    private let details: [String]
    private let record: RecordResult?
    private let onClose: () -> Void
    private let secondaryAction: SecondaryAction?
    private let closeTitle: String
    private let closeHint: String

    /// 「盤を見る」の上に足す、ゲーム固有の動線（五目並べの「ここで止めていれば」など・#2851）。
    public struct SecondaryAction {
        let title: String
        let hint: String
        let action: () -> Void

        public init(title: String, hint: String, action: @escaping () -> Void) {
            self.title = title
            self.hint = hint
            self.action = action
        }
    }

    /// - Parameters:
    ///   - headline: 勝ちの見出しを差し替える特別な演出（将棋の達人への初勝利・#2991）。nil なら通常の見出し。
    ///   - reason: 終局の理由（「詰み」「投了」「五連」など）。
    ///   - decisiveMove: 決め手の手（将棋・チェス。例 "▲７六歩"）。無ければ nil。
    ///   - details: 補足の行（囲碁の目数の内訳など）。
    ///   - record: 自己ベストの行に使う記録。
    ///   - secondaryAction: ゲーム固有の動線。無ければ出さない。
    ///   - closeTitle: 閉じるボタンの文言。nil なら「盤を見る」（ねこさがしの「あきらめて正解を見る」・#2904）。
    ///   - closeHint: 閉じるボタンの VoiceOver のヒント。nil なら「結果を閉じて盤面を見返します」。
    ///   - onClose: 「盤を見る」。
    public init(verdict: Verdict, headline: String? = nil, reason: String, decisiveMove: String? = nil, details: [String] = [],
                record: RecordResult?, secondaryAction: SecondaryAction? = nil,
                closeTitle: String? = nil, closeHint: String? = nil, onClose: @escaping () -> Void) {
        self.secondaryAction = secondaryAction
        self.closeTitle = closeTitle ?? tr("盤を見る")
        self.closeHint = closeHint ?? tr("結果を閉じて盤面を見返します")
        self.verdict = verdict
        self.headline = headline
        self.reason = reason
        self.decisiveMove = decisiveMove
        self.details = details
        self.record = record
        self.onClose = onClose
    }

    /// VoiceOver が 1 回で読む文。記号・見出し・理由・決め手・補足をまとめる。
    public static func accessibilityLabel(verdict: Verdict, headline: String? = nil, reason: String,
                                          decisiveMove: String?, details: [String]) -> String {
        var parts = [(headline ?? verdict.title).replacingOccurrences(of: "！", with: "").replacingOccurrences(of: "!", with: ""), reason]  // i18n-keep: 見出しから「！」「!」を外すだけ（表示する文ではない）
        if let decisiveMove { parts.append(tr("決め手 %@", decisiveMove)) }
        parts.append(contentsOf: details)
        return parts.joined(separator: tr("。"))
    }

    private var accent: Color {
        switch verdict {
        case .win: return Theme.tealText
        case .loss: return Theme.coralText
        case .draw: return Theme.inkSubText
        }
    }

    private var symbol: (name: String, color: Color) {
        switch verdict {
        case .win: return ("trophy.fill", Theme.yellowText)
        case .loss: return ("flag.fill", Theme.coralText)
        case .draw: return ("equal.circle.fill", Theme.inkSubText)
        }
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 12) {
                VStack(spacing: 10) {
                    Image(systemName: symbol.name)
                        .scaledFont(40, maxScale: 1.2)
                        .foregroundStyle(symbol.color)
                    Text(headline ?? verdict.title)
                        .themeBody(headline == nil ? 24 : 30, weight: .bold, maxScale: 1.5)
                        .foregroundStyle(accent)
                    Text(reason)
                        .themeBody(17, weight: .semibold, maxScale: 1.5)
                        .foregroundStyle(Theme.ink)
                    if let decisiveMove {
                        Text(tr("決め手 %@", decisiveMove))
                            .themeBody(15, weight: .semibold, maxScale: 1.5)
                            .foregroundStyle(Theme.ink)
                    }
                    ForEach(details, id: \.self) { line in
                        Text(line)
                            .themeBody(15, weight: .semibold, maxScale: 1.5)
                            .foregroundStyle(Theme.ink)
                    }
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.accessibilityLabel(verdict: verdict, headline: headline, reason: reason,
                                                            decisiveMove: decisiveMove, details: details))
                // 共有ボタンを持つので、読み上げの塊の外に置く（オセロ #1716 と同じ）。
                RecordLabel(record)
                if let secondaryAction {
                    Button(action: secondaryAction.action) {
                        Text(secondaryAction.title)
                            .themeBody(15, weight: .bold, maxScale: 1.5)
                            .foregroundStyle(Theme.coralText)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 44)
                            .background(Capsule().stroke(Theme.coralText, lineWidth: 2))
                    }
                    .accessibilityHint(secondaryAction.hint)
                }
                Button(action: onClose) {
                    Text(closeTitle)
                        .themeBody(15, weight: .bold, maxScale: 1.5)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Theme.Fill.coral))
                }
                .accessibilityHint(closeHint)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .playStreakCaption()
            .padding(16)
            .resultCardScrollsWhenTall()
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .announcesResultAppearance(Self.accessibilityLabel(verdict: verdict, headline: headline, reason: reason,
                                                           decisiveMove: decisiveMove, details: details))
    }
}

public extension View {
    /// 盤の上に結果カードを重ねる（#1753）。`isPresented` が真のあいだ出し、フェードで入れ替える。
    ///
    /// `.gameAnimation` は**残り続ける親**（この `ZStack`）に置く。出入りする枝の中に置くと、
    /// 消える側と一緒に修飾子も消えて効かない（#195）。決着の瞬間に操作エリアが入れ替わって盤が
    /// 伸び縮みするのを止める外側の `.gameAnimation(.none, …)` とは別の View に付くので、打ち消し合わない（#199）。
    func boardGameResultCard<Card: View>(isPresented: Bool, @ViewBuilder card: () -> Card) -> some View {
        overlay {
            ZStack {
                if isPresented {
                    card().transition(.opacity)
                }
            }
            .gameAnimation(.easeOut(duration: 0.25), value: isPresented)
        }
    }
}

extension View {
    /// 結果カードが重ね先の盤より背が高いとき（最大の文字サイズ・SE）、上下が切り落とされないよう縦にスクロールさせる（#2858）。
    /// 収まるときは `ViewThatFits` が素のカードを選ぶので、標準の文字サイズでは見た目も挙動も変わらない。
    @ViewBuilder
    func resultCardScrollsWhenTall() -> some View {
        ViewThatFits(in: .vertical) {
            self
            ScrollView { self }.scrollBounceBehavior(.basedOnSize)
        }
    }
}
