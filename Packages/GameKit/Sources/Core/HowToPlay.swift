import SwiftUI

/// 1 ゲームぶんの「遊び方」（#118）。
///
/// ルールは **3 行以内**、盤の近くに出すミニガイドは **1 行**に収める。遊ぶ前に長文を読ませる
/// 方式は #81 で却下されているため、これ以上の分量はシートの「くわしいルール」へ逃がす。
public struct HowToPlayGuide: Sendable, Equatable {
    /// `GameModule.id` と同じ ID。ミニガイドの表示済みフラグのキーに使う。
    public let gameID: String
    /// シートの見出し（例: 「将棋の遊び方」）。
    public let title: String
    /// ルール本文。3 行以内。
    public let lines: [String]
    /// 初回だけ盤の近くに出す 1 行。
    public let hint: String
    /// ミニガイドのアイコン（SF Symbols 名）。
    public let hintIcon: String

    public init(
        gameID: String,
        title: String,
        lines: [String],
        hint: String,
        hintIcon: String = "hand.tap.fill"
    ) {
        self.gameID = gameID
        self.title = title
        self.lines = lines
        self.hint = hint
        self.hintIcon = hintIcon
    }
}

// MARK: - 全ゲームの文言

public extension HowToPlayGuide {
    static let game2048 = HowToPlayGuide(
        gameID: "2048",
        title: "2048 の遊び方",
        lines: [
            "スワイプすると、すべてのタイルがその向きへ寄ります。",
            "同じ数字どうしがぶつかると合体して 2 倍になります。",
            "動かせなくなる前に 2048 のタイルを作れたらクリアです。",
        ],
        hint: "スワイプで動かそう",
        hintIcon: "hand.draw.fill"
    )

    static let shogi = HowToPlayGuide(
        gameID: "shogi",
        title: "将棋の遊び方",
        lines: [
            "自分の駒をタップすると、動けるマスが光ります。行きたいマスをタップで移動します。",
            "相手陣（奥から 3 段）に入ると駒を成れて、動きが強くなります。",
            "相手の玉将を追いつめたら勝ちです。",
        ],
        hint: "駒をタップ → 移動先をタップ"
    )

    static let chess = HowToPlayGuide(
        gameID: "chess",
        title: "チェスの遊び方",
        lines: [
            "自分の駒をタップすると、動けるマスが光ります。行きたいマスをタップで移動します。",
            "駒ごとに動き方が違います（ナイトは L 字、ビショップはななめ…）。「くわしいルール」で確認できます。",
            "相手のキングに王手をかけ、逃げ場をなくしたら勝ちです（王手が無いのに動けないときは引き分け）。",
        ],
        hint: "駒をタップ → 移動先をタップ"
    )

    static let gomoku = HowToPlayGuide(
        gameID: "gomoku",
        title: "五目並べの遊び方",
        lines: [
            "空いているマスをタップして石を置きます。",
            "たて・よこ・ななめのどれかで先に 5 つ並べたら勝ちです。",
            "相手が 4 つ並べたら、次の一手で止めましょう。",
        ],
        hint: "タップで石を置こう"
    )

    /// 「禁じ手（連珠ルール）」をオンにして対局しているときの五目並べ（#441）。
    ///
    /// `gameID` は `.gomoku` と同じ（同じゲームの表示違いなので、ミニガイドの
    /// 「一度見たら出さない」フラグも共有する）。そのため **`all` には入れない**
    /// ＝ 登録漏れ検査は `.gomoku` のほうで担保される。
    static let gomokuRenju = HowToPlayGuide(
        gameID: "gomoku",
        title: "五目並べの遊び方（禁じ手あり）",
        lines: [
            "空いているマスをタップして石を置きます。",
            "たて・よこ・ななめのどれかで先に 5 つ並べたら勝ちです。",
            "黒（先手）だけは禁じ手があり、三三・四四・長連（6 つ以上）になる場所には打てません。",
        ],
        hint: "黒は三三・四四・長連が打てない"
    )

    static let minesweeper = HowToPlayGuide(
        gameID: "minesweeper",
        title: "マインスイーパーの遊び方",
        lines: [
            "マスをタップして開きます。数字はまわり 8 マスにある地雷の数です。",
            "地雷がありそうなマスは長押しで旗を立てられます（旗のマスは開きません）。",
            "数字と同じ数だけ旗を立てたら、その数字をタップして周囲をまとめて開けます。地雷以外をすべて開けたらクリアです。",
        ],
        hint: "長押しで旗を立てられる",
        hintIcon: "flag.fill"
    )

