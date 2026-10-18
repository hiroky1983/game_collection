// #2438 のレイアウト検討モック（マインスイーパー・今 vs C〔＋参考で A〕）の生成器。**アプリのコードではない**（docs に置くだけ）。
// 使い方: このファイルを `Packages/GameKit/Tests/GameMinesweeperTests/` にコピーし、
//   DUTY_SCRATCH_DIR=<出力先> swift test --package-path Packages/GameKit --filter LayoutMock2438
// で `<出力先>/mock2438/` に PNG 10 枚と寸法の JSON が出る（シミュレータ不要。macOS の ImageRenderer で描く）。
// 実物の部品（GameStatusBar・GameClockLabel・GameControlArea・GameReplayBar・RecordLabel・GameOverflowBar・popCard・scaledFont）を
// そのまま使い、盤は `MinesweeperView.boardGrid` / `cellBody` の写し（private なので同じ寸法・色で組み直し）、
// ナビバー・ステータスバー・バナーは見た目を写して描いている。#2427（麻雀ソリティア）以降の兄弟 Issue の生成器と同じ型。
// 「今」は release/v1.1.13（#2423 反映後）の `MinesweeperView.body` の写し。終わったらコピーは消す（コミットしない）。
import Foundation
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
import Core
import CoreTestSupport
@testable import GameMinesweeper

private struct Phone {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let safeTop: CGFloat
    let safeBottom: CGFloat
    let scale: CGFloat
    /// iOS 26 のナビバーの高さ。iPhone 17 は 54pt（実スクショ ip17_spiderzoom_v2cur.png の実測）、
    /// iPhone SE は 44pt（#2435 のブロック崩しで `BlocksLayoutTests.devices` の実機プローブに合わせた値。非ノッチ端末の標準）。
    let navBarHeight: CGFloat
}

private let phones = [
    Phone(name: "ip17", width: 402, height: 874, safeTop: 62, safeBottom: 34, scale: 3, navBarHeight: 54),
    Phone(name: "se3", width: 375, height: 667, safeTop: 20, safeBottom: 0, scale: 2, navBarHeight: 44),
]

/// 描画中に GeometryReader から寸法を書き留める器。
private final class Measure: @unchecked Sendable {
    var values: [String: Double] = [:]
    func set(_ key: String, _ value: CGFloat) { values[key] = (Double(value) * 100).rounded() / 100 }
}

/// C の「大きいバナー」の仮の枠。大きさは会長決裁待ち（#2111「C のバナーの大きさ」）なので、AdMob の 2 つの定型を描く。
private enum BannerKind {
    /// 今のアダプティブバナー（枠 50pt）。
    case standard
    /// ラージバナー 320×100（枠 100pt）。
    case large
    /// ミディアムレクタングル 300×250（枠 250pt。柵越えおじさんの記録ページで既に使っている寸法・`MediumRectangleSlot`）。
    case mrec

    var slotHeight: CGFloat {
        switch self {
        case .standard: return 50   // BannerSlot.height（View の static は MainActor 隔離なのでここでは値を書く）
        case .large: return 100
        case .mrec: return 250
        }
    }
    var adSize: CGSize? {
        switch self {
        case .standard: return nil
        case .large: return CGSize(width: 320, height: 100)
        case .mrec: return CGSize(width: 300, height: 250)
        }
    }
    var label: String {
        switch self {
        case .standard: return "バナー広告（50pt・そのまま残す）"
        case .large: return "大きいバナー（仮・ラージバナー 320×100）"
        case .mrec: return "大きいバナー（仮・MREC 300×250）"
        }
    }
    var suffix: String {
        switch self {
        case .standard: return "cur"
        case .large: return "c100"
        case .mrec: return "c250"
        }
    }
}

// MARK: - 盤（MinesweeperView.boardGrid / cellBody の写し）

