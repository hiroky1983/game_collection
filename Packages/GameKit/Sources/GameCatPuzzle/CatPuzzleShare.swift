import SwiftUI
import Core

/// ステージのクリアのカードから共有する「今日の pt」（#3237）。デイリーランキングの開催中のステージだけ。
///
/// 文は「ねこさがし 今日 18pt（5 面クリア）」。画像は**答えが分からない**ように、盤は部屋の色の間取りだけを
/// ぼかして描き、猫・× は一切描かない（置いた印を渡さない）。商標・賭けの語は使わない。
enum CatPuzzleShare {
    /// 共有する短い文。
    static func message(points: Int, clears: Int) -> String {
        tr("ねこさがし 今日 %1$lldpt（%2$lld 面クリア）", points, clears)
    }

    /// 共有の中身。期間外・自由に遊ぶ（ステージでない）・クリアしていないときは nil（共有ボタンを出さない）。
    @MainActor
    static func content(for model: CatPuzzleModel) -> ClearShare? {
        guard model.stage != nil, model.isEventActive, model.lastEventPoints != nil else { return nil }
        let points = model.eventTotal
        let clears = model.todayEventClears
        let puzzle = model.puzzle
        let message = message(points: points, clears: clears)
        return ClearShare(message: message) { image(puzzle: puzzle, points: points, clears: clears) }
    }

    @MainActor
    static func image(puzzle: CatPuzzle, points: Int, clears: Int) -> CGImage? {
        let renderer = ImageRenderer(content: Card(puzzle: puzzle, points: points, clears: clears))
        renderer.scale = 2
        return renderer.cgImage
    }

    /// 画像の寸法（pt）。
    static let cardSize = CGSize(width: 360, height: 360)

    struct Card: View {
        let puzzle: CatPuzzle
        let points: Int
        let clears: Int

        var body: some View {
            VStack(spacing: 14) {
                Text(tr("あそびば ねこさがし"))
                    .font(.system(size: 20, weight: .bold, design: .rounded)) // fixed-size: 画像に焼く共有カード（端末の文字サイズ設定に従わない固定寸法）
                    .foregroundStyle(Theme.tealText)
                // 答えの分からない間取りだけ。印（猫・×）は渡さないので盤に何も載らない。
                CatPuzzleBoardCanvas(
                    puzzle: puzzle, marks: Array(repeating: .empty, count: puzzle.cellCount),
                    showsRoomLabels: false, cellSide: 150 / CGFloat(puzzle.side)
                )
                .blur(radius: 5)
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall))
                .overlay(alignment: .bottomTrailing) {
                    CatPuzzleArt.image(.sitFront).frame(width: 72, height: 72).offset(x: 28, y: 22)
                }
                Text(tr("今日 %lldpt", points))
                    .font(.system(size: 40, weight: .heavy, design: .rounded)) // fixed-size: 画像に焼く共有カード（端末の文字サイズ設定に従わない固定寸法）
                    .foregroundStyle(Theme.ink)
                Text(tr("%lld 面クリア", clears))
                    .font(.system(size: 20, weight: .semibold, design: .rounded)) // fixed-size: 画像に焼く共有カード（端末の文字サイズ設定に従わない固定寸法）
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: CatPuzzleShare.cardSize.width, height: CatPuzzleShare.cardSize.height)
            .background(Theme.surface)
            .environment(\.colorScheme, .light)
        }
    }
}