    static let othello = HowToPlayGuide(
        gameID: "othello",
        title: "オセロの遊び方",
        lines: [
            "半透明の○が置けるマスです。タップして石を置きます。",
            "自分の石ではさんだ相手の石は、すべて自分の色に裏返ります。",
            "最後に石が多かったほうが勝ちです。",
        ],
        hint: "○のマスに置けるよ",
        hintIcon: "circle.dashed"
    )

    static let poker = HowToPlayGuide(
        gameID: "poker",
        title: "ポーカーの遊び方",
        lines: [
            "手札は 5 枚。残したいカードをタップで選びます。",
            "選ばなかったカードは 1 回だけ引き直せます。",
            "役の強い側がポットのチップをもらえます。",
        ],
        hint: "残すカードをタップしよう"
    )

    static let concentration = HowToPlayGuide(
        gameID: "concentration",
        title: "神経衰弱の遊び方",
        lines: [
            "カードを 2 枚めくり、同じ数字ならペアを取れて、もう一度めくれます。",
            "ちがったらカードは伏せられ、CPU の番になります。",
            "多くペアを取ったほうが勝ちです。",
        ],
        hint: "2 枚めくってペアを探そう"
    )

    static let blackjack = HowToPlayGuide(
        gameID: "blackjack",
        title: "ブラックジャックの遊び方",
        lines: [
            "チップを賭ける枚数（ベット）を選ぶと、カードが配られます。",
            "カードの合計を 21 に近づけたほうが勝ち。21 を超えると負けです。",
            "「ヒット」でもう 1 枚引き、「スタンド」でそこで止めます。最初の 2 枚では、賭けを倍にして 1 枚だけ引く「ダブルダウン」と、同じ点数の 2 枚（10・J・Q・K は同じ 10 点）を 2 手に分ける「スプリット」も選べます。",
        ],
        hint: "21 に近づけたほうが勝ち",
        hintIcon: "suit.spade.fill"
    )

    static let shiritori = HowToPlayGuide(
        gameID: "shiritori",
        title: "カードしりとりの遊び方",
        lines: [
            "場の札の読みの最後の字から始まる読みの札を選んで取ります。取った札が新しい場の札になり、CPUの番です。",
            "制限時間は60秒。しりとりが成立するたびに+10秒、成立しない札を選ぶと-5秒。「ん」で終わる読みを選ぶとその場で負けです。",
            "CPUが続けられなくなればあなたの勝ち、あなたが続けられなくなれば負けです。自分が取った札がノルマ（やさしい4枚・ふつう6枚・むずかしい9枚）に届いた瞬間も勝ちで、届かないまま時間切れになると負けです。",
        ],
        hint: "最後の字から始まる札を取ろう",
        hintIcon: "textformat.abc"
    )

    static let daifugo = HowToPlayGuide(
        gameID: "daifugo",
        title: "大富豪の遊び方",
        lines: [
            "場に出ている組より強い組を出します。手札を先になくした人が勝ちです。",
            "出せない・出したくないときはパス。全員パスすると場が流れます。",
            "3 が最弱で、2 とジョーカーが最強です。",
        ],
        hint: "場より強い組を出そう"
    )

    static let mahjongSolitaire = HowToPlayGuide(
        gameID: "mahjong",
        title: "麻雀ソリティアの遊び方",
        lines: [
            "同じ絵柄の牌を 2 枚タップすると消えます。",
            "取れるのは、上に牌が乗っておらず、左右どちらかが空いている牌だけです。",
            "すべての牌を消せたらクリアです。",
        ],
        hint: "同じ牌を 2 枚タップで消そう"
    )

    static let mahjong = HowToPlayGuide(
        gameID: "mahjong4",
        title: "麻雀の遊び方",
        lines: [
            "1 枚引いて 1 枚切ります。同じ牌 3 枚か連番 3 枚を 4 組と、同じ牌 2 枚を 1 組そろえたら和了です。",
            "和了の形でも役が無いと上がれません。聴牌したら立直を宣言すると役が付きます。",
            "CPU 3 人と東 1 局から東 4 局まで戦い、持ち点の多い順に順位が決まります。",
        ],
        hint: "切る牌をタップしよう"
    )

