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

        var title: String {
            switch self {
            case .win: return "あなたの勝ち！"
            case .loss: return "あなたの負け"
            case .draw: return "引き分け"
            }
        }
    }

    private let verdict: Verdict
    private let reason: String
    private let decisiveMove: String?
    private let details: [String]
    private let record: RecordResult?
    private let onClose: () -> Void

    /// - Parameters:
    ///   - reason: 終局の理由（「詰み」「投了」「五連」など）。
    ///   - decisiveMove: 決め手の手（将棋・チェス。例 "▲７六歩"）。無ければ nil。
    ///   - details: 補足の行（囲碁の目数の内訳など）。
    ///   - record: 自己ベストの行に使う記録。
    ///   - onClose: 「盤を見る」。
    public init(verdict: Verdict, reason: String, decisiveMove: String? = nil, details: [String] = [],
                record: RecordResult?, onClose: @escaping () -> Void) {
        self.verdict = verdict
        self.reason = reason
        self.decisiveMove = decisiveMove
        self.details = details
        self.record = record
        self.onClose = onClose
    }

    /// VoiceOver が 1 回で読む文。記号・見出し・理由・決め手・補足をまとめる。
    public static func accessibilityLabel(verdict: Verdict, reason: String, decisiveMove: String?,
                                          details: [String]) -> String {
        var parts = [verdict.title.replacingOccurrences(of: "！", with: ""), reason]
        if let decisiveMove { parts.append("決め手 \(decisiveMove)") }
        parts.append(contentsOf: details)
        return parts.joined(separator: "。")
    }

    private var accent: Color {
        switch verdict {
        case .win: return Theme.teal
        case .loss: return Theme.coral
        case .draw: return Theme.inkSub
        }
    }

    private var symbol: (name: String, color: Color) {
        switch verdict {
        case .win: return ("trophy.fill", Theme.yellow)
        case .loss: return ("flag.fill", Theme.coral)
        case .draw: return ("equal.circle.fill", Theme.inkSub)
        }
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 12) {
                VStack(spacing: 10) {
                    Image(systemName: symbol.name)
                        .font(.system(size: 40))
                        .foregroundStyle(symbol.color)
                    Text(verdict.title)
                        .themeBody(24, weight: .bold, maxScale: 1.5)
                        .foregroundStyle(accent)
                    Text(reason)
                        .themeBody(17, weight: .semibold, maxScale: 1.5)
                        .foregroundStyle(Theme.ink)
                    if let decisiveMove {
                        Text("決め手 \(decisiveMove)")
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
                .accessibilityLabel(Self.accessibilityLabel(verdict: verdict, reason: reason,
                                                            decisiveMove: decisiveMove, details: details))
                // 共有ボタンを持つので、読み上げの塊の外に置く（オセロ #1716 と同じ）。
                RecordLabel(record)
                Button(action: onClose) {
                    Text("盤を見る")
                        .themeBody(15, weight: .bold, maxScale: 1.5)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Theme.Fill.coral))
                }
                .accessibilityHint("結果を閉じて盤面を見返します")
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
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
