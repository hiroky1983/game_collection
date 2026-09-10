import SwiftUI
import Core

/// 配り直すときにルールを選ぶ開始シート（#498）。
///
/// **ここで選んだ値は配札と同時に焼き込まれ、その局の途中では変えられない**
/// （`docs/ai-devops.md`「1局=1RuleSet」原則）。ソリティアは起動したらすぐ遊べるのが
/// 身上なので、**初回の配札ではこのシートを出さない**（既定の1枚めくりで即座に配る）。
/// 出るのはツールバーの「新規ゲーム」を押したときだけ。
///
/// #498 以前にそこで出していた確認ダイアログ（「新しい配札にしますか？」）は、
/// **このシートが兼ねる**。途中の盤面があるときは同じ警告をここに出し、
/// 確定のボタンを破棄扱いにする。ダイアログを残したままシートを重ねると、
/// キャンセルできる確認が 2 枚続くことになる。
public struct SolitaireSetupSheet: View {
    @Binding var draft: SolitaireRuleSet
    /// 途中の盤面を捨てて配り直すことになるか。文言だけを切り替える。
    let discardsProgress: Bool
    let onStart: () -> Void
    @Environment(\.dismiss) private var dismiss

    public init(
        draft: Binding<SolitaireRuleSet>,
        discardsProgress: Bool,
        onStart: @escaping () -> Void
    ) {
        self._draft = draft
        self.discardsProgress = discardsProgress
        self.onStart = onStart
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("山札のめくり方", selection: $draft.drawMode) {
                        ForEach(SolitaireDrawMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("山札のめくり方")
                } footer: {
                    Text(Self.footer(for: draft.drawMode))
                }

                if discardsProgress {
                    Section {
                        Label("途中で終了すると今の盤面が失われ、この配札は「クリアできなかった」として記録されます。",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.coral)
                    }
                }
            }
            .navigationTitle("新しい配札")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // 途中の盤面を捨てることになる場合だけ破棄扱いにする（旧・確認ダイアログの
                    // 「終了して新規ゲーム」と同じ重み）。
                    Button(role: discardsProgress ? .destructive : nil) {
                        onStart()
                    } label: {
                        Text(discardsProgress ? "終了して配る" : "配る")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                }
            }
        }
    }

    /// めくり方の説明。**記録の扱いまで書く**（自己ベストが別枠になり、順位表には
    /// 標準の1枚めくりしか載らないことを、選ぶ前に知らせる）。
    static func footer(for mode: SolitaireDrawMode) -> String {
        switch mode {
        case .one:
            return "山札を1枚ずつめくります。いちばん標準的なクロンダイクで、"
                + "Game Center の「ソリティア 最短タイム」に載るのはこちらだけです。"
        case .three:
            return "山札を3枚ずつめくり、使えるのはいちばん上の1枚だけです。"
                + "同じ配札でも使える札が減るぶん歯ごたえがあります。"
                + "自己ベストは1枚めくりとは別に記録され、Game Center の順位表には送りません。"
        }
    }
}