    static let sudoku = HowToPlayGuide(
        gameID: "sudoku",
        title: "ナンプレの遊び方",
        lines: [
            "マスをタップして選び、下の数字パッドで 1〜9 を入れます。",
            "たて 9 マス・よこ 9 マス・太線で囲んだ 3×3 のどれにも、同じ数字は 1 つまでです。",
            "空いているマスをすべて埋めたらクリアです。",
        ],
        hint: "マスを選んで数字を入れよう",
        hintIcon: "square.grid.3x3"
    )

    static let go = HowToPlayGuide(
        gameID: "go",
        title: "囲碁の遊び方",
        lines: [
            "線の交わるところをタップして、交互に石を置きます。",
            "相手の石をぐるりと囲むと取り上げられます。",
            "打つところが無くなったら「パス」。両者パスで終局し、盤上の石と囲んだ地の合計が多い方が勝ちです。",
        ],
        hint: "交点をタップして石を置こう",
        hintIcon: "circle.circle"
    )

    static let solitaire = HowToPlayGuide(
        gameID: "solitaire",
        // ハブでの表示名は「ソリティア」だが、遊びの正体（クロンダイク）はここで添える
        // （#397 の「開始シートにクロンダイクを添える」。開幕モーダルは #192 で廃止済みのため、
        //  遊ぶ前に読ませる唯一の面であるこのシートに寄せた）。
        title: "ソリティア（クロンダイク）の遊び方",
        lines: [
            "動かす札をタップして選び、置きたい列か右上の組札をタップします。",
            "場札は1つ小さくて色ちがいの札だけ重ねられます（黒の8 の上に 赤の7）。空いた列には K だけ置けます。",
            "♠♥♦♣ ごとに A から K まで組札に積み上げたらクリアです。",
        ],
        hint: "札をタップ → 置き先をタップ",
        hintIcon: "rectangle.stack.fill"
    )

    static let freecell = HowToPlayGuide(
        gameID: "freecell",
        title: "フリーセルの遊び方",
        lines: [
            "動かす札をタップして選び、置きたい列か、左上のフリーセル、右上の組札をタップします。",
            "場札は1つ小さくて色ちがいの札だけ重ねられます（黒の8 の上に 赤の7）。空いた列にはどの札でも置けます。",
            "♠♥♦♣ ごとに A から K まで組札に積み上げたらクリアです。52枚すべて最初から見えています。",
        ],
        hint: "札をタップ → 置き先をタップ",
        hintIcon: "rectangle.grid.1x2.fill"
    )

    static let spider = HowToPlayGuide(
        gameID: "spider",
        title: "スパイダーソリティアの遊び方",
        lines: [
            "動かす札をタップして選び、置きたい列をタップします。置けるのは、ひとつ上の札より1つ小さい札（スートは問いません）か、空いた列です。",
            "まとめて動かせるのは、同じスートで降順に揃った並びだけです。動かせる手が無くなったら左上の山札をタップして各列に1枚ずつ配ります（空いた列があると配れません）。",
            "同じスートで K から A まで13枚揃うと自動で取り除かれます。8組すべて取り除いたらクリアです。",
        ],
        hint: "札をタップ → 置き先をタップ",
        hintIcon: "rectangle.portrait.on.rectangle.portrait.angled.fill"
    )

    static let blockPuzzle = HowToPlayGuide(
        gameID: "blockpuzzle",
        title: "ブロックならべの遊び方",
        lines: [
            "下に出ている3つのピースを、盤の空いているところへドラッグして置きます。",
            "たて1列・よこ1行がすべて埋まると、その並びが消えて点になります。",
            "3つ置くと次の3つが出ます。どれも置けなくなったらゲームオーバーです。",
        ],
        hint: "ピースを盤へドラッグ",
        hintIcon: "hand.draw.fill"
    )

    static let blocks = HowToPlayGuide(
        gameID: "blocks",
        title: "ブロック崩しの遊び方",
        lines: [
            "指を横に動かした分だけパドルが動きます。指は盤の上でも盤の下の空いた場所でもよく、パドルに重ねなくて大丈夫です。タップすると球が飛び出します。",
            "球をはね返してブロックに当てます。灰色のブロックは壊れません。",
            "ときどき落ちてくるアイテムをパドルで受けると、パドルが伸びたり球が増えたりします。壊せるブロックを全部消すと次のステージへ。盤の球をすべて落とすと 1 ミスで、3 回で終わりです。",
        ],
        hint: "盤の下で指を横に動かしてパドルを操作",
        hintIcon: "hand.draw.fill"
    )

