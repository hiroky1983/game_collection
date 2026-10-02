import SwiftUI

/// ソリティア系・ナンプレ・麻雀ソリティアのクリアを盤に重ねて大きく示すカード（#1755）。
///
/// 見た目は `BoardGameResultCard`（オセロ手本の結果カード）と揃え、**5 本で完全に同じ**にする。
/// 載せるのは見出しと各ゲームが持つ記録の行（タイム・手数など）だけ。終局後のボタン（もう一回など）は
/// 盤の下の既存部品（`GameControlArea` / `GameReplayBar`）のままで、ここには置かない。
/// `onClose` があれば「盤を見る」で閉じて盤面を見返せる（麻雀ソリティアは盤が空なので閉じる口を持たない）。
public struct GameClearCard: View {
    private let title: String
    private let details: [String]
    private let onClose: (() -> Void)?

    public init(title: String = "クリア！", details: [String] = [], onClose: (() -> Void)? = nil) {
        self.title = title
        self.details = details
        self.onClose = onClose
    }

    /// VoiceOver が 1 回で読む文。見出しの「！」は読み上げでは落とす。
    public static func accessibilityLabel(title: String, details: [String]) -> String {
        ([title.replacingOccurrences(of: "！", with: "")] + details).joined(separator: "。")
    }

    public var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.yellow)
                Text(title)
                    .themeBody(24, weight: .bold, maxScale: 1.5)
                    .foregroundStyle(Theme.teal)
                ForEach(details, id: \.self) { line in
                    Text(line)
                        .themeBody(15, weight: .semibold, maxScale: 1.5)
                        .foregroundStyle(Theme.ink)
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityLabel(title: title, details: details))
            if let onClose {
                Button(action: onClose) {
                    Text("盤を見る")
                        .themeBody(15, weight: .bold, maxScale: 1.5)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Theme.Fill.coral))
                }
                .accessibilityHint("クリアの表示を閉じて盤面を見返します")
            }
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(16)
    }
}

/// `View.gameClearCard` の本体。「盤を見る」で閉じたかどうかをここが持つので、呼び出し側は
/// `isPresented`（クリアしたか）だけを渡せばよい。`isPresented` が偽に戻ったら（新しい局）閉じた記憶を捨てる。
private struct GameClearCardModifier: ViewModifier {
    let isPresented: Bool
    let title: String
    let details: [String]
    @State private var dismissed = false

    func body(content: Content) -> some View {
        content.overlay {
            // `.gameAnimation` は残り続ける親（この `ZStack`）に置く（`boardGameResultCard` と同じ・#195）。
            ZStack {
                if isPresented && !dismissed {
                    ZStack {
                        Color.black.opacity(0.45)
                        GameClearCard(title: title, details: details) { dismissed = true }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
                    .transition(.opacity)
                }
            }
            .gameAnimation(.easeOut(duration: 0.25), value: isPresented && !dismissed)
        }
        .onChange(of: isPresented) { _, now in
            if !now { dismissed = false }
        }
    }
}

public extension View {
    /// 盤の上にクリアカードを重ねる（#1755）。`isPresented` が真のあいだ出し、「盤を見る」で閉じられる。
    func gameClearCard(isPresented: Bool, title: String = "クリア！", details: [String] = []) -> some View {
        modifier(GameClearCardModifier(isPresented: isPresented, title: title, details: details))
    }
}