private func numberColor(_ n: Int) -> Color {
    switch n {
    case 1: return Color(hex: 0x1565C0)
    case 2: return Color(hex: 0x2E7D32)
    case 3: return Theme.coralText
    case 4: return Color(hex: 0x0D47A1)
    case 5: return Color(hex: 0xB71C1C)
    case 6: return Color(hex: 0x006064)
    case 7: return Theme.Fixed.ink
    default: return Color(hex: 0x616161)
    }
}

/// マス 1 つ（プレイ中・コンティニュー無し・ヒント無しの分岐だけ）。
private struct CellBody: View {
    let cell: MinesweeperCell
    let size: CGFloat
    var body: some View {
        let iconSize = size * 0.52
        ZStack {
            Rectangle()
                .fill(cell.isRevealed ? Color(hex: 0xD8D8D8) : Color(hex: 0xBDBDBD))
                .padding(0.7)
            if !cell.isRevealed && cell.isFlagged {
                Image(systemName: "flag.fill")
                    .resizable().scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .foregroundStyle(Theme.coralText)
            } else if !cell.isRevealed && cell.mark == .question {
                Image(systemName: "questionmark")
                    .resizable().scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .foregroundStyle(Theme.Fixed.ink)
            } else if cell.isRevealed && cell.adjacentMines > 0 {
                Text("\(cell.adjacentMines)")
                    .font(.system(size: size * 0.56, weight: .black, design: .rounded))
                    .foregroundStyle(numberColor(cell.adjacentMines))
            }
        }
        .frame(width: size, height: size)
    }
}

private struct BoardGrid: View {
    let model: MinesweeperModel
    let cellSize: CGFloat
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(hex: 0x777777)
            VStack(spacing: 0) {
                ForEach(0..<model.rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<model.cols, id: \.self) { c in
                            if let cell = model.cell(atRow: r, col: c) {
                                CellBody(cell: cell, size: cellSize)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: cellSize * CGFloat(model.cols), height: cellSize * CGFloat(model.rows))
    }
}

/// 等倍の盤（`MinesweeperView.board` の写し）。正方形・角丸・影。呼び出し側で `.layoutPriority(1)` を付ける。
private struct Board: View {
    let model: MinesweeperModel
    let measure: Measure
    let prefix: String
    var body: some View {
        GeometryReader { geo in
            let f = geo.frame(in: .named("phone"))
            let _ = {
                measure.set("\(prefix).board_w_pt", geo.size.width)
                measure.set("\(prefix).board_h_pt", geo.size.height)
                measure.set("\(prefix).board_top_pt", f.minY)
                measure.set("\(prefix).board_left_pt", f.minX)
                measure.set("\(prefix).cell_pt", geo.size.width / CGFloat(model.cols))
            }()
            BoardGrid(model: model, cellSize: geo.size.width / CGFloat(model.cols))
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
    }
}

// MARK: - 今の画面の部品（MinesweeperView の写し）

/// 残り地雷の表示（`statusBar` の leading。プレイ中・旗モードオフ）。
private struct MinesLabel: View {
    let model: MinesweeperModel
    let size: CGFloat
    var body: some View {
        Label(String(format: "%02d", max(0, model.remainingMines)), systemImage: "flag.fill")
            .scaledFont(size, weight: .bold, design: .monospaced)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(Theme.coralText)
            .lineLimit(1)
    }
}

@MainActor
private func clockText(_ model: MinesweeperModel) -> String {
    String(format: "%03d", min(model.elapsedSeconds, 999))
}

/// 今の帯（`GameStatusBar`・44pt）。
private struct CurrentStatusBar: View {
    let model: MinesweeperModel
    let measure: Measure
    let prefix: String
    var body: some View {
        GameStatusBar {
            MinesLabel(model: model, size: 16)
        } trailing: {
            GameClockLabel(clockText(model)).fixedSize(horizontal: true, vertical: false)
        }
        .background(GeometryReader { geo in
            let _ = measure.set("\(prefix).status_h_pt", geo.size.height)
            Color.clear
        })
    }
}

private struct EllipsisButton: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Theme.fillMuted))
    }
}

