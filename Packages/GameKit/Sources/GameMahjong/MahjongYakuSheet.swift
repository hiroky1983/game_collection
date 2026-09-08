import SwiftUI
import Core
import MahjongTiles

/// 対局中 1 タップで開ける役の早見表（#501）。
///
/// 役は 30 種以上あり、何をねらえばいいか分からないまま切る牌を選べない。全役を飜数順に並べ、
/// 成立条件と牌例をその場で引けるようにする（花札の `HanafudaYakuSheet` と同じ役割）。
///
/// **並びも名前も飜数も `MahjongYaku` から取る**。役判定（`MahjongScoring`）が使うのと同じ
/// 定義source なので、片方だけ直して表と実装がズレることが起きない。
///
/// モデルには一切触らない（`MahjongModel` を受け取らない）。開いている間も対局の状態は動かず、
/// 閉じれば元の局面がそのまま残る。
public struct MahjongYakuSheet: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                ForEach(MahjongYaku.Section.allCases, id: \.self) { section in
                    Section {
                        ForEach(MahjongYaku.yaku(in: section), id: \.self) { yaku in
                            row(yaku)
                        }
                    } header: {
                        Text(section.rawValue)
                    } footer: {
                        if let note = Self.footer(for: section) {
                            Text(note)
                        }
                    }
                }
            }
            .navigationTitle("役の早見表")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    static func footer(for section: MahjongYaku.Section) -> String? {
        switch section {
        case .one:
            // 門前を崩さないのは暗槓だけ（`MahjongCall.breaksConcealment`）。大明槓も崩す。
            return "「門前のみ」はポン・チー・大明槓をすると消える役です（暗槓は門前のままなので消えません）。"
        case .two, .three:
            return "「鳴きN飜」はポン・チー・大明槓をすると飜数が下がる役、「門前のみ」は消える役です。"
        case .yakuman:
            return "役満は飜数によらず点数が固定で、複数そろうと倍役満になります。"
        case .dora:
            return "ドラは役ではありません。ドラだけでは和了できず、ほかに役が1つ以上要ります。"
        }
    }

    // MARK: - 行

    private func row(_ yaku: MahjongYaku) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(yaku.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(yaku.reading)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                Spacer(minLength: 6)
                Text(yaku.hanText)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.coral)
                    .fixedSize()
            }
            Text(yaku.requirement)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Theme.inkSub)
                .fixedSize(horizontal: false, vertical: true)
            exampleTiles(yaku)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(yaku.name)。\(yaku.reading)。\(yaku.hanText)。\(yaku.requirement)")
    }

    /// 牌例。牌が多い役は行を折り返す（横スクロールにすると、動かさないと全体が見えない）。
    @ViewBuilder
    private func exampleTiles(_ yaku: MahjongYaku) -> some View {
        let lines = Self.exampleLines(yaku.example)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 6) {
                        ForEach(Array(line.enumerated()), id: \.offset) { _, group in
                            HStack(spacing: 1) {
                                ForEach(Array(group.enumerated()), id: \.offset) { _, tile in
                                    MahjongTileView(
                                        tile: tile, width: Self.tileWidth,
                                        height: Self.tileWidth * 1.34
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding(.top, 1)
            // 牌の絵柄は上の成立条件の言い換えなので、読み上げでは 1 枚ずつ読ませない。
            .accessibilityHidden(true)
        }
    }

    static let tileWidth: CGFloat = 20
    /// 1 行に並べる牌の上限。20pt 幅なら 12 枚 + 面子の間隔で 300pt 弱に収まり、
    /// もっとも狭い端末（iPhone SE・幅 375pt）でもリストの行からはみ出さない。
    static let maxTilesPerLine = 12

    /// 面子を崩さずに行へ詰める。1 つの面子が途中で切れると別の形に見えてしまうため、
    /// 上限を超える場合は**面子の切れ目で**折り返す。
    static func exampleLines(_ groups: [[MahjongTile]]) -> [[[MahjongTile]]] {
        var lines: [[[MahjongTile]]] = []
        var line: [[MahjongTile]] = []
        var count = 0
        for group in groups {
            if !line.isEmpty && count + group.count > maxTilesPerLine {
                lines.append(line)
                line = []
                count = 0
            }
            line.append(group)
            count += group.count
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }
}
