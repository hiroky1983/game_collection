import SwiftUI
import Core
import MahjongTiles

// MARK: - Start Sheet

struct MahjongStartSheet: View {
    /// 選んだ対局の長さ（#639）。ここで選んだものが `startGame(length:)` で焼き込まれる。
    @Binding var length: MahjongGameLength
    let onStart: () -> Void
    /// キャンセル（ハブへ戻る）。12本中この1本だけ「入ったら戻れない」状態だった（#352）。
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("対局の長さ")
                        .themeBody(15).foregroundStyle(Theme.inkSub)
                    // 他ゲームの開始シート（先手／後手・6局／12局など）と同じ大きめのタイルに揃える
                    // （会長指摘・2026-09-23。`.pickerStyle(.segmented)` は他より一回り小さく見えた）。
                    HStack(spacing: 12) {
                        ForEach(MahjongGameLength.allCases) { option in
                            GameSetupChooser(
                                title: option.title, subtitle: "",
                                selected: length == option, accent: Theme.Fill.coral
                            ) { length = option }
                        }
                    }
                    Text(length.summary)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 3))

                VStack(alignment: .leading, spacing: 8) {
                    Text("ゲームの流れ")
                        .themeBody(15).foregroundStyle(Theme.inkSub)
                    ruleRow("1", flowSummary)
                    ruleRow("2", "1枚ツモって1枚切る。4面子+雀頭で和了")
                    ruleRow("3", "聴牌したら立直できます（1000点を供託）。門前のときだけ")
                    ruleRow("4", "他の人の捨て牌はポン・チー・カンで鳴けます（鳴くと立直はできません）")
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 3))

                NavigationLink {
                    MahjongRuleSheet()
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("ルールと役を見る")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.inkSub)
                    }
                    .foregroundStyle(Theme.coral)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 3))
                }

                Spacer()
                Button {
                    onStart()
                } label: {
                    Text("対局開始").themeBody(18).frame(maxWidth: .infinity)
                    .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
            }
            .padding(Theme.pad)
            .popBackground()
            .navigationTitle("麻雀")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
            }
        }
        .presentationDetents([.large])
    }

    /// 選んだ長さに合わせた 1 行目。何局打つかは遊ぶ前にいちばん知りたい情報なので、
    /// ピッカーの説明文と流れの 1 行目の両方に出す。
    private var flowSummary: String {
        switch length {
        case .tonpuu:
            return "CPU3人と東風戦（東1局〜東4局）。持ち点は25000点から"
        case .singleHand:
            return "CPU3人と一局戦（東1局のみ）。持ち点は25000点から"
        }
    }

    private func ruleRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.Fill.coral))
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.ink)
            Spacer()
        }
    }
}

// MARK: - Rule Sheet

struct MahjongRuleSheet: View {
    private let rules: [(String, String)] = [
        ("和了の形", "同じ牌3枚（刻子）か連番3枚（順子）を4組と、同じ牌2枚（雀頭）を1組そろえると和了です。ほかに七対子（対子7組）と国士無双もあります"),
        ("ツモとロン", "自分で引いた牌で和了すればツモ、他の人が切った牌で和了すればロンです"),
        ("役が要ります", "和了の形になっても、役が1つも無いと和了できません。立直・断幺九・役牌などが役です"),
        ("立直", "聴牌したら1000点を供託して宣言できます。以後は引いてきた牌をそのまま切ります（手牌は変えられません）。鳴いた手では宣言できません"),
        ("ポン・チー", "同じ牌が2枚あれば誰の捨て牌でもポン、連番であと2枚そろうときは上家（左の人）の捨て牌をチーできます。鳴くとその牌を含む面子を手牌の外に晒し、そのまま自分の番になって1枚切ります"),
        ("カン", "同じ牌4枚でカンできます。手の内の4枚なら暗槓、他の人の捨て牌でそろえば明槓、ポン済みの牌に4枚目を足せば加槓です。カンすると新しいドラがめくれ、王牌から1枚（嶺上牌）を引きます"),
        ("鳴くと何が変わるか", "立直・門前清自摸和・平和・一盃口・七対子は付かなくなり、三色同順・一気通貫・チャンタ・混一色などは1飜下がります。役牌のように鳴いても付く役をねらいます。暗槓だけは門前のままです"),
        ("フリテン", "自分の待ち牌を自分で捨てているとロンできません（ツモなら和了できます）"),
        ("流局", "山が尽きたら流局。聴牌していた人が3000点を分け合い、ノーテンの人が払います"),
        ("東風戦", "東1局から東4局までの4局。親が和了または聴牌で流局すると連荘して本場が増えます"),
        ("一局戦", "東1局だけを打って順位を決める短い対局です。親が和了っても連荘はせず、その局で終わります。成績は東風戦とは別に数えます"),
        ("採用していないルール", "半荘戦・立直したあとのカン・食い替えの禁止・流し満貫は採用していません"),
    ]

    var body: some View {
        RuleListSheet(title: "ルールと役", rules: rules)
    }
}