@MainActor
private func hintAction(model: MinesweeperModel) -> GameActionItem {
    GameActionItem(id: "hint", title: "ヒント", systemImage: "lightbulb.fill", role: .hint,
                   badge: model.needsAdForHint ? .ad() : .count(model.hints.freeRemaining),
                   isEnabled: model.canUseHint) {}
}

/// 操作の段（ヒント）＋「⋯」（旗モード・拡大・諦める）。`GameOverflowBar` の Menu は macOS で見た目が変わるので
/// 「⋯」だけ自前で描く（寸法は同じ 44pt・行の上下余白 8pt）。
private struct ControlRow: View {
    let model: MinesweeperModel
    var body: some View {
        HStack(spacing: 8) {
            GameOverflowBar(actions: [hintAction(model: model)], verticalPadding: 0)
            EllipsisButton()
        }
        .padding(.vertical, 8)
    }
}

/// 終局後の 1 段（`MinesweeperView.resultControls` の写し。`GameControlArea` が高さのひな形に使う）。
/// macOS の既定の Button はベゼルぶん背が高くなる（カード 52pt）ので `.plain` にして iOS と同じ寸法
/// （カプセル 28.5 ＋ 余白 8×2 = 44.5pt・#2360 の実測）に揃える。ひな形は hidden なので見た目には出ない。
private struct ResultControls: View {
    var body: some View {
        GameReplayBar(onReplay: {}, onChangeSettings: {}) {
            RecordLabel(nil)
        }
        .buttonStyle(.plain)
    }
}

/// 盤の下の操作エリア（`MinesweeperView.controlArea` の写し）。高さは常に終局後の最大構成（記録の段 ＋ レコメンド枠）。
private struct ControlArea: View {
    let model: MinesweeperModel
    let services: GameServices
    let measure: Measure
    let prefix: String
    var body: some View {
        GameControlArea(isFinished: false, services: services) {
            ResultControls()
        } playing: {
            ControlRow(model: model)
        }
        .background(GeometryReader { geo in
            let f = geo.frame(in: .named("phone"))
            let _ = {
                measure.set("\(prefix).control_h_pt", geo.size.height)
                measure.set("\(prefix).control_bottom_pt", f.maxY)
            }()
            Color.clear
        })
    }
}

// MARK: - 共通部品（ステータスバー・ナビバー・バナー）

private struct StatusStrip: View {
    let phone: Phone
    var body: some View {
        HStack {
            Text("9:41").font(.system(size: 17, weight: .semibold))
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
            }
            .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, phone.safeTop > 30 ? 40 : 16)
        .frame(height: phone.safeTop, alignment: phone.safeTop > 30 ? .center : .bottom)
    }
}

private struct GlassCircle<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .frame(width: 44, height: 44)
            .background(Circle().fill(Theme.surface).shadow(color: Theme.cardShadow, radius: 8, y: 3))
    }
}

/// iOS 26 の「戻る ＋ ゲーム名 ＋ 右のアイコン群（？・＋）」。＋の絵柄は v1.1.13 から全種類 `plus.circle.fill`（#2370）、色は `Theme.coralText`（#2377）。
private struct NavHeader: View {
    let phone: Phone
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            GlassCircle { Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.coralText) }
            Spacer(minLength: 0)
            Text(verbatim: title)
                .themeBody(20, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            HStack(spacing: 24) {
                Image(systemName: "questionmark.circle")
                Image(systemName: "plus.circle.fill")
            }
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Theme.coralText)
            .padding(.horizontal, 20)
            .frame(height: 44)
            .background(Capsule().fill(Theme.surface).shadow(color: Theme.cardShadow, radius: 8, y: 3))
        }
        .padding(.horizontal, 16)
        .frame(height: phone.navBarHeight)
    }
}