    /// 全ゲームぶん。テストで「登録漏れが無いか」を突き合わせるのに使う。
    static let runner = HowToPlayGuide(
        gameID: "runner",
        title: "チャリンコおじさんの遊び方",
        lines: [
            "画面をタップするとおじさんが走り出します。あとは自動で右へ進みます。",
            "タップでジャンプ。長く押すほど高く跳べるので、穴や障害物を跳び越えます。空中でもう一度タップすると二段ジャンプ。ペダルは地面でしか漕げないので、低く跳ぶほどスピードが乗って先へ進めます。",
            "ぶつかるか穴に落ちたらミス。何度でもステージの頭からやり直せます。青いチェックポイントより先で失敗した場合は、広告を見てそこから再開することもできます。",
        ],
        hint: "タップでジャンプ",
        hintIcon: "hand.tap.fill"
    )

    /// 花札こいこい（#495）。役の一覧は 3 行に収まらないので、対局中の「役」ボタンと
    /// 「くわしいルール」に送る。ここには**合わせ方**だけを書く。
    static let hanafuda = HowToPlayGuide(
        gameID: "hanafuda",
        title: "花札こいこいの遊び方",
        lines: [
            "手札を1枚選ぶと、場にある同じ月の札と合わせて取れます。左上の数字が月です。",
            "続けて山札が1枚めくれます。こちらも同じ月の札と合わさります。",
            "役ができたら「あがり」で得点、「こいこい」で続けて役を伸ばせます。",
        ],
        hint: "同じ月を合わせる",
        hintIcon: "leaf.fill"
    )

    static let fifteen = HowToPlayGuide(
        gameID: "fifteen",
        title: "15パズルの遊び方",
        lines: [
            "空白の隣にあるタイルをタップすると、空白へスライドします。",
            "空白と同じ列・行にあるタイルをタップすると、間のタイルをまとめて動かせます。",
            "1〜15 を左上から順に並べたらクリアです。手数が少ないほど良い記録です。",
        ],
        hint: "空白の隣をタップで動く",
        hintIcon: "square.grid.4x3.fill"
    )

    static let roulette = HowToPlayGuide(
        gameID: "roulette",
        title: "ルーレットの遊び方",
        lines: [
            "チップの額を選び、賭けたい場所（数字・赤黒・奇数偶数・1〜18 / 19〜36・12 個ずつの区分）をタップして置きます。何か所にも置けます。",
            "「スピン」でホイールが回り、玉の真下で止まったポケットの数字が出目です。",
            "配当は数字 1 点で 35 倍、12 個の区分で 2 倍、赤黒などは 1 倍（元金も戻ります）。0 は緑で、赤黒などの賭けはすべて外れです。",
        ],
        hint: "賭ける場所をタップしてスピン",
        hintIcon: "circle.circle.fill"
    )

    static let fruits = HowToPlayGuide(
        gameID: "fruits",
        title: "くっつきフルーツの遊び方",
        lines: [
            "箱の上で指を左右に動かして位置を決め、離すと果物が落ちます。",
            "同じ果物どうしが触れるとくっついて、1 つ大きい果物になります。いちばん大きいのはメロンです。",
            "上の点線より上に果物がとどまるとゲームオーバー。大きく育てて高得点を狙いましょう。",
        ],
        hint: "左右に動かして、離すと落ちる",
        hintIcon: "hand.draw.fill"
    )

    static let colorRelay = HowToPlayGuide(
        gameID: "colorrelay",
        title: "いろリレーの遊び方",
        lines: [
            "場の札と同じ色か、同じ数字・記号の札を出します。手札を先になくした人が勝ちです。",
            "出せる札がなければ山から 1 枚引きます。引いた札が出せるなら、そのまま出せます。",
            "とばし・ぎゃく・+2・いろがえ・いろがえ+4 の特殊札で流れを変えましょう。",
        ],
        hint: "同じ色か同じ数字の札を出そう",
        hintIcon: "rectangle.on.rectangle.angled"
    )

