import Core
import SwiftUI

/// 図入りの遊び方（#2044 の先駆け・会長決定 2026-10-12）の図。
///
/// 文言は `HowToPlayGuide.ojisanPuzzleBackpain` / `.ojisanPuzzlePuzzle`（Core）にあり、ここは項目ごとの
/// 図だけを持つ。荷物は本番の `OjisanPuzzleView.luggage(_:side:)`、おじさんは `OjisanPuzzleArt.image(_:)`
/// で描き、絵を二重に持たない。図は固定寸法で、いちばん狭い iPhone SE のカード（幅 315pt 前後）に
/// 収まる大きさで組む。
///
/// 「？」は遊んでいるモードに合わせる（会長指示 2026-10-12）。パズルモードには腰痛ゲージ・入院・
/// クリアライン・せり上がりを出さない。
@MainActor
enum OjisanPuzzleHowToFigures {
    /// `HowToPlayGuide.ojisanPuzzleBackpain.items` と同じ順。
    static let backpain: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(GoalFigure(mode: .backpain)) },
        { AnyView(ControlsFigure()) },
        { AnyView(ChainFigure()) },
        { AnyView(WeightFigure()) },
        { AnyView(GaugeFigure()) },
        { AnyView(EndFigure(mode: .backpain)) },
    ]

    /// `HowToPlayGuide.ojisanPuzzlePuzzle.items` と同じ順。
    static let puzzle: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(GoalFigure(mode: .puzzle)) },
        { AnyView(ControlsFigure()) },
        { AnyView(ChainFigure()) },
        { AnyView(WeightFigure()) },
        { AnyView(EndFigure(mode: .puzzle)) },
    ]

    /// 図の中の小さな文字。図は固定寸法なので、拡大はわずかに留める。
    fileprivate static func label(_ text: String, size: CGFloat = 10, color: Color = Theme.ink) -> some View {
        Text(text)
            .scaledFont(size, weight: .black, design: .rounded, maxScale: 1.15)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// コマ図の下などに出す説明。
    fileprivate static func caption(_ text: String) -> some View {
        Text(text)
            .themeCaption(11, weight: .bold, maxScale: 1.3)
            .foregroundStyle(Theme.inkSubText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 見出し（アイコン＋語）。
    fileprivate static func heading(_ title: String, icons: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(icons, id: \.self) { icon in
                Image(systemName: icon)
                    .scaledFont(13, weight: .bold, maxScale: 1.15)
                    .foregroundStyle(Theme.coralText)
            }
            Text(title)
                .scaledFont(13, weight: .black, design: .rounded, maxScale: 1.15)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    /// おじさんのドット絵を 1 ドット = 1pt（本番の半分）で描く。
    fileprivate static func smallOjisan(_ pose: OjisanPuzzleArt.Pose) -> some View {
        let size = OjisanPuzzleArt.dotSize(pose) ?? (width: 40, height: 48)
        return OjisanPuzzleArt.image(pose)
            .scaleEffect(0.5)
            .frame(width: CGFloat(size.width), height: CGFloat(size.height))
    }

    /// 下から積んだ盤を作る。`stacks` は列 → 下から順の荷物。
    fileprivate static func grid(rows: Int, columns: Int, stacks: [Int: [Int]]) -> [[Int]] {
        var g = Array(repeating: Array(repeating: 0, count: columns), count: rows)
        for (column, kinds) in stacks {
            for (i, kind) in kinds.enumerated() { g[rows - 1 - i][column] = kind }
        }
        return g
    }

    /// 浮いている荷物を下へ落とす（れんさの図の 3 コマ目）。
    fileprivate static func gravity(_ g: [[Int]]) -> [[Int]] {
        let rows = g.count, columns = g.first?.count ?? 0
        var out = Array(repeating: Array(repeating: 0, count: columns), count: rows)
        for c in 0..<columns {
            var write = rows - 1
            for r in stride(from: rows - 1, through: 0, by: -1) where g[r][c] != 0 {
                out[write][c] = g[r][c]
                write -= 1
            }
        }
        return out
    }
}

/// 図のための小さな盤。本番の盤と同じ部品（荷物・出口の列・クリアのライン）を縮めて描く。
struct OjisanPuzzleMiniBoard: View {
    struct Cell: Hashable {
        let row: Int
        let column: Int
    }

    let grid: [[Int]]
    let cell: CGFloat
    var clearLine: Int?
    var spawnColumn: Int?
    var spawnWarn = false
    var highlight: Set<Cell> = []

    private var rows: Int { grid.count }
    private var columns: Int { grid.first?.count ?? 0 }
    private var inset: CGFloat { max(2, cell * 0.18) }

    var body: some View {
        VStack(spacing: 1) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<columns, id: \.self) { column in
                        OjisanPuzzleView.luggage(grid[row][column], side: cell - 1)
                            .background {
                                if highlight.contains(Cell(row: row, column: column)) {
                                    RoundedRectangle(cornerRadius: cell * 0.24, style: .continuous)
                                        .fill(Theme.surface)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: cell * 0.24, style: .continuous)
                                                .stroke(Theme.ink, lineWidth: 1.5)
                                        }
                                        .padding(-1.5)
                                }
                            }
                    }
                }
            }
        }
        .padding(inset)
        .background {
            RoundedRectangle(cornerRadius: max(4, cell * 0.5), style: .continuous)
                .fill(Theme.fillMuted.opacity(0.18))
        }
        .overlay(alignment: .topLeading) { spawnMark }
        .overlay(alignment: .topLeading) { clearLineMark }
    }

    /// 組の出口の列（▼）。塞がって終わる図では珊瑚色。
    @ViewBuilder
    private var spawnMark: some View {
        if let spawnColumn {
            let tint = spawnWarn ? Theme.coral : Theme.inkSub
            let iconTint = spawnWarn ? Theme.coralText : Theme.inkSubText
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: max(1, cell * 0.2), style: .continuous)
                    .fill(tint.opacity(spawnWarn ? 0.22 : 0.10))
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: max(5, cell * 0.55))) // fixed-size: 盤の枠内に収める印（盤の大きさに比例）
                    .foregroundStyle(iconTint)
                    .offset(y: -cell * 0.6)
            }
            .frame(width: cell, height: cell * CGFloat(rows))
            .offset(x: inset + CGFloat(spawnColumn) * cell - 0.5, y: inset)
            .allowsHitTesting(false)
        }
    }

    /// クリアのライン（荷運びモード）。ラインより下を薄い水色で塗り、太い線を引く。
    @ViewBuilder
    private var clearLineMark: some View {
        if let clearLine {
            let y = inset + CGFloat(clearLine) * cell - 0.5
            let width = CGFloat(columns) * cell
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Theme.Fill.teal.opacity(0.16))
                    .frame(width: width, height: CGFloat(rows - clearLine) * cell)
                    .offset(x: inset, y: y)
                Capsule().fill(Theme.surface)
                    .frame(width: width + 2, height: 4)
                    .offset(x: inset - 1, y: y - 2)
                Capsule().fill(Theme.ink)
                    .frame(width: width + 2, height: 2)
                    .offset(x: inset - 1, y: y - 1)
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - 1. もくてき

/// 1 項目 = 1 モードぶんの図。遊んでいるモードの「？」には、そのモードの目的だけを出す
/// （会長指示 2026-10-12。以前は腰痛モード・パズルモードを常に並べていた）。
struct GoalFigure: View {
    private static let cell: CGFloat = 10.5

    let mode: OjisanPuzzleMode

    private let backpainBoard: [[Int]] = {
        var g = OjisanPuzzleHowToFigures.grid(rows: 12, columns: 6, stacks: [
            0: [5, 2, 3, 1], 1: [2, 2, 4, 5, 1], 2: [3, 4, 1, 1, 5, 2], 3: [1, 5, 5, 2], 4: [4, 3, 2, 2, 1], 5: [5, 1, 3, 4],
        ])
        g[1][2] = 2; g[2][2] = 3
        return g
    }()

    private let puzzleBoard: [[Int]] = {
        var g = OjisanPuzzleHowToFigures.grid(rows: 12, columns: 6, stacks: [
            0: [3, 3], 1: [3, 1], 3: [5], 4: [5, 2], 5: [2],
        ])
        g[1][2] = 4; g[2][2] = 1
        return g
    }()

    private var boardHeight: CGFloat { 12 * Self.cell + max(2, Self.cell * 0.18) * 2 }

    var body: some View {
        switch mode {
        case .backpain: backpainPanel
        case .puzzle: puzzlePanel
        }
    }

    private var backpainPanel: some View {
        HStack(alignment: .top, spacing: 4) {
            OjisanPuzzleMiniBoard(grid: backpainBoard, cell: Self.cell,
                                  clearLine: OjisanPuzzleCleanup.clearLineRow,
                                  spawnColumn: OjisanPuzzleBoard.spawnColumn)
            VStack(alignment: .leading, spacing: 2) {
                // 「ここまで下げたら」の印は、クリアのラインのすぐ上に置く。
                Color.clear.frame(height: max(0, boardHeight * CGFloat(OjisanPuzzleCleanup.clearLineRow) / CGFloat(OjisanPuzzleBoard.rows) - 44))
                HStack(alignment: .top, spacing: 2) {
                    Image(systemName: "flag.checkered")
                        .scaledFont(10, weight: .bold, maxScale: 1.15)
                        .foregroundStyle(Theme.tealText)
                    OjisanPuzzleHowToFigures.label(tr("ここまで\n下げたら\nクリア"), size: 9.5)
                }
                Spacer(minLength: 8)
                HStack(alignment: .top, spacing: 2) {
                    Image(systemName: "arrow.up")
                        .scaledFont(10, weight: .bold, maxScale: 1.15)
                        .foregroundStyle(Theme.coralText)
                    OjisanPuzzleHowToFigures.label(tr("時間で\n下から\nせり上がる"), size: 9.5, color: Theme.coralText)
                }
            }
            .frame(height: boardHeight)
        }
        .frame(maxWidth: .infinity)
    }

    private var puzzlePanel: some View {
        HStack(alignment: .top, spacing: 6) {
            OjisanPuzzleMiniBoard(grid: puzzleBoard, cell: Self.cell,
                                  spawnColumn: OjisanPuzzleBoard.spawnColumn)
            VStack(alignment: .leading, spacing: 2) {
                OjisanPuzzleHowToFigures.label(tr("スコア"), size: 9, color: Theme.inkSubText)
                OjisanPuzzleHowToFigures.label("1280", size: 16)
                OjisanPuzzleHowToFigures.label(tr("2連鎖"), size: 11, color: Theme.coralText)
                Spacer(minLength: 0)
                OjisanPuzzleHowToFigures.label(tr("ゲージ\nなし"), size: 9.5, color: Theme.inkSubText)
            }
            .frame(height: boardHeight)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 2. そうさ

struct ControlsFigure: View {
    private static let rows = 5

    private static let base: [[Int]] = OjisanPuzzleHowToFigures.grid(rows: rows, columns: 4, stacks: [0: [1], 2: [2, 3], 3: [5]])
    private static let pinched: [[Int]] = OjisanPuzzleHowToFigures.grid(rows: rows, columns: 3, stacks: [0: [1, 5, 3, 2], 2: [2, 4, 1, 5]])

    private static func with(_ g: [[Int]], _ cells: [(Int, Int, Int)]) -> [[Int]] {
        var out = g
        for (r, c, k) in cells { out[r][c] = k }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                panel(tr("よこにスワイプ"), icons: ["hand.draw.fill", "arrow.left.and.right"],
                      frames: [Self.with(Self.base, [(1, 1, 4), (2, 1, 2)]), Self.with(Self.base, [(1, 2, 4), (2, 2, 2)])],
                      caption: tr("1 マスずつ左右へ"))
                panel(tr("タップで回す"), icons: ["hand.tap.fill", "arrow.clockwise"],
                      frames: [Self.with(Self.base, [(1, 1, 4), (2, 1, 2)]), Self.with(Self.base, [(2, 1, 2), (2, 2, 4)])],
                      caption: tr("時計回り。壁ぎわは自動でずれる"))
            }
            HStack(alignment: .top, spacing: 12) {
                panel(tr("下にスワイプ"), icons: ["hand.draw.fill", "arrow.down"],
                      frames: [Self.with(Self.base, [(0, 1, 4), (1, 1, 2)]), Self.with(Self.base, [(3, 1, 4), (4, 1, 2)])],
                      caption: tr("動かしたぶんだけ落ちる。長く払えば一気に"))
                panel(tr("はさまれたら2回タップ"), icons: ["hand.tap.fill"],
                      frames: [Self.with(Self.pinched, [(2, 1, 4), (3, 1, 2)]),
                               Self.with(Self.pinched, [(2, 1, 4), (3, 1, 2)]),
                               Self.with(Self.pinched, [(3, 1, 2), (4, 1, 4)])],
                      marks: [nil, ("xmark", Theme.coralText), ("arrow.up.arrow.down", Theme.tealText)],
                      caption: tr("回せないときは、もう 1 回で上下が入れかわる"))
            }
        }
    }

    private func panel(_ title: String, icons: [String], frames: [[[Int]]],
                       marks: [(String, Color)?] = [], caption: String) -> some View {
        let cell: CGFloat = frames.count >= 3 ? 11 : 13
        return VStack(alignment: .leading, spacing: 6) {
            OjisanPuzzleHowToFigures.heading(title, icons: icons)
            RuleFrames(count: frames.count, spacing: frames.count >= 3 ? 2 : 6) { index in
                VStack(spacing: 2) {
                    if !marks.isEmpty {
                        Group {
                            if let mark = marks[index] {
                                Image(systemName: mark.0)
                                    .scaledFont(10, weight: .black, maxScale: 1.15)
                                    .foregroundStyle(mark.1)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(height: 12)
                    }
                    OjisanPuzzleMiniBoard(grid: frames[index], cell: cell)
                }
            }
            .frame(maxWidth: .infinity)
            OjisanPuzzleHowToFigures.caption(caption)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - 3. きえる・れんさ

struct ChainFigure: View {
    static let rows = 7
    private static let cell: CGFloat = 12.5

    typealias Cell = OjisanPuzzleMiniBoard.Cell

    struct Step {
        let label: String
        let points: String
        let grid: [[Int]]
        let highlight: Set<Cell>
        let emphasized: Bool
    }

    // 文言は表示言語で引き直すので、計算型にする（static let だと最初の言語で固まる）。
    static var steps: [Step] {
        let rows = Self.rows
        let base = OjisanPuzzleHowToFigures.grid(rows: rows, columns: 6, stacks: [
            0: [1, 3, 5], 1: [2, 4, 4, 4], 2: [5, 3, 1], 3: [2, 3], 4: [1, 5], 5: [2],
        ])
        var first = base
        first[rows - 5][1] = 4
        first[rows - 6][1] = 3
        let firstGroup: Set<Cell> = [Cell(row: rows - 2, column: 1), Cell(row: rows - 3, column: 1),
                                     Cell(row: rows - 4, column: 1), Cell(row: rows - 5, column: 1)]
        var second = base
        for cell in firstGroup { second[cell.row][cell.column] = 0 }
        second[rows - 2][1] = 3
        let secondGroup: Set<Cell> = [Cell(row: rows - 2, column: 0), Cell(row: rows - 2, column: 1),
                                      Cell(row: rows - 2, column: 2), Cell(row: rows - 2, column: 3)]
        var third = second
        for cell in secondGroup { third[cell.row][cell.column] = 0 }
        return [
            Step(label: tr("4 つつながった"), points: tr("40 点"), grid: first, highlight: firstGroup, emphasized: false),
            Step(label: tr("落ちて 2 れんさ！"), points: tr("+ 80 点"), grid: second, highlight: secondGroup, emphasized: true),
            Step(label: tr("おわり"), points: tr("= 120 点"), grid: OjisanPuzzleHowToFigures.gravity(third), highlight: [], emphasized: false),
        ]
    }

    var body: some View {
        RuleFrames(count: Self.steps.count, spacing: 5) { index in
            let step = Self.steps[index]
            VStack(spacing: 4) {
                OjisanPuzzleHowToFigures.label(step.label, size: 10.5, color: step.emphasized ? Theme.coralText : Theme.inkSubText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                OjisanPuzzleMiniBoard(grid: step.grid, cell: Self.cell, highlight: step.highlight)
                OjisanPuzzleHowToFigures.label(step.points, size: 11)
            }
            .frame(width: 6 * Self.cell + 6)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 4. 荷物の種類

struct WeightFigure: View {
    private static var names: [String] { [tr("座布団\nの山"), tr("スイカ"), tr("クーラー\nボックス"), tr("灯油の\nポリタンク"), tr("ビール\nケース")] }

    var body: some View {
        RuleLineup(count: OjisanPuzzleLuggage.all.count, low: tr("かるい"), high: tr("おもい")) { index in
            let kind = OjisanPuzzleLuggage.all[index]
            VStack(spacing: 4) {
                OjisanPuzzleView.luggage(kind.value, side: 34)
                Text(Self.names[index])
                    .scaledFont(10, weight: .bold, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(height: 28, alignment: .top)
                HStack(spacing: 1) {
                    ForEach(0..<kind.weight, id: \.self) { _ in
                        Image(systemName: "scalemass.fill")
                            .scaledFont(8, weight: .regular, maxScale: 1.1)
                    }
                }
                .foregroundStyle(kind.weight >= 4 ? Theme.coralText : Theme.inkSubText)
            }
        }
    }
}

// MARK: - 5. 腰痛ゲージ

struct GaugeFigure: View {
    /// 段階の帯の幅。iPhone SE のカード（幅 315pt 前後）に収める。
    private static let bandWidth: CGFloat = 296

    // 数値の目盛りは出さない（ゲージの計算方法は会長検討中・#2069）。段階の帯と姿だけ。
    private static var stages: [RuleStageBand<AnyView>.Stage] { [
        .init(OjisanPuzzlePain.Stage.easy.caption, share: 0.4, color: Theme.Fill.teal),
        .init(OjisanPuzzlePain.Stage.aching.caption, share: 0.4, color: Theme.Fill.yellow, captionColor: Theme.coralText),
        .init(OjisanPuzzlePain.Stage.severe.caption, share: 0.2, color: Theme.Fill.coral, captionColor: Theme.coralText),
    ] }

    private static let poses: [OjisanPuzzleArt.Pose] = [.easy, .aching, .severe]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RuleStageBand(stages: Self.stages, width: Self.bandWidth) { index in
                AnyView(
                    HStack(alignment: .bottom, spacing: 0) {
                        OjisanPuzzleHowToFigures.smallOjisan(Self.poses[index])
                        if index == Self.poses.count - 1 {
                            Image(systemName: "cross.case.fill")
                                .scaledFont(12, weight: .bold, maxScale: 1.15)
                                .foregroundStyle(Theme.coralText)
                        }
                    }
                )
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 5) {
                row("arrow.up", Theme.coralText, tr("重い荷物をかかえるほど腰にくる"))
                row("arrow.down", Theme.tealText, tr("消すと楽になる"))
                row("shippingbox.fill", Theme.inkSubText, tr("荷物が多い盤ほど、最初から腰にきている"))
                row("hare.fill", Theme.coralText, tr("腰にくると落ちるのが速くなり、操作が遅れる"))
                row("cross.case.fill", Theme.coralText, tr("満タンで入院"))
            }
        }
    }

    private func row(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .scaledFont(11, weight: .bold, maxScale: 1.3)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(text)
                .themeCaption(11.5, weight: .bold, maxScale: 1.3)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 6. おわり

/// 終わり方。荷運びモード（旧名・腰痛モード）は入院と積みあがりの両方があるので並べ、パズルモードには
/// 入院が無いので積みあがりだけを出す（会長指示 2026-10-12。パズルモードの「？」に入院の絵を出さない）。
struct EndFigure: View {
    private static let buriedBoard: [[Int]] = OjisanPuzzleHowToFigures.grid(rows: 7, columns: 6, stacks: [
        0: [1, 5, 2], 1: [3, 2, 2, 4, 1], 2: [5, 1, 3, 3, 2, 4, 1], 3: [2, 4, 1, 5, 3], 4: [1, 5, 2], 5: [4, 1],
    ])

    let mode: OjisanPuzzleMode

    var body: some View {
        switch mode {
        case .backpain:
            HStack(alignment: .top, spacing: 10) {
                hospitalizedPanel
                Rectangle().fill(Theme.fillMuted.opacity(0.2)).frame(width: 1)
                buriedPanel
            }
        case .puzzle:
            buriedPanel
        }
    }

    private var hospitalizedPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            OjisanPuzzleHowToFigures.heading(tr("入院"), icons: ["cross.case.fill"])
            OjisanPuzzleHowToFigures.smallOjisan(.hospitalized)
                .frame(maxWidth: .infinity)
            OjisanPuzzleHowToFigures.caption(tr("ゲージが満タン"))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var buriedPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            OjisanPuzzleHowToFigures.heading(tr("積みあがった"), icons: ["arrow.up.to.line"])
            HStack(alignment: .top, spacing: 4) {
                OjisanPuzzleMiniBoard(grid: Self.buriedBoard, cell: 10,
                                      spawnColumn: OjisanPuzzleBoard.spawnColumn, spawnWarn: true)
                OjisanPuzzleHowToFigures.label(tr("▼の列が\nふさがる"), size: 9.5, color: Theme.coralText)
            }
            .frame(maxWidth: .infinity)
            OjisanPuzzleHowToFigures.caption(tr("荷物が出てくる位置（▼の列のいちばん上）が埋まる"))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