/// バナーの仮の枠。C の大きいバナーは、枠（幅いっぱい・薄い灰）の中に広告そのものの寸法（濃い灰・中央）を描いて大きさが分かるようにする。
private struct BannerPlaceholder: View {
    let kind: BannerKind
    let measure: Measure
    let prefix: String
    var body: some View {
        ZStack {
            Color(white: 0.86)
            if let ad = kind.adSize {
                Color(white: 0.76).frame(width: ad.width, height: ad.height)
            }
            Text(verbatim: kind.label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(white: 0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: kind.slotHeight)
        .background(GeometryReader { geo in
            let f = geo.frame(in: .named("phone"))
            let _ = {
                measure.set("\(prefix).banner_h_pt", geo.size.height)
                measure.set("\(prefix).banner_top_pt", f.minY)
            }()
            Color.clear
        })
    }
}

/// 「⋯」の行とバナーのあいだの余り（`Spacer(minLength: 0)`）。
private struct Slack: View {
    let measure: Measure
    let prefix: String
    var body: some View {
        Spacer(minLength: 0)
            .background(GeometryReader { geo in
                let _ = measure.set("\(prefix).slack_pt", geo.size.height)
                Color.clear
            })
    }
}

// MARK: - 今の画面（MinesweeperView.body の写し）／C（バナーだけ大きい）

private struct CurrentScreen: View {
    let phone: Phone
    let model: MinesweeperModel
    let services: GameServices
    let banner: BannerKind
    let measure: Measure
    let prefix: String

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                StatusStrip(phone: phone)
                NavHeader(phone: phone, title: "マインスイーパー")
                // 縦の余白は 8（#148）。盤 → 「⋯」の行（高さは終局後の最大構成）→ 余り → 広告（#1485）。
                VStack(spacing: 8) {
                    CurrentStatusBar(model: model, measure: measure, prefix: prefix)
                    Board(model: model, measure: measure, prefix: prefix)
                        .layoutPriority(1)
                    ControlArea(model: model, services: services, measure: measure, prefix: prefix)
                    // HowToPlayHint（初回だけ 1 行のミニガイド）は 2 回目以降は出ないので描かない。
                    Slack(measure: measure, prefix: prefix)
                    BannerPlaceholder(kind: banner, measure: measure, prefix: prefix)
                }
                .padding(Theme.pad)
                Color.clear.frame(height: phone.safeBottom)
            }
        }
        .frame(width: phone.width, height: phone.height)
    }
}

// MARK: - A（全画面・参考）

/// 残り地雷・時計を 1 行の札にまとめる（会長の方針: 手数・点数などの表示は 1 行の札に）。
private struct StatusPill: View {
    let model: MinesweeperModel
    let measure: Measure
    let prefix: String
    var body: some View {
        HStack(spacing: 8) {
            MinesLabel(model: model, size: 15)
            Spacer(minLength: 8)
            GameClockLabel(clockText(model)).fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .popCard(corner: 10)
        .background(GeometryReader { geo in
            let _ = measure.set("\(prefix).status_h_pt", geo.size.height)
            Color.clear
        })
    }
}

private struct FullScreenA: View {
    let phone: Phone
    let model: MinesweeperModel
    /// 画面最下部のバナー。A は 50pt のまま。「A の詰め方に大きいバナーを足したら盤はどうなるか」の計算のために .large でも測る（画像は作らない）。
    var banner: BannerKind = .standard
    let measure: Measure
    let prefix: String

