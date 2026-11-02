import Core
import SwiftUI

/// 初めて鍵の面（10 面ごと・#3235）に来たときに 1 回だけ出す短い説明。図は遊び方の図と同じ部品（`CatPuzzleHowToFigures.Board`）。
struct CatPuzzleKeyIntro: View {
    /// 説明を見たかの保存キー（端末に 1 つ。見たら二度と出さない）。
    static let seenKey = "catPuzzleKeyIntroSeen"
    /// 図で鍵を持たせる部屋（`CatPuzzleHowToFigures.sample` で `tapCell` の猫がいる部屋）。
    static let figureKeyRoom = CatPuzzleHowToFigures.sample.rooms[CatPuzzleHowToFigures.tapCell]

    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Label(tr("鍵を持った猫の面"), systemImage: "key.fill")
                .scaledFont(20, weight: .heavy, design: .rounded)
                .foregroundStyle(Theme.ink)
            RuleFrames(count: 2, spacing: 10) { index in
                VStack(spacing: 4) {
                    CatPuzzleHowToFigures.Board(
                        cats: index == 0 ? [] : [CatPuzzleHowToFigures.tapCell],
                        cellSide: 22, showsRoomLabels: true,
                        keyRoom: Self.figureKeyRoom, keyLocked: index == 0
                    )
                    RuleFigureLabel(index == 0 ? tr("鍵が閉じている") : tr("鍵が開いた"),
                                    color: index == 0 ? Theme.coralText : Theme.tealText)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("鍵の札がついた部屋に、鍵を持った猫がいます。"))
                Text(tr("その猫を見つけるまで、ほかの部屋には × も猫も置けません。"))
                Text(tr("鍵の部屋は、ほかのマスを調べなくても、考えれば猫の場所が決まります。"))
            }
            .scaledFont(15, weight: .semibold, design: .rounded)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Text(tr("わかった"))
                    .scaledFont(17, weight: .heavy, design: .rounded)
            }
            .buttonStyle(.game(.primary, shape: .block))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.large])
    }
}
