import SwiftUI
import Core

/// 駒の動きの対応表（#2166）。「遊び方」シートの「くわしいルール」から開く。
///
/// 盤の駒は言語に関係なく漢字のまま描く（会長決裁 #2166）。英語で遊ぶ人が盤の漢字と
/// 名前・動きを結び付けられるよう、駒の絵（`KomaView`・漢字）と名前・動きを 1 行ずつ並べる。
/// 駒の絵は盤と同じ部品で描くので漢字のまま。名前と動きだけを表示言語で引く。
struct ShogiPieceGuideSheet: View {
    /// 駒の表の下に置く補足（持ち駒・成り）。表示用なので、その時点の言語で引く。
    private var rules: [(String, String)] {
        [
            (tr("持ち駒"), tr("取った相手の駒は持ち駒になり、自分の駒として好きなマスに打てます。")),
            (tr("成り"), tr("相手陣（奥の3段）に入る・その中で動く・そこから出るときに成れます。金と玉は成りません。")),
        ]
    }

    var body: some View {
        // 「くわしいルール」は共通部品 `RuleListSheet` で組む決まり（#1414）。駒の表は `figures` に置く。
        RuleListSheet(rules: rules) {
            RuleFigureCard(title: tr("基本の駒")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ShogiPieceGuide.basic) { entry in
                        ShogiPieceGuideRow(entry: entry)
                    }
                }
            }
            RuleFigureCard(title: tr("成った駒")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ShogiPieceGuide.promoted) { entry in
                        ShogiPieceGuideRow(entry: entry)
                    }
                }
            }
        }
    }
}

/// 対応表の 1 行分。駒（1 つ以上）・名前・動き。
struct ShogiPieceGuideEntry: Identifiable {
    /// 行の識別子（表示しない）。
    let id: String
    /// 行の頭に並べる駒。成銀・成桂・成香のように同じ動きの駒はまとめて 1 行にする。
    let pieces: [Piece]
    /// 駒の名前（表示言語）。
    let name: String
    /// 動きの説明（表示言語）。
    let movement: String

    /// 読み上げ文。駒の絵（漢字）は読ませず、名前と動きを読む（英語の読み上げに漢字を混ぜない）。
    var accessibilityLabel: String {
        tr("%1$@：%2$@", name, movement)
    }
}

/// 対応表の中身。テストから「全駒種を載せているか」を確かめられるよう、View の外に置く。
/// 文言は表示言語に追従させるため、保存せず毎回組む（#2109）。
enum ShogiPieceGuide {
    static var basic: [ShogiPieceGuideEntry] {
        [
            ShogiPieceGuideEntry(
                id: "king",
                pieces: [Piece(type: .king, color: .black), Piece(type: .king, color: .white)],
                name: tr("玉将・王将"),
                movement: tr("全方向に1マス。取られたら負け")
            ),
            ShogiPieceGuideEntry(
                id: "rook",
                pieces: [Piece(type: .rook, color: .black)],
                name: tr("飛車"),
                movement: tr("縦・横にどこまでも進む")
            ),
            ShogiPieceGuideEntry(
                id: "bishop",
                pieces: [Piece(type: .bishop, color: .black)],
                name: tr("角行"),
                movement: tr("斜めにどこまでも進む")
            ),
            ShogiPieceGuideEntry(
                id: "gold",
                pieces: [Piece(type: .gold, color: .black)],
                name: tr("金将"),
                movement: tr("斜め後ろ以外の6方向に1マス")
            ),
            ShogiPieceGuideEntry(
                id: "silver",
                pieces: [Piece(type: .silver, color: .black)],
                name: tr("銀将"),
                movement: tr("斜め4方向と前に1マス")
            ),
            ShogiPieceGuideEntry(
                id: "knight",
                pieces: [Piece(type: .knight, color: .black)],
                name: tr("桂馬"),
                movement: tr("2マス前の左右どちらかへ跳ぶ（間の駒を飛び越せる）")
            ),
            ShogiPieceGuideEntry(
                id: "lance",
                pieces: [Piece(type: .lance, color: .black)],
                name: tr("香車"),
                movement: tr("前にどこまでも進む")
            ),
            ShogiPieceGuideEntry(
                id: "pawn",
                pieces: [Piece(type: .pawn, color: .black)],
                name: tr("歩兵"),
                movement: tr("前に1マス進む")
            ),
        ]
    }

    static var promoted: [ShogiPieceGuideEntry] {
        [
            ShogiPieceGuideEntry(
                id: "dragon",
                pieces: [Piece(type: .rook, color: .black, promoted: true)],
                name: tr("龍王（成った飛車）"),
                movement: tr("飛車の動きに加えて、斜めに1マス")
            ),
            ShogiPieceGuideEntry(
                id: "horse",
                pieces: [Piece(type: .bishop, color: .black, promoted: true)],
                name: tr("龍馬（成った角行）"),
                movement: tr("角行の動きに加えて、縦・横に1マス")
            ),
            ShogiPieceGuideEntry(
                id: "promotedMinor",
                pieces: [
                    Piece(type: .silver, color: .black, promoted: true),
                    Piece(type: .knight, color: .black, promoted: true),
                    Piece(type: .lance, color: .black, promoted: true),
                ],
                name: tr("成銀・成桂・成香"),
                movement: tr("金将と同じ動き")
            ),
            ShogiPieceGuideEntry(
                id: "tokin",
                pieces: [Piece(type: .pawn, color: .black, promoted: true)],
                name: tr("と金（成った歩兵）"),
                movement: tr("金将と同じ動き")
            ),
        ]
    }

    static var all: [ShogiPieceGuideEntry] { basic + promoted }
}

/// 対応表の 1 行。駒の絵は盤と同じ `KomaView`（漢字のまま）で描く。
private struct ShogiPieceGuideRow: View {
    let entry: ShogiPieceGuideEntry
    /// 駒の絵の大きさ。3 枚並ぶ行（成銀・成桂・成香）でも SE の幅に収まる大きさにする。
    private static let komaSize: CGFloat = 30

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 2) {
                ForEach(Array(entry.pieces.enumerated()), id: \.offset) { _, piece in
                    KomaView(piece: piece, size: Self.komaSize, pointsUp: true)
                }
            }
            // 駒の列の幅は行ごとに揃える（名前の頭の位置を揃えて読みやすくする）。3 枚の行が最も広い。
            // `KomaView` の枠は `size * 0.86` 四方。
            .frame(width: Self.komaSize * 0.86 * 3 + 4, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .scaledFont(14, weight: .black, design: .rounded)
                    .foregroundStyle(Theme.coral)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.movement)
                    .scaledFont(12, weight: .medium, design: .rounded)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityLabel)
    }
}