    static let anzan = HowToPlayGuide(
        gameID: "anzan",
        title: "ぱっと暗算の遊び方",
        lines: [
            "数が 1 つずつ、パッと出ては消えます。出た数を頭の中でぜんぶ足していきましょう。",
            "最後の数が消えたら、合計をテンキーで入力して「決定」。正解すると連続正解が伸びます。",
            "右上の「難易度」で桁数・個数・速さをそれぞれ選べます。まずは 1 桁・5 個から。",
        ],
        hint: "出た数をぜんぶ足そう",
        hintIcon: "sum"
    )

    static let backgammon = HowToPlayGuide(
        gameID: "backgammon",
        title: "バックギャモンの遊び方",
        lines: [
            "あなたは白。サイコロは自動で振られ、出た目のぶんだけ駒を右下の自陣へ向けて進めます。動かす駒 → 行き先の順にタップ。",
            "相手の駒が 2 個以上あるポイントには止まれません。1 個だけなら叩いてバー（中央）へ送れます。バーの駒は先に戻さないと他の駒を動かせません。",
            "15 個すべてが自陣（1〜6 ポイント）に入ったら、右端の置き場へ「あがり」。先に全部あげたほうの勝ちです。",
        ],
        hint: "動かす駒 → 行き先の順にタップ",
        hintIcon: "dice.fill"
    )

    static let speed = HowToPlayGuide(
        gameID: "speed",
        title: "スピードの遊び方",
        lines: [
            "台札は真ん中の2山。手札から、台札の数字と1つ違い（A と K もつながる）の札を、どちらかの台札に重ねます。順番はなく、CPU も同時に出してきます。",
            "出した札のぶん、山札から手札に補充されます。手札も山札も先に出し切ったほうの勝ちです。",
            "どちらも出せなくなったら「めくる」で、両方の山札から1枚ずつ台札に置きます。CPU の速さは右上の「速さ」で選べます。あなたの側に制限時間はありません。",
        ],
        hint: "台札と1つ違いの札を重ねよう",
        hintIcon: "hare.fill"
    )

    static let all: [HowToPlayGuide] = [
        .game2048, .shogi, .gomoku, .minesweeper, .othello,
        .poker, .concentration, .blackjack, .daifugo, .mahjongSolitaire, .mahjong,
        .sudoku, .go, .solitaire, .chess, .blocks, .freecell, .blockPuzzle, .runner,
        .hanafuda, .spider, .shiritori, .fifteen, .roulette, .fruits, .colorRelay, .anzan, .backgammon, .speed,
    ]
}

// MARK: - シート

/// `?` ボタンから開く「遊び方」シート。3 行の要点だけを見せ、詳細は `extra` へ押しやる。
public struct HowToPlaySheet<Extra: View>: View {
    private let guide: HowToPlayGuide
    private let extra: () -> Extra
    private let hasExtra: Bool
    @Environment(\.dismiss) private var dismiss

    public init(guide: HowToPlayGuide) where Extra == EmptyView {
        self.guide = guide
        self.extra = { EmptyView() }
        self.hasExtra = false
    }

    /// 役一覧や細かいルールなど、3 行に収まらない説明を持つゲーム用。
    public init(guide: HowToPlayGuide, @ViewBuilder extra: @escaping () -> Extra) {
        self.guide = guide
        self.extra = extra
        self.hasExtra = true
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(guide.lines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundStyle(Theme.onAccent)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Theme.Fill.coral))
                            Text(line)
                                .themeBody(15)
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .popCard(corner: Theme.cornerSmall)
                    }
                    if hasExtra {
                        NavigationLink {
                            extra()
                        } label: {
                            HStack {
                                Label("くわしいルール", systemImage: "book")
                                    .themeBody(15)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Theme.inkSub)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .popCard(corner: Theme.cornerSmall)
                        }
                        .foregroundStyle(Theme.ink)
                    }
                }
                .padding(Theme.pad)
            }
            .popBackground()
            .navigationTitle(guide.title)
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
        // 3 行だけのときは半分の高さで開き、盤を隠しすぎない。詳細を持つゲームは最初から全画面。
        .presentationDetents(hasExtra ? [.large] : [.medium, .large])
    }
}

// MARK: - くわしいルール

