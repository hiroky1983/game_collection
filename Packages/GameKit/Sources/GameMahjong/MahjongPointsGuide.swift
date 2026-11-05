import SwiftUI
import Core

/// 役の早見表の下半分「点数の数え方」（#2723）。符と飜から点数が決まる流れと、子・親の早見表。
///
/// **数字は `MahjongScoring.basePoints` / `payments` から計算する**。表を手で書き写すと、精算側の式を
/// 直したときに表だけ古くなるので、精算と同じ関数を通す。
enum MahjongPointsGuide {
    /// 早見表に並べる符と飜。25 符は七対子（2 飜以上）、20 符は平和のツモで、ロンの表には出さない。
    static let fuRows = [25, 30, 40, 50, 60, 70]
    static let hanColumns = [1, 2, 3, 4]

    /// 満貫以上の行。`han` はその区分に入る代表の飜数。
    struct LimitRow: Identifiable {
        let name: String
        let hanText: String
        let han: Int
        var id: String { name }
    }

    static var limitRows: [LimitRow] {
        [
            LimitRow(name: tr("満貫"), hanText: tr("5飜（4飜40符・3飜70符から）"), han: 5),
            LimitRow(name: tr("跳満"), hanText: tr("6〜7飜"), han: 6),
            LimitRow(name: tr("倍満"), hanText: tr("8〜10飜"), han: 8),
            LimitRow(name: tr("三倍満"), hanText: tr("11〜12飜"), han: 11),
            LimitRow(name: tr("数え役満"), hanText: tr("13飜以上"), han: 13),
        ]
    }

    /// 符と飜の組み合わせの支払い。成立しない組み合わせ（25 符 1 飜）は nil。
    static func payment(han: Int, fu: Int, isDealer: Bool, isTsumo: Bool) -> (ron: Int, fromDealer: Int, fromNonDealer: Int)? {
        if fu == 25 && han < 2 { return nil }
        let base = MahjongScoring.basePoints(han: han, fu: fu, yakumanCount: 0).0
        let p = MahjongScoring.payments(base: base, isDealer: isDealer, isTsumo: isTsumo)
        return (p.ron, p.fromDealer, p.fromNonDealer)
    }

    static func ronText(han: Int, fu: Int, isDealer: Bool) -> String {
        payment(han: han, fu: fu, isDealer: isDealer, isTsumo: false).map { "\($0.ron)" } ?? "–"
    }

    /// 役満のロン（1 つ分）。
    static func yakumanRon(isDealer: Bool) -> Int {
        let base = MahjongScoring.basePoints(han: 13, fu: 0, yakumanCount: 1).0
        return MahjongScoring.payments(base: base, isDealer: isDealer, isTsumo: false).ron
    }

    /// ツモの表記。子の和了は「親の支払い / 子の支払い」、親の和了は「全員から同額」。
    static func tsumoText(han: Int, isDealer: Bool) -> String {
        let base = MahjongScoring.basePoints(han: han, fu: 30, yakumanCount: 0).0
        let p = MahjongScoring.payments(base: base, isDealer: isDealer, isTsumo: true)
        return isDealer ? tr("%lld点オール", p.fromNonDealer) : "\(p.fromDealer) / \(p.fromNonDealer)"
    }
}

/// 「点数の数え方」の見た目。`MahjongYakuSheet` の中に並べる。
struct MahjongPointsGuideView: View {
    var body: some View {
        YakuTableSection(
            header: tr("点数の数え方"),
            footer: tr("支払いは100点単位に切り上げます。このアプリでは、4飜30符・3飜60符などの「切り上げ満貫」はありません。")
        ) {
            step(tr("① 符を数える"),
                 tr("20符から始めて足します。門前でロン +10、ツモ +2、刻子（ポン・暗刻）は明刻 2・暗刻 4（1・9・字牌は倍）、槓は明槓 8・暗槓 16（1・9・字牌は倍）、役牌の雀頭 +2（自風と場風が同じ連風牌は +4）、嵌張・辺張・単騎待ち +2。最後に10符単位へ切り上げます。七対子は25符固定、平和はツモ20符・ロン30符です。"))
            step(tr("② 基本点を出す"),
                 tr("基本点 ＝ 符 × 2^(飜+2)。2000を超える（満貫以上）と、飜数で決まった基本点になります。"))
            step(tr("③ 支払いを出す"),
                 tr("ロンは、子なら基本点×4、親なら基本点×6。ツモは、子の和了なら親が基本点×2・子が基本点×1ずつ、親の和了なら全員が基本点×2ずつ払います。"))
        }
        YakuTableSection(header: tr("満貫以上の点数")) {
            limitTable
        }
        YakuTableSection(header: tr("子のロン（符 × 飜）")) {
            ronTable(isDealer: false)
        }
        YakuTableSection(
            header: tr("親のロン（符 × 飜）"),
            footer: tr("25符は七対子（2飜以上）です。20符は平和のツモだけなので、ロンの表にはありません。")
        ) {
            ronTable(isDealer: true)
        }
    }

    private func step(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .scaledFont(14, weight: .bold, design: .rounded)
                .foregroundStyle(Theme.ink)
            Text(detail)
                .scaledFont(12, design: .rounded)
                .foregroundStyle(Theme.inkSubText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var limitTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MahjongPointsGuide.limitRows) { row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.name)
                            .scaledFont(14, weight: .bold, design: .rounded)
                            .foregroundStyle(Theme.ink)
                        Text(row.hanText)
                            .scaledFont(11, weight: .medium, design: .rounded)
                            .foregroundStyle(Theme.inkSubText)
                    }
                    ForEach(limitLines(han: row.han), id: \.self) { line in
                        Text(line)
                            .scaledFont(12, weight: .heavy, design: .rounded)
                            .foregroundStyle(Theme.coralText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Text(tr("役満は %1$lld点（子）・%2$lld点（親）。複数そろうと倍になります。",
                    MahjongPointsGuide.yakumanRon(isDealer: false), MahjongPointsGuide.yakumanRon(isDealer: true)))
                .scaledFont(12, design: .rounded)
                .foregroundStyle(Theme.inkSubText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func limitLines(han: Int) -> [String] {
        [
            tr("子: ロン %1$@ ・ ツモ %2$@",
               MahjongPointsGuide.ronText(han: han, fu: 30, isDealer: false),
               MahjongPointsGuide.tsumoText(han: han, isDealer: false)),
            tr("親: ロン %1$@ ・ ツモ %2$@",
               MahjongPointsGuide.ronText(han: han, fu: 30, isDealer: true),
               MahjongPointsGuide.tsumoText(han: han, isDealer: true)),
        ]
    }

    private func ronTable(isDealer: Bool) -> some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                Text(tr("符"))
                    .gridColumnAlignment(.leading)
                ForEach(MahjongPointsGuide.hanColumns, id: \.self) { han in
                    Text(tr("%lld飜", han))
                        .gridColumnAlignment(.trailing)
                }
            }
            .scaledFont(11, weight: .bold, design: .rounded)
            .foregroundStyle(Theme.inkSubText)
            ForEach(MahjongPointsGuide.fuRows, id: \.self) { fu in
                GridRow {
                    Text(tr("%lld符", fu))
                        .scaledFont(12, weight: .bold, design: .rounded)
                        .foregroundStyle(Theme.ink)
                    ForEach(MahjongPointsGuide.hanColumns, id: \.self) { han in
                        Text(MahjongPointsGuide.ronText(han: han, fu: fu, isDealer: isDealer))
                            .scaledFont(12, weight: .heavy, design: .rounded)
                            .foregroundStyle(Theme.coralText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