    /// 左右の余白。今の 16pt から 8pt に詰める（兄弟 Issue の A と同じ）。盤は正方形なので、増えた幅 16pt がそのまま盤の一辺に乗る。
    static let sideInset: CGFloat = 8

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            VStack(spacing: 0) {
                StatusStrip(phone: phone)
                NavHeader(phone: phone, title: "マインスイーパー")
                VStack(spacing: 8) {
                    StatusPill(model: model, measure: measure, prefix: prefix)
                    Board(model: model, measure: measure, prefix: prefix)
                        .layoutPriority(1)
                    // 操作の段は盤のすぐ下。終局後の記録の段・レコメンドカードの置き場所は共通化のときに決める（兄弟のモックと同じ）。
                    ControlRow(model: model)
                        .background(GeometryReader { geo in
                            let f = geo.frame(in: .named("phone"))
                            let _ = {
                                measure.set("\(prefix).control_h_pt", geo.size.height)
                                measure.set("\(prefix).control_bottom_pt", f.maxY)
                            }()
                            Color.clear
                        })
                    Slack(measure: measure, prefix: prefix)
                }
                .padding(.horizontal, Self.sideInset)
                .padding(.top, 8)
                .padding(.bottom, 8)
                // 画面最下部のバナー（会長の方針: A のバナーは下）。
                BannerPlaceholder(kind: banner, measure: measure, prefix: prefix).padding(.horizontal, Theme.pad)
                Color.clear.frame(height: phone.safeBottom)
            }
        }
        .frame(width: phone.width, height: phone.height)
    }
}

// MARK: - 並べて 1 枚に

private struct SideBySide<Left: View, Right: View>: View {
    let leftCaption: String
    let rightCaption: String
    let left: Left
    let right: Right
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 10) {
                Text(verbatim: leftCaption).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
                left.clipShape(RoundedRectangle(cornerRadius: 28)).overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            }
            VStack(spacing: 10) {
                Text(verbatim: rightCaption).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
                right.clipShape(RoundedRectangle(cornerRadius: 28)).overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            }
        }
        .padding(24)
        .background(Color(white: 0.94))
        .environment(\.colorScheme, .light)
    }
}

// MARK: - 局面を作る

/// 決定論的な乱数（SplitMix64）。地雷の配置を種で固定するためだけに使う。
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

private struct SceneInfo {
    let level: MinesweeperDifficulty
    let seed: UInt64
    let revealed: Int
    let flags: Int
    let elapsed: Int
}