/// `HowToPlaySheet` の `extra` から開く「くわしいルール」ページ。見出しと本文の組をカードで縦に並べる（#829）。
///
/// ソリティア・フリーセル・スパイダー・大富豪・麻雀ソリティア・麻雀が同じ body を写しで持っていたので、
/// 組み方はここに 1 つだけ置く。**文言は各ゲームの `rules` に残す**（テストが文言そのものを検証するため）。
public struct RuleListSheet: View {
    private let title: LocalizedStringKey
    private let rules: [(String, String)]

    public init(title: LocalizedStringKey, rules: [(String, String)]) {
        self.title = title
        self.rules = rules
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(rules, id: \.0) { rule in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(rule.0)
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.coral)
                        Text(rule.1)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2))
                }
            }
            .padding(Theme.pad)
        }
        .popBackground()
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - ツールバーの `?` ボタン

private struct HowToPlayToolbar<Extra: View>: ViewModifier {
    let guide: HowToPlayGuide
    let extra: (() -> Extra)?
    var onPresent: (() -> Void)?
    var onDismiss: (() -> Void)?
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onPresent?()
                        isPresented = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("遊び方")
                }
            }
            .sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                if let extra {
                    HowToPlaySheet(guide: guide, extra: extra)
                } else {
                    HowToPlaySheet(guide: guide)
                }
            }
    }
}

public extension View {
    /// ツールバーに `?` ボタンを足し、タップで「遊び方」シートを開く。
    ///
    /// `onPresent` はシートを開く直前に呼ばれる。リアルタイム進行のゲームは
    /// ここで一時停止する（読んでいる間に落球する、を防ぐ。#510）。
    func howToPlay(
        _ guide: HowToPlayGuide,
        onPresent: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(HowToPlayToolbar<EmptyView>(guide: guide, extra: nil, onPresent: onPresent, onDismiss: onDismiss))
    }

    /// 詳細ページ付きの `?` ボタン（ポーカーの役一覧・大富豪のルール）。
    ///
    /// `onPresent` は詳細ページを持たない版と同じ意味（開く直前に呼ぶ。リアルタイム進行の
    /// ゲームはここで一時停止する）。
    func howToPlay<Extra: View>(
        _ guide: HowToPlayGuide,
        onPresent: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder extra: @escaping () -> Extra
    ) -> some View {
        modifier(HowToPlayToolbar(guide: guide, extra: extra, onPresent: onPresent, onDismiss: onDismiss))
    }
}

// MARK: - 初回のミニガイド

/// 盤の近くに 1 行だけ出す初回ガイド（#118）。
///
/// **モーダルではない**。ただのテキストなので操作を一切ブロックしない（タップも透過する）。
/// 表示済みかどうかは `PlayLog` に 1 キーで持ち、2 回目以降とアプリ再起動後は出さない。
/// `playLog` が nil の構成（テスト・プレビュー）では何も出さない。
public struct HowToPlayHint: View {
    private let guide: HowToPlayGuide
    @State private var isVisible: Bool

    public init(_ guide: HowToPlayGuide, playLog: PlayLog?) {
        self.guide = guide
        // 判定と「見せた」の記録を 1 回で済ませる（2 回目以降は false が返る）。この View が作られる
        // = そのゲームの画面が開かれた、なので `onAppear` を待たずにここで確定させてよい。
        // 何も出さないとき `.onAppear` が呼ばれない（EmptyView には付かない）のを避ける意味もある。
        // 再描画で init が呼び直されても `@State` が初回の判定を保つため、途中で消えたりしない。
        _isVisible = State(initialValue: playLog?.markGuideShown(for: guide.gameID) ?? false)
    }

    /// 出すかどうかを**呼び出し側が決める**版（#650）。
    ///
    /// 既定の初期化子は init で `markGuideShown` を消費するため、`ViewThatFits` のように
    /// 同じ列を複数回組み立てる画面では使えない（2 つめ以降の init が false を受け取り、
    /// あとから選ばれた枝に初回ヒントが出ない）。そういう画面では呼び出し側が
    /// 自分の `@State` で1回だけ判定し、その結果をここへ渡す。
    public init(_ guide: HowToPlayGuide, isVisible: Bool) {
        self.guide = guide
        _isVisible = State(initialValue: isVisible)
    }

    public var body: some View {
        if isVisible {
            Label(guide.hint, systemImage: guide.hintIcon)
                .themeBody(14)
                .foregroundStyle(Theme.inkSub)
                .allowsHitTesting(false)
        }
    }
}
