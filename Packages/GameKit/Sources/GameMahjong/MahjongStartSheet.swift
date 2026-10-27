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

    /// 「ルールと役を見る」の詳細。共通枠は NavigationStack を持たないので、入れ子のシートで開く。
    @State private var showRules = false
    /// ツモ・立直・鳴きの説明を開いているか。長さを切り替えても開閉はそのまま。
    @State private var showsDetails = false

    var body: some View {
        GameSetupSheet(kind: .versus, onboarding: MahjongOnboarding.guide(length: length), onStart: onStart, onCancel: onCancel) {
            GameSetupSection(tr("対局の長さ")) {
                HStack(spacing: 12) {
                    ForEach(MahjongGameLength.allCases) { option in
                        GameSetupChooser(
                            title: option.title, subtitle: "",
                            selected: length == option, accent: Theme.Fill.coral
                        ) { length = option }
                    }
                }
                Text(length.summary)
                    .scaledFont(12, weight: .medium, design: .rounded)
                    .foregroundStyle(Theme.inkSubText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 選んでいる長さの遊び方の要点を、図つきでそのまま並べる（#2044。荷物運びパズルの開始シート #2132 と
            // 同じ型・会長指示「遷移リンクを貼るだけでは駄目」）。カードは「？」の遊び方シートと同じ部品。
            GameSetupSection(tr("%@のルール", length.title)) {
                VStack(spacing: 10) {
                    ForEach(Array(length.setupKeyItems.enumerated()), id: \.offset) { _, item in
                        HowToPlayItemCard(item)
                    }
                    detailsToggle
                    if showsDetails {
                        ForEach(Array(length.setupDetailItems.enumerated()), id: \.offset) { _, item in
                            HowToPlayItemCard(item)
                        }
                        let notes = length.howToPlayGuide.notes
                        if !notes.isEmpty { HowToPlayNotesCard(notes) }
                    }
                }
                // 長さを切り替えたら、前の長さの図を引きずらずに丸ごと描き直す。
                .id(length)
            }

            Button { showRules = true } label: {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                    Text(tr("ルールと役を見る"))
                        .scaledFont(15, weight: .semibold, design: .rounded)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(Theme.inkSubText)
                }
                .foregroundStyle(Theme.coralText)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 3))
            }
            .buttonStyle(.pop)
        }
        .sheet(isPresented: $showRules) {
            NavigationStack {
                MahjongRuleSheet()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(tr("閉じる")) { showRules = false }
                        }
                    }
            }
        }
    }

    /// ツモ・立直・鳴きの説明を開閉する行。別画面へは移らず、この場で下に広げる（荷物運びパズルと同じ）。
    private var detailsToggle: some View {
        Button {
            withGameAnimation(.easeInOut(duration: 0.2)) { showsDetails.toggle() }
        } label: {
            HStack {
                Label(tr("ツモ・立直・鳴きのくわしい説明"), systemImage: "hand.tap.fill")
                    .themeBody(15)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .scaledFont(13, weight: .bold)
                    .foregroundStyle(Theme.inkSubText)
                    .rotationEffect(.degrees(showsDetails ? 180 : 0))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .popCard(corner: Theme.cornerSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pop)
        .foregroundStyle(Theme.ink)
        .accessibilityValue(showsDetails ? tr("開いている") : tr("閉じている"))
    }
}

// MARK: - Rule Sheet

struct MahjongRuleSheet: View {
    private var rules: [(String, String)] { [
        (tr("和了の形"), tr("同じ牌3枚（刻子）か連番3枚（順子）を4組と、同じ牌2枚（雀頭）を1組そろえると和了です。ほかに七対子（対子7組）と国士無双もあります")),
        (tr("ツモとロン"), tr("自分で引いた牌で和了すればツモ、他の人が切った牌で和了すればロンです")),
        (tr("役が要ります"), tr("和了の形になっても、役が1つも無いと和了できません。立直・断幺九・役牌などが役です")),
        (tr("立直"), tr("聴牌したら1000点を供託して宣言できます。以後は引いてきた牌をそのまま切ります（手牌は変えられません）。鳴いた手では宣言できません")),
        (tr("ポン・チー"), tr("同じ牌が2枚あれば誰の捨て牌でもポン、連番であと2枚そろうときは上家（左の人）の捨て牌をチーできます。鳴くとその牌を含む面子を手牌の外に晒し、そのまま自分の番になって1枚切ります")),
        (tr("カン"), tr("同じ牌4枚でカンできます。手の内の4枚なら暗槓、他の人の捨て牌でそろえば明槓、ポン済みの牌に4枚目を足せば加槓です。カンすると新しいドラがめくれ、王牌から1枚（嶺上牌）を引きます")),
        (tr("鳴くと何が変わるか"), tr("立直・門前清自摸和・平和・一盃口・七対子は付かなくなり、三色同順・一気通貫・チャンタ・混一色などは1飜下がります。役牌のように鳴いても付く役をねらいます。暗槓だけは門前のままです")),
        (tr("フリテン"), tr("自分の待ち牌を自分で捨てているとロンできません（ツモなら和了できます）")),
        (tr("流局"), tr("山が尽きたら流局。聴牌していた人が3000点を分け合い、ノーテンの人が払います")),
        (tr("東風戦"), tr("東1局から東4局までの4局。親が和了または聴牌で流局すると連荘します。流局のときは親が流れても本場が増えます")),
        (tr("一局戦"), tr("東1局だけを打って順位を決める短い対局です。親が和了っても連荘はせず、その局で終わります。成績は東風戦とは別に数えます")),
        (tr("採用していないルール"), tr("半荘戦・立直したあとのカン・食い替えの禁止・流し満貫は採用していません")),
    ] }

    var body: some View {
        RuleListSheet(rules: rules)
    }
}