/// 局面。中断データ（`MinesweeperSnapshot`）に地雷だけ置いた盤を入れて復元し（`.playing` で始まる）、
/// 中央のマスを実物の `tap` で開いて連鎖開放させ、開いた領域に接する地雷に旗を立てる。
/// 地雷の配置は種で固定し、開く量が狙いの範囲（初級 25〜45%・上級 22〜35%）に入る最初の種を使う。
@MainActor
private func makeModel(level: MinesweeperDifficulty) -> (MinesweeperModel, GameServices, SceneInfo) {
    let rows = level.rows, cols = level.cols, mines = level.mines
    let center = (row: rows / 2, col: cols / 2)
    let elapsed = level == .beginner ? 42 : 187
    let safeCells = rows * cols - mines
    let targetRange: ClosedRange<Double> = level == .beginner ? 0.25...0.45 : 0.22...0.35
    let flagsWanted = level == .beginner ? 3 : 8

    for seed in UInt64(1)...UInt64(500) {
        var rng = SplitMix64(state: seed &* 2438)
        var excluded = Set<Int>()
        for dr in -1...1 { for dc in -1...1 { excluded.insert((center.row + dr) * cols + (center.col + dc)) } }
        let candidates = (0..<rows * cols).filter { !excluded.contains($0) }.shuffled(using: &rng)
        var isMine = Array(repeating: false, count: rows * cols)
        for i in 0..<mines { isMine[candidates[i]] = true }
        func adjacent(_ r: Int, _ c: Int) -> Int {
            var n = 0
            for dr in -1...1 { for dc in -1...1 where !(dr == 0 && dc == 0) {
                let nr = r + dr, nc = c + dc
                if nr >= 0, nr < rows, nc >= 0, nc < cols, isMine[nr * cols + nc] { n += 1 }
            } }
            return n
        }
        let cells = (0..<rows).map { r in
            (0..<cols).map { c in
                MinesweeperSnapshot.CellData(isRevealed: false, isFlagged: false, isMine: isMine[r * cols + c],
                                             adjacentMines: isMine[r * cols + c] ? 0 : adjacent(r, c), isContinuedMine: false, mark: MinesweeperMark.none)
            }
        }
        let snap = MinesweeperSnapshot(rows: rows, cols: cols, totalMines: mines, cells: cells, flagCount: 0, revealedCount: 0,
                                       elapsedSeconds: elapsed, continueUsed: false, hintsUsed: 0, flagMode: false)
        let store = MemorySnapshotStore()
        try! store.save(snap, for: "minesweeper")
        let services = GameServices(snapshots: store, ads: NoopAdService())
        let model = MinesweeperModel(services: services)
        model.tap(row: center.row, col: center.col)
        let ratio = Double(model.revealedCount) / Double(safeCells)
        guard model.gameState == .playing, targetRange.contains(ratio) else { continue }
        // 開いた領域に接する地雷に旗を立てる（左上から順）。
        var flagged = 0
        outer: for r in 0..<rows {
            for c in 0..<cols where isMine[r * cols + c] {
                var touchesRevealed = false
                for dr in -1...1 { for dc in -1...1 {
                    let nr = r + dr, nc = c + dc
                    if nr >= 0, nr < rows, nc >= 0, nc < cols, model.cell(atRow: nr, col: nc)?.isRevealed == true { touchesRevealed = true }
                } }
                if touchesRevealed {
                    model.toggleFlag(row: r, col: c)
                    flagged += 1
                    if flagged >= flagsWanted { break outer }
                }
            }
        }
        return (model, services, SceneInfo(level: level, seed: seed, revealed: model.revealedCount, flags: model.flagCount, elapsed: elapsed))
    }
    fatalError("狙いの開き方になる種が見つからない")
}

@Suite("#2438 レイアウト検討モック（一時）")
struct LayoutMock2438Tests {
    private static var outDir: URL {
        let base = ProcessInfo.processInfo.environment["DUTY_SCRATCH_DIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: base).appendingPathComponent("mock2438", isDirectory: true)
    }

    /// 描く（寸法を書き留めるのが目的なので `save` が false なら PNG は書かない）。
    @MainActor
    private static func render(_ view: some View, scale: CGFloat, name: String, save: Bool) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        guard save else { return }
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent(name)
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        print("wrote \(url.path) \(image.width)x\(image.height)")
    }

