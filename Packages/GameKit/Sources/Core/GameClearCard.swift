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
    private let record: RecordResult?
    private let onClose: (() -> Void)?
    private let primaryAction: PrimaryAction?

    /// 「盤を見る」の上に置く、次へ進む動線（ねこさがしのステージの「次のステージへ」・#3048）。無ければ出さない。
    public struct PrimaryAction {
        let title: String
        let hint: String
        let action: () -> Void

        public init(title: String, hint: String, action: @escaping () -> Void) {
            self.title = title
            self.hint = hint
            self.action = action
        }
    }

    /// - Parameter record: 自己ベストの行に使う記録（15パズル・つなぎ。無ければ行を出さない・#3059）。
    public init(title: String? = nil, details: [String] = [], record: RecordResult? = nil,
                primaryAction: PrimaryAction? = nil, onClose: (() -> Void)? = nil) {
        self.title = title ?? tr("クリア！")
        self.details = details
        self.record = record
        self.primaryAction = primaryAction
        self.onClose = onClose
    }

    /// VoiceOver が 1 回で読む文。見出しの「！」は読み上げでは落とす。
    public static func accessibilityLabel(title: String, details: [String]) -> String {
        ([title.replacingOccurrences(of: "！", with: "").replacingOccurrences(of: "!", with: "")] + details).joined(separator: tr("。"))  // i18n-keep: 見出しから「！」「!」を外すだけ
    }

    public var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                Image(systemName: "trophy.fill")
                    .scaledFont(40, maxScale: 1.2)
                    .foregroundStyle(Theme.yellowText)
                Text(title)
                    .themeBody(24, weight: .bold, maxScale: 1.5)
                    .foregroundStyle(Theme.tealText)
                ForEach(details, id: \.self) { line in
                    Text(line)
                        .themeBody(15, weight: .semibold, maxScale: 1.5)
                        .foregroundStyle(Theme.ink)
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityLabel(title: title, details: details))
            // 共有ボタンを持つので、読み上げの塊の外に置く（`BoardGameResultCard` と同じ）。
            if record != nil { RecordLabel(record) }
            if let primaryAction {
                Button(action: primaryAction.action) {
                    Text(primaryAction.title)
                        .themeBody(15, weight: .bold, maxScale: 1.5)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Theme.Fill.coral))
                }
                .accessibilityHint(primaryAction.hint)
            }
            if let onClose {
                Button(action: onClose) {
                    Text(tr("盤を見る"))
                        .themeBody(15, weight: .bold, maxScale: 1.5)
                        .foregroundStyle(primaryAction == nil ? Theme.onAccent : Theme.coralText)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        // 次へ進む動線があるときは、そちらを塗りにして「盤を見る」は枠だけにする（結果カードの副ボタンと同じ形）。
                        .background {
                            if primaryAction == nil {
                                Capsule().fill(Theme.Fill.coral)
                            } else {
                                Capsule().stroke(Theme.coralText, lineWidth: 2)
                            }
                        }
                }
                .accessibilityHint(tr("クリアの表示を閉じて盤面を見返します"))
            }
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .playStreakCaption()
        .padding(16)
        .resultCardScrollsWhenTall()
        .announcesResultAppearance(Self.accessibilityLabel(title: title, details: details))
    }
}

/// `View.gameClearCard` の本体。「盤を見る」で閉じたかどうかをここが持つので、呼び出し側は
/// `isPresented`（クリアしたか）だけを渡せばよい。`isPresented` が偽に戻ったら（新しい局）閉じた記憶を捨てる。
private struct GameClearCardModifier: ViewModifier {
    let isPresented: Bool
    let title: String?
    let details: [String]
    let record: RecordResult?
    let primaryAction: GameClearCard.PrimaryAction?
    @State private var dismissed = false

    func body(content: Content) -> some View {
        content.overlay {
            // `.gameAnimation` は残り続ける親（この `ZStack`）に置く（`boardGameResultCard` と同じ・#195）。
            ZStack {
                if isPresented && !dismissed {
                    ZStack {
                        Color.black.opacity(0.45)
                        GameClearCard(title: title, details: details, record: record, primaryAction: primaryAction) { dismissed = true }
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
    /// `record` は自己ベストの行、`primaryAction` は「盤を見る」の上に置く動線（15パズル・つなぎの「もう一回」・#3059）。
    func gameClearCard(isPresented: Bool, title: String? = nil, details: [String] = [], record: RecordResult? = nil,
                       primaryAction: GameClearCard.PrimaryAction? = nil) -> some View {
        modifier(GameClearCardModifier(isPresented: isPresented, title: title, details: details,
                                       record: record, primaryAction: primaryAction))
    }
}