    @Test("今 vs C（＋A）を描いて寸法を書き出す")
    @MainActor
    func render() throws {
        NSApp?.appearance = NSAppearance(named: .aqua)
        var all: [String: [String: Double]] = [:]
        for level in [MinesweeperDifficulty.beginner, .advanced] {
            let (model, services, info) = makeModel(level: level)
            print("\(level): seed \(info.seed) revealed \(info.revealed)/\(model.safeCellCount) flags \(info.flags) remaining \(model.remainingMines) state \(model.gameState)")
            all["scene_\(level.rawValue)"] = [
                "rows": Double(model.rows), "mines": Double(model.totalMines), "seed": Double(info.seed),
                "revealed": Double(info.revealed), "flags": Double(info.flags), "elapsed_s": Double(info.elapsed),
            ]
            for phone in phones {
                let measure = Measure()
                let base = "\(phone.name)_\(level.rawValue)"
                let cur = "\(base)_cur"
                // 今 vs C（ラージバナー 100pt）・今 vs C（MREC 250pt・画像は初級だけ）・今 vs A（参考）。
                for kind in [BannerKind.large, .mrec] {
                    let view = SideBySide(
                        leftCaption: "今（v1.1.13）",
                        rightCaption: "C 盤＋大きいバナー（仮 \(Int(kind.slotHeight))pt）",
                        left: CurrentScreen(phone: phone, model: model, services: services, banner: .standard, measure: measure, prefix: cur)
                            .coordinateSpace(name: "phone"),
                        right: CurrentScreen(phone: phone, model: model, services: services, banner: kind, measure: measure, prefix: "\(base)_\(kind.suffix)")
                            .coordinateSpace(name: "phone")
                    )
                    let name = kind == .large ? "\(base.replacingOccurrences(of: "_", with: "_minesweeper_"))_cur_vs_c.png"
                                              : "\(base.replacingOccurrences(of: "_", with: "_minesweeper_"))_cur_vs_c250.png"
                    try Self.render(view, scale: phone.scale, name: name, save: kind == .large || level == .beginner)
                }
                let viewA = SideBySide(
                    leftCaption: "今（v1.1.13）",
                    rightCaption: "A 全画面（参考）",
                    left: CurrentScreen(phone: phone, model: model, services: services, banner: .standard, measure: measure, prefix: cur)
                        .coordinateSpace(name: "phone"),
                    right: FullScreenA(phone: phone, model: model, measure: measure, prefix: "\(base)_a")
                        .coordinateSpace(name: "phone")
                )
                try Self.render(viewA, scale: phone.scale, name: "\(base.replacingOccurrences(of: "_", with: "_minesweeper_"))_cur_vs_a.png", save: true)
                // 計算用: A の詰め方（1 行の札・左右 8pt）のままバナーだけ 100pt にしたら盤はどうなるか（画像は作らない）。
                try Self.render(
                    FullScreenA(phone: phone, model: model, banner: .large, measure: measure, prefix: "\(base)_a100").coordinateSpace(name: "phone"),
                    scale: 1, name: "", save: false)

                for (k, v) in measure.values {
                    let parts = k.split(separator: ".", maxSplits: 1).map(String.init)
                    all[parts[0], default: [:]][parts[1]] = v
                }
                // 派生値: 使える幅・頭打ちの向き・盤の下から広告の上までの距離。
                for (prefix, sideInset) in [(cur, Theme.pad), ("\(base)_c100", Theme.pad), ("\(base)_c250", Theme.pad),
                                            ("\(base)_a", FullScreenA.sideInset), ("\(base)_a100", FullScreenA.sideInset)] {
                    guard var m = all[prefix], let bw = m["board_w_pt"] else { continue }
                    let availW = Double(phone.width - sideInset * 2)
                    m["avail_w_pt"] = availW
                    m["limited_by"] = bw < availW - 0.5 ? 1 : 0  // 1 = 高さで頭打ち（横幅が余る）, 0 = 幅で頭打ち
                    m["width_use_ratio"] = (bw / availW * 1000).rounded() / 1000
                    if let bt = m["board_top_pt"], let bh = m["board_h_pt"], let at = m["banner_top_pt"] {
                        m["board_bottom_to_banner_pt"] = ((at - bt - bh) * 100).rounded() / 100
                    }
                    all[prefix] = m
                }
            }
        }
        // 操作エリア（`GameControlArea` のひな形 = 記録の段のカード ＋ 8 ＋ レコメンド枠）の内訳。ひな形は `.hidden()` で
        // 背景の GeometryReader が走らないので、記録の段だけを同じ幅で別に描いて高さを取る（scale 1 なので画素 = pt）。
        for phone in phones {
            let renderer = ImageRenderer(content: ResultControls().frame(width: phone.width - Theme.pad * 2))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            let card = Double(image.height)
            let control = all["\(phone.name)_beginner_cur"]?["control_h_pt"] ?? 0
            all["\(phone.name)_control_area"] = ["replay_card_h_pt": card, "recommend_slot_h_pt": control - card - 8, "control_h_pt": control]
        }
        let data = try JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: Self.outDir.appendingPathComponent("measure_minesweeper.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
