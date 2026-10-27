import SwiftUI

/// 1 ゲームぶんの「遊び方」（#118）。
///
/// ルールは **3 行以内**、盤の近くに出すミニガイドは **1 行**に収める。遊ぶ前に長文を読ませる
/// 方式は #81 で却下されているため、これ以上の分量はシートの「くわしいルール」へ逃がす。
///
/// 図入りの遊び方（#2044）を持つゲームは `items` に「短文 1〜2 行＋その図」を並べる。`items` がある
/// ゲームのシートは `lines` の代わりに番号付きの図カードを並べ、`notes` を末尾の文だけのカードに出す
/// （3 行ルールの制約 #81 は「文は項目ごとに 1〜2 行」に読み替える）。`lines` は要約として残す。
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
    /// 図入りの項目（#2044）。空ならシートは `lines` を並べる（従来どおり）。
    public let items: [HowToPlayItem]
    /// 図に入らない補足。`items` のあとに文だけのカードで出す。
    public let notes: [String]
    /// 図で見る「はじめての遊び方」（#2827）。持つゲームだけ、シートの先頭に入口のボタンが出る。
    public let onboarding: OnboardingGuide?

    public init(
        gameID: String,
        title: String,
        lines: [String],
        hint: String,
        hintIcon: String = "hand.tap.fill",
        items: [HowToPlayItem] = [],
        notes: [String] = [],
        onboarding: OnboardingGuide? = nil
    ) {
        self.gameID = gameID
        self.title = title
        self.lines = lines
        self.hint = hint
        self.hintIcon = hintIcon
        self.items = items
        self.notes = notes
        self.onboarding = onboarding
    }

    /// 「はじめての遊び方」（#2827）を持たせた版を返す。
    public func onboarding(_ guide: OnboardingGuide) -> HowToPlayGuide {
        HowToPlayGuide(
            gameID: gameID, title: title, lines: lines, hint: hint, hintIcon: hintIcon,
            items: items, notes: notes, onboarding: guide
        )
    }

    /// 項目に図を差し込んだ版を返す。図の View はゲーム側のモジュールにあるので、文言は Core、
    /// 図はゲーム側で持つ。`figures` は `items` と同じ順・同じ数で渡す。
    public func illustrated(_ figures: [@MainActor @Sendable () -> AnyView]) -> HowToPlayGuide {
        precondition(figures.count == items.count,
                     "\(gameID): 図の数（\(figures.count)）が項目の数（\(items.count)）と合わない")
        return HowToPlayGuide(
            gameID: gameID, title: title, lines: lines, hint: hint, hintIcon: hintIcon,
            items: zip(items, figures).map { HowToPlayItem($0.text, figure: $1) },
            notes: notes, onboarding: onboarding
        )
    }

    /// 図（クロージャ）は比べられないので、文言と「図があるか」で比べる。
    public static func == (lhs: HowToPlayGuide, rhs: HowToPlayGuide) -> Bool {
        lhs.gameID == rhs.gameID && lhs.title == rhs.title && lhs.lines == rhs.lines
            && lhs.hint == rhs.hint && lhs.hintIcon == rhs.hintIcon
            && lhs.items == rhs.items && lhs.notes == rhs.notes && lhs.onboarding == rhs.onboarding
    }
}

/// 図入りの遊び方の 1 項目（#2044）。短文 1〜2 行と、その下に出す図。
public struct HowToPlayItem: Sendable, Equatable {
    /// 項目の文。1〜2 行に収める。
    public let text: String
    /// 文の下に出す図。nil なら文だけ。
    public let figure: (@MainActor @Sendable () -> AnyView)?

    public init(_ text: String, figure: (@MainActor @Sendable () -> AnyView)? = nil) {
        self.text = text
        self.figure = figure
    }

    public static func == (lhs: HowToPlayItem, rhs: HowToPlayItem) -> Bool {
        lhs.text == rhs.text && (lhs.figure == nil) == (rhs.figure == nil)
    }
}

// MARK: - 全ゲームの文言

public extension HowToPlayGuide {
    static var game2048: HowToPlayGuide { HowToPlayGuide(
        gameID: "2048",
        title: tr("2048 の遊び方"),
        lines: [
            tr("スワイプすると、すべてのタイルがその向きへ寄ります。"),
            tr("同じ数字どうしがぶつかると合体して 2 倍になります。"),
            tr("動かせなくなる前に 2048 のタイルを作れたらクリアです。"),
        ],
        hint: tr("スワイプで動かそう"),
        hintIcon: "hand.draw.fill",
        items: [
            HowToPlayItem(tr("スワイプすると、すべてのタイルがその向きへ寄ります。")),
            HowToPlayItem(tr("同じ数字どうしがぶつかると合体して 2 倍になります。")),
            HowToPlayItem(tr("2048 のタイルを作れたらクリアです。")),
        ],
        notes: [
            tr("動かすたびに、空いたマスに新しいタイルが 1 枚出ます。どこにも動かせなくなったら終わりです。"),
        ]
    ) }

    static var shogi: HowToPlayGuide { HowToPlayGuide(
        gameID: "shogi",
        title: tr("将棋の遊び方"),
        lines: [
            tr("自分の駒をタップすると、動けるマスが光ります。行きたいマスをタップで移動します。"),
            tr("相手陣（奥から 3 段）に入ると駒を成れて、動きが強くなります。"),
            tr("相手の王将（王）を追いつめたら勝ちです。"),
        ],
        hint: tr("駒をタップ → 移動先をタップ"),
        items: [
            HowToPlayItem(tr("自分の駒をタップすると、動けるマスが光ります。行きたいマスをタップで移動します。")),
            HowToPlayItem(tr("相手の駒があるマスへ動くと、その駒を取れます。取った駒は持ち駒になり、あとで好きなマスに打てます。")),
            HowToPlayItem(tr("相手陣（奥から 3 段）に入ると駒を成れて、動きが強くなります。")),
            HowToPlayItem(tr("相手の王将（王）を追いつめたら勝ちです。")),
        ],
        notes: [
            tr("駒ごとの動き方は、盤の駒をタップすると光るマスで確かめられます。"),
            tr("手合いで「飛車落ち」「角落ち」を選ぶと、上手（盤の上側）がその駒を外して始まります。上手が先に指します。自分が落とすか、CPU が落とすかを選べます。"),
        ]
    ) }

    static var chess: HowToPlayGuide { HowToPlayGuide(
        gameID: "chess",
        title: tr("チェスの遊び方"),
        lines: [
            tr("自分の駒をタップすると、動けるマスが光ります。行きたいマスをタップで移動します。"),
            tr("駒ごとに動き方が違います（ナイトは L 字、ビショップはななめ…）。「くわしいルール」で確認できます。"),
            tr("相手のキングに王手をかけ、逃げ場をなくしたら勝ちです（王手が無いのに動けないときは引き分け）。"),
        ],
        hint: tr("駒をタップ → 移動先をタップ"),
        items: [
            HowToPlayItem(tr("自分の駒をタップすると、動けるマスが光ります。行きたいマスをタップで移動します。")),
            HowToPlayItem(tr("駒ごとに動き方が違います。ナイトは L 字、ビショップはななめ、ルークはたてよこです。")),
            HowToPlayItem(tr("相手のキングに王手をかけ、逃げ場をなくしたら勝ちです。")),
        ],
        notes: [
            tr("王手が無いのに動けないときは引き分けです。"),
            tr("ほかの駒の動きや特別ルールは「くわしいルール」で見られます。"),
        ]
    ) }

    static var gomoku: HowToPlayGuide { HowToPlayGuide(
        gameID: "gomoku",
        title: tr("五目並べの遊び方"),
        lines: [
            tr("空いているマスをタップして石を置きます。"),
            tr("たて・よこ・ななめのどれかで先に 5 つ並べたら勝ちです。"),
            tr("相手が 4 つ並べたら、次の一手で止めましょう。"),
        ],
        hint: tr("タップで石を置こう"),
        items: [
            HowToPlayItem(tr("空いているマスをタップして、黒と白が交互に石を置きます。")),
            HowToPlayItem(tr("たて・よこ・ななめのどれかで先に 5 つ並べたら勝ちです。")),
            HowToPlayItem(tr("相手が 4 つ並べたら、次の一手で止めましょう。")),
        ],
        notes: []
    ) }

    /// 「禁じ手（連珠ルール）」をオンにして対局しているときの五目並べ（#441）。
    ///
    /// `gameID` は `.gomoku` と同じ（同じゲームの表示違いなので、ミニガイドの
    /// 「一度見たら出さない」フラグも共有する）。そのため **`all` には入れない**
    /// ＝ 登録漏れ検査は `.gomoku` のほうで担保される。
    static var gomokuRenju: HowToPlayGuide { HowToPlayGuide(
        gameID: "gomoku",
        title: tr("五目並べの遊び方（禁じ手あり）"),
        lines: [
            tr("空いているマスをタップして石を置きます。"),
            tr("たて・よこ・ななめのどれかで先に 5 つ並べたら勝ちです。"),
            tr("黒（先手）だけは禁じ手があり、三三・四四・長連（6 つ以上）になる場所には打てません。"),
        ],
        hint: tr("黒は三三・四四・長連が打てない"),
        items: [
            HowToPlayItem(tr("空いているマスをタップして、黒と白が交互に石を置きます。")),
            HowToPlayItem(tr("たて・よこ・ななめのどれかで先に 5 つ並べたら勝ちです。")),
            HowToPlayItem(tr("黒（先手）だけは禁じ手があり、三三・四四・長連（6 つ以上）になる場所には打てません。")),
        ],
        notes: [
            tr("三三は、あと 1 つで 3 つ並ぶ列が 2 本できる手です。四四は 4 つの列が 2 本できる手です。"),
        ]
    ) }

    static var minesweeper: HowToPlayGuide { HowToPlayGuide(
        gameID: "minesweeper",
        title: tr("マインスイーパーの遊び方"),
        lines: [
            tr("マスをタップして開きます。数字はまわり 8 マスにある地雷の数です。"),
            tr("地雷がありそうなマスは長押しで旗を立てられます（旗のマスは開きません）。"),
            tr("数字と同じ数だけ旗を立てたら、その数字をタップして周囲をまとめて開けます。地雷以外をすべて開けたらクリアです。"),
        ],
        hint: tr("長押しで旗を立てられる"),
        hintIcon: "flag.fill",
        items: [
            HowToPlayItem(tr("マスをタップして開きます。数字はまわり 8 マスにある地雷の数です。")),
            HowToPlayItem(tr("地雷がありそうなマスは、長押しで旗を立てられます。")),
            HowToPlayItem(tr("数字と同じ数だけ旗を立てたら、その数字をタップしてまわりをまとめて開けます。")),
            HowToPlayItem(tr("地雷以外のマスをすべて開けたらクリアです。")),
        ],
        notes: [
            tr("旗を立てたマスはタップしても開きません。"),
        ]
    ) }

    static var othello: HowToPlayGuide { HowToPlayGuide(
        gameID: "othello",
        title: tr("オセロの遊び方"),
        lines: [
            tr("半透明の○が置けるマスです。タップして石を置きます。"),
            tr("自分の石ではさんだ相手の石は、すべて自分の色に裏返ります。"),
            tr("最後に石が多かったほうが勝ちです。"),
        ],
        hint: tr("○のマスに置けるよ"),
        hintIcon: "circle.dashed",
        items: [
            HowToPlayItem(tr("半透明の○が置けるマスです。タップして石を置きます。")),
            HowToPlayItem(tr("自分の石ではさんだ相手の石は、すべて自分の色に裏返ります。")),
            HowToPlayItem(tr("最後に石が多かったほうが勝ちです。")),
        ],
        notes: [
            tr("お互い置けなくなって空きマスが残ったときは、残ったマスは勝った方に加算されます。"),
        ]
    ) }

    static var poker: HowToPlayGuide { HowToPlayGuide(
        gameID: "poker",
        title: tr("ポーカーの遊び方"),
        lines: [
            tr("手札は 5 枚。入れ替えたいカードをタップで選びます。"),
            tr("選んだカードを引き直せます。"),
            tr("10 回勝負。勝った回は自分の役の点が入ります。"),
        ],
        hint: tr("入れ替えるカードをタップしよう"),
        items: [
            HowToPlayItem(tr("手札は 5 枚。入れ替えたいカードをタップで選びます。")),
            HowToPlayItem(tr("選んだカードを引き直せます。")),
            HowToPlayItem(tr("CPU と手札を見せ合い、役の強い側がその回の勝ちです。")),
            HowToPlayItem(tr("10 回勝負。勝った回は自分の役の点が入り、合計点の多い側が勝ちです。")),
        ],
        notes: [
            tr("役の一覧は「くわしいルール」、点数は「役の点数表」で見られます。"),
            tr("広告を見ると、10 回のうち 1 度だけもう 1 回カードを交換できます。"),
        ]
    ) }

    static var concentration: HowToPlayGuide { HowToPlayGuide(
        gameID: "concentration",
        title: tr("神経衰弱の遊び方"),
        lines: [
            tr("カードを 2 枚めくり、同じ絵柄ならペアを取れて、もう一度めくれます。"),
            tr("ちがったらカードは伏せられ、CPU の番になります。"),
            tr("多くペアを取ったほうが勝ちです。"),
        ],
        hint: tr("2 枚めくってペアを探そう"),
        items: [
            HowToPlayItem(tr("カードを 2 枚めくります。同じ絵柄ならペアになり、もう一度めくれます。")),
            HowToPlayItem(tr("ちがったらカードは伏せられ、CPU の番になります。")),
            HowToPlayItem(tr("多くペアを取ったほうが勝ちです。")),
        ],
        notes: []
    ) }

    static var blackjack: HowToPlayGuide { HowToPlayGuide(
        gameID: "blackjack",
        title: tr("ブラックジャックの遊び方"),
        lines: [
            tr("ディーラーと 10 回勝負します。勝てば 1 点、最初の 2 枚の 21（ブラックジャック）で勝てば 2 点。10 回の合計が自己ベストになります。"),
            tr("カードの合計を 21 に近づけたほうが勝ち。21 を超えると負けです。"),
            tr("「ヒット」でもう 1 枚引き、「スタンド」でそこで止めます。最初の 2 枚が同じ点数（10・J・Q・K は同じ 10 点）なら、2 手に分ける「スプリット」も選べます。分けた手はそれぞれ勝てば 1 点です。"),
        ],
        hint: tr("21 に近づけたほうが勝ち"),
        hintIcon: "suit.spade.fill",
        items: [
            HowToPlayItem(tr("カードの合計を 21 に近づけたほうが勝ち。21 を超えると負けです。")),
            HowToPlayItem(tr("A は 1 か 11、J・Q・K は 10 点で数えます。")),
            HowToPlayItem(tr("「ヒット」でもう 1 枚引き、「スタンド」でそこで止めます。")),
            HowToPlayItem(tr("最初の 2 枚が同じ点数なら、2 手に分ける「スプリット」もできます。")),
        ],
        notes: [
            tr("ディーラーと 10 回勝負。勝てば 1 点、ブラックジャックで勝てば 2 点で、10 回の合計が自己ベストになります。"),
            tr("10・J・Q・K は同じ 10 点なので、スプリットできます。分けた手はそれぞれ勝てば 1 点です。"),
            tr("負けた回は、広告を見て 1 回だけやり直せます。"),
        ]
    ) }

    /// カードしりとりのノルマ（いつもの遊び方）。とことんは `.shiritoriEndless`（`gameID` が同じなので `all` には
    /// 入れない。五目並べの禁じ手と同じ作法）。「？」と開始シートは遊び方で出し分ける（#2044）。
    static var shiritori: HowToPlayGuide { shiritori(
        goal: tr("取った札がノルマの枚数に届いたら勝ち。届かないまま時間切れになると負けです。"),
        notes: [
            tr("ノルマは かんたん 4 枚・ふつう 6 枚・むずかしい 9 枚です。"),
            tr("「ん」で終わる読みの札を選ぶと、その場で負けです。"),
        ]
    ) }

    /// カードしりとりのとことん（ノルマなし）。
    static var shiritoriEndless: HowToPlayGuide { shiritori(
        goal: tr("ノルマは無く、札が尽きるまで続きます。全部の札を取りきればパーフェクトで勝ち。"),
        notes: [
            tr("札を取った場所には、山札から新しい札が出ます。時間切れは負けです。"),
            tr("「ん」で終わる読みの札を選ぶと、その場で負けです。"),
        ]
    ) }

    private static func shiritori(goal: String, notes: [String]) -> HowToPlayGuide { HowToPlayGuide(
        gameID: "shiritori",
        title: tr("カードしりとりの遊び方"),
        lines: [
            tr("場の札の読みの最後の字から始まる読みの札を選んで取ります。取った札が新しい場の札になり、CPUの番です。"),
            tr("制限時間は60秒。しりとりが成立するたびに+10秒、成立しない札を選ぶと-5秒。「ん」で終わる読みを選ぶとその場で負けです。"),
            tr("CPUが続けられなくなればあなたの勝ち、あなたが続けられなくなれば負けです。自分が取った札がノルマ（かんたん4枚・ふつう6枚・むずかしい9枚）に届いた瞬間も勝ちで、届かないまま時間切れになると負けです。「とことん」はノルマが無く、札が尽きるまで続きます（取った場所には山札から新しい札が出ます）。全部の札を取りきればパーフェクトで勝ちです。"),
        ],
        hint: tr("最後の字から始まる札を取ろう"),
        hintIcon: "textformat.abc",
        items: [
            HowToPlayItem(goal),
            HowToPlayItem(tr("場の札の読みの最後の字から始まる札を選んで取ります。")),
            HowToPlayItem(tr("取った札が新しい場の札になり、CPU の番になります。")),
            HowToPlayItem(tr("制限時間は 60 秒。しりとりが成立すると +10 秒、成立しない札を選ぶと -5 秒。")),
            HowToPlayItem(tr("CPU が続けられなくなったら勝ち、あなたが続けられなくなったら負けです。")),
        ],
        notes: notes
    ) }

    static var daifugo: HowToPlayGuide { HowToPlayGuide(
        gameID: "daifugo",
        title: tr("大富豪の遊び方"),
        lines: [
            tr("場に出ている組より強い組を出します。手札を先になくした人が勝ちです。"),
            tr("出せない・出したくないときはパス。全員パスすると場が流れます。"),
            tr("3 が最弱で、2 とジョーカーが最強です。"),
        ],
        hint: tr("場より強い組を出そう"),
        items: [
            HowToPlayItem(tr("場に出ている組より強い組を出します。手札を先になくした人が勝ちです。")),
            HowToPlayItem(tr("3 が最弱で、2 とジョーカーが最強です。")),
            HowToPlayItem(tr("出せない・出したくないときはパス。全員パスすると場が流れます。")),
        ],
        notes: [
            tr("同じ数字を 4 枚以上まとめて出すと革命。カードの強さが逆になります。"),
            tr("8 を含む組を出すと場が流れ、そのまま続けて出せます。"),
            tr("そのほかの決まりは「くわしいルール」で見られます。"),
        ]
    ) }

    static var mahjongSolitaire: HowToPlayGuide { HowToPlayGuide(
        gameID: "mahjong",
        title: tr("麻雀ソリティアの遊び方"),
        lines: [
            tr("同じ絵柄の牌を 2 枚タップすると消えます。"),
            tr("取れるのは、上に牌が乗っておらず、左右どちらかが空いている牌だけです。"),
            tr("すべての牌を消せたらクリアです。"),
        ],
        hint: tr("同じ牌を 2 枚タップで消そう"),
        items: [
            HowToPlayItem(tr("同じ絵柄の牌を 2 枚タップすると消えます。")),
            HowToPlayItem(tr("取れるのは、上に牌が乗っておらず、左右どちらかが空いている牌だけです。")),
            HowToPlayItem(tr("花牌どうし・季節牌どうしは、絵柄がちがってもペアになります。")),
            HowToPlayItem(tr("すべての牌を消せたらクリアです。")),
        ],
        notes: [
            tr("盤面のかたちは 3 種類。どれも必ず取り切れるように配ります。"),
            tr("ヒント・並べ替え・戻すの使い方は「くわしいルール」で見られます。"),
        ]
    ) }

    /// 東風戦（東 1 局〜東 4 局）の麻雀。一局戦は `.mahjongSingleHand`（`gameID` が同じなので `all` に入れない。
    /// 五目並べの禁じ手・荷物運びパズルのパズルモードと同じ作法）。「？」と開始シートは対局の長さで出し分ける。
    static var mahjong: HowToPlayGuide { mahjong(flow: tr("CPU 3 人と東 1 局から東 4 局まで戦い、持ち点の多い順に順位が決まります。")) }

    /// 一局戦（東 1 局だけ・#639）の麻雀。
    static var mahjongSingleHand: HowToPlayGuide { mahjong(flow: tr("CPU 3 人と東 1 局だけを戦い、持ち点の多い順に順位が決まります。")) }

    private static func mahjong(flow: String) -> HowToPlayGuide { HowToPlayGuide(
        gameID: "mahjong4",
        title: tr("麻雀の遊び方"),
        lines: [
            tr("1 枚引いて 1 枚切ります。同じ牌 3 枚か連番 3 枚を 4 組と、同じ牌 2 枚を 1 組そろえたら和了です。"),
            tr("和了の形でも役が無いと上がれません。聴牌したら立直を宣言すると役が付きます。"),
            flow,
        ],
        hint: tr("切る牌をタップしよう"),
        items: [
            HowToPlayItem(flow),
            HowToPlayItem(tr("1 枚引いて 1 枚切ります。切る牌はタップで選びます。")),
            HowToPlayItem(tr("同じ牌 3 枚か連番 3 枚を 4 組と、同じ牌 2 枚を 1 組そろえたら和了です。")),
            HowToPlayItem(tr("和了の形でも役が無いと上がれません。聴牌したら立直を宣言すると役が付きます。")),
            HowToPlayItem(tr("他の人の捨て牌は、ポン・チー・カンで鳴いて取れます。")),
        ],
        notes: [
            tr("立直できるのは鳴いていない手だけで、1000 点を供託します。"),
            tr("役の一覧は、画面上の「役の早見表」と「くわしいルール」で見られます。"),
        ]
    ) }

    static var sudoku: HowToPlayGuide { HowToPlayGuide(
        gameID: "sudoku",
        title: tr("ナンプレの遊び方"),
        lines: [
            tr("マスをタップして選び、下の数字パッドで 1〜9 を入れます。"),
            tr("たて 9 マス・よこ 9 マス・太線で囲んだ 3×3 のどれにも、同じ数字は 1 つまでです。"),
            tr("空いているマスをすべて埋めたらクリアです。"),
        ],
        hint: tr("マスを選んで数字を入れよう"),
        hintIcon: "square.grid.3x3",
        items: [
            HowToPlayItem(tr("マスをタップして選び、下の数字パッドで 1〜9 を入れます。")),
            HowToPlayItem(tr("たての列・よこの行・太線の 3×3 のどれにも、同じ数字は 1 つまでです。")),
            HowToPlayItem(tr("空いているマスをすべて埋めたらクリアです。")),
        ],
        notes: []
    ) }

    static var go: HowToPlayGuide { HowToPlayGuide(
        gameID: "go",
        title: tr("囲碁の遊び方"),
        lines: [
            tr("線の交わるところをタップして、交互に石を置きます。"),
            tr("相手の石をぐるりと囲むと取り上げられます。"),
            tr("打つところが無くなったら「パス」。両者パスで終局し、盤上の石と囲んだ地の合計が多い方が勝ちです。"),
        ],
        hint: tr("交点をタップして石を置こう"),
        hintIcon: "circle.circle",
        items: [
            HowToPlayItem(tr("線の交わるところをタップして、黒と白が交互に石を置きます。")),
            HowToPlayItem(tr("相手の石をぐるりと囲むと取り上げられます。")),
            HowToPlayItem(tr("打つところが無くなったら「パス」。両者パスで終局し、盤上の石と囲んだ地の合計が多い方が勝ちです。")),
        ],
        notes: [
            tr("コウや数え方など、細かい決まりは「くわしいルール」で見られます。"),
        ]
    ) }

    static var solitaire: HowToPlayGuide { HowToPlayGuide(
        gameID: "solitaire",
        // ハブでの表示名は「ソリティア」だが、遊びの正体（クロンダイク）はここで添える
        // （#397 の「開始シートにクロンダイクを添える」。開幕モーダルは #192 で廃止済みのため、
        //  遊ぶ前に読ませる唯一の面であるこのシートに寄せた）。
        title: tr("ソリティア（クロンダイク）の遊び方"),
        lines: [
            tr("動かす札をタップして選び、置きたい列か右上の組札をタップします。"),
            tr("場札は1つ小さくて色ちがいの札だけ重ねられます（黒の8 の上に 赤の7）。空いた列には K だけ置けます。"),
            tr("♠♥♦♣ ごとに A から K まで組札に積み上げたらクリアです。"),
        ],
        hint: tr("札をタップ → 置き先をタップ"),
        hintIcon: "rectangle.stack.fill",
        items: [
            HowToPlayItem(tr("動かす札をタップして選び、置きたい列か右上の組札をタップします。")),
            HowToPlayItem(tr("場札は 1 つ小さくて色ちがいの札だけ重ねられます。")),
            HowToPlayItem(tr("空いた列には K だけ置けます。")),
            HowToPlayItem(tr("♠♥♦♣ ごとに A から K まで組札に積み上げたらクリアです。")),
        ],
        notes: [
            tr("山札をタップすると、選んだ枚数（1 枚か 3 枚）をめくれます。"),
        ]
    ) }

    static var freecell: HowToPlayGuide { HowToPlayGuide(
        gameID: "freecell",
        title: tr("フリーセルの遊び方"),
        lines: [
            tr("動かす札をタップして選び、置きたい列か、左上のフリーセル、右上の組札をタップします。"),
            tr("場札は1つ小さくて色ちがいの札だけ重ねられます（黒の8 の上に 赤の7）。空いた列にはどの札でも置けます。"),
            tr("♠♥♦♣ ごとに A から K まで組札に積み上げたらクリアです。52枚すべて最初から見えています。"),
        ],
        hint: tr("札をタップ → 置き先をタップ"),
        hintIcon: "rectangle.grid.1x2.fill",
        items: [
            HowToPlayItem(tr("動かす札をタップして選び、置きたい列かフリーセル、組札をタップします。")),
            HowToPlayItem(tr("フリーセルは札を 1 枚ずつ置いておける空きです。左上に 4 つあります。")),
            HowToPlayItem(tr("場札は 1 つ小さくて色ちがいの札だけ重ねられます。空いた列にはどの札でも置けます。")),
            HowToPlayItem(tr("♠♥♦♣ ごとに A から K まで組札に積み上げたらクリアです。")),
        ],
        notes: [
            tr("52 枚すべて最初から見えています。"),
        ]
    ) }

    static var spider: HowToPlayGuide { HowToPlayGuide(
        gameID: "spider",
        title: tr("スパイダーソリティアの遊び方"),
        lines: [
            tr("動かす札をタップして選び、置きたい列をタップします。置けるのは、ひとつ上の札より1つ小さい札（スートは問いません）か、空いた列です。"),
            tr("まとめて動かせるのは、同じスートで降順に揃った並びだけです。動かせる手が無くなったら左上の山札をタップして各列に1枚ずつ配ります（空いた列があると配れません）。"),
            tr("同じスートで K から A まで13枚揃うと自動で取り除かれます。8組すべて取り除いたらクリアです。"),
        ],
        hint: tr("札をタップ → 置き先をタップ"),
        hintIcon: "rectangle.portrait.on.rectangle.portrait.angled.fill",
        items: [
            HowToPlayItem(tr("動かす札をタップして選び、置きたい列をタップします。")),
            HowToPlayItem(tr("置けるのは、ひとつ上の札より 1 つ小さい札（スートは問いません）か、空いた列です。")),
            HowToPlayItem(tr("まとめて動かせるのは、同じスートで降順に揃った並びだけです。")),
            HowToPlayItem(tr("動かせる手が無くなったら左上の山札をタップ。各列に 1 枚ずつ配ります。")),
            HowToPlayItem(tr("同じスートで K から A まで 13 枚揃うと自動で取り除かれ、8 組取り除いたらクリアです。")),
        ],
        notes: [
            tr("空いた列があると、山札は配れません。"),
        ]
    ) }

    static var blocks: HowToPlayGuide { HowToPlayGuide(
        gameID: "blocks",
        title: tr("ブロック崩しの遊び方"),
        lines: [
            tr("指を横に動かした分だけパドルが動きます。指は盤の上でも盤の下の空いた場所でもよく、パドルに重ねなくて大丈夫です。タップすると球が飛び出します。"),
            tr("球をはね返してブロックに当てます。灰色のブロックは壊れません。"),
            tr("ときどき落ちてくるアイテムをパドルで受けると、パドルが伸びたり球が増えたりします。壊せるブロックを全部消すと次のステージへ。盤の球をすべて落とすと 1 ミスで、3 回で終わりです。"),
        ],
        hint: tr("盤の下で指を横に動かしてパドルを操作"),
        hintIcon: "hand.draw.fill",
        items: [
            HowToPlayItem(tr("指を横に動かした分だけパドルが動きます。タップで球が飛び出します。")),
            HowToPlayItem(tr("球をはね返してブロックに当てます。灰色のブロックは壊れません。")),
            HowToPlayItem(tr("落ちてくるアイテムをパドルで受けると、パドルが伸びたり球が増えたりします。")),
            HowToPlayItem(tr("壊せるブロックを全部消すと次のステージへ進みます。")),
            HowToPlayItem(tr("盤の球をすべて落とすと 1 ミス。3 回ミスで終わりです。")),
        ],
        notes: [
            tr("指は盤の上でも盤の下の空いた場所でもよく、パドルに重ねなくて大丈夫です。"),
        ]
    ) }

    /// チャリンコおじさんのステージ制（いつもの遊び方）。エンドレスは `.runnerEndless`（`gameID` が同じなので
    /// `all` には入れない。五目並べの禁じ手と同じ作法）。「？」と開始シートはモードで出し分ける（#2044）。
    static var runner: HowToPlayGuide { runner(
        goal: tr("ゴールまで走ればステージクリア。面を順にクリアして、先の世界へ進みます。"),
        miss: tr("ぶつかるか穴に落ちたらミス。何度でもステージの頭からやり直せます。"),
        lastLine: tr("ぶつかるか穴に落ちたらミス。何度でもステージの頭からやり直せます。青いチェックポイントより先で失敗した場合は、広告を見てそこから再開することもできます。"),
        notes: [
            tr("青いチェックポイントより先でミスしたときは、広告を見てそこから再開することもできます。"),
            tr("ペダルは地面でしか漕げないので、低く跳ぶほどスピードが乗ります。"),
            tr("鳥は近づくと飛び立ちます。跳ばずに走ったまま、下を抜けましょう。"),
            tr("スピードアップのアイテムを取ると、しばらく速くなります。"),
            tr("たこ焼きを取ると、3 秒だけ障害にぶつからなくなります。"),
        ]
    ) }

    /// チャリンコおじさんのエンドレス（#675）。
    static var runnerEndless: HowToPlayGuide { runner(
        goal: tr("毎回ちがうコースを、ミスするまで走ります。走った距離が記録です。"),
        miss: tr("ぶつかるか穴に落ちたらおしまい。途中で閉じると記録は残りません。"),
        lastLine: tr("ぶつかるか穴に落ちたらおしまい。途中で閉じると記録は残りません。"),
        notes: [
            tr("ペダルは地面でしか漕げないので、低く跳ぶほどスピードが乗ります。"),
            tr("鳥は近づくと飛び立ちます。跳ばずに走ったまま、下を抜けましょう。"),
            tr("スピードアップのアイテムを取ると、しばらく速くなります。"),
            tr("たこ焼きを取ると、3 秒だけ障害にぶつからなくなります。"),
        ]
    ) }

    private static func runner(goal: String, miss: String, lastLine: String, notes: [String]) -> HowToPlayGuide { HowToPlayGuide(
        gameID: "runner",
        title: tr("チャリンコおじさんの遊び方"),
        lines: [
            tr("画面をタップするとおじさんが走り出します。あとは自動で右へ進みます。"),
            tr("タップでジャンプ。長く押すほど高く跳べるので、穴や障害物を跳び越えます。空中でもう一度タップすると二段ジャンプ。ペダルは地面でしか漕げないので、低く跳ぶほどスピードが乗って先へ進めます。"),
            lastLine,
        ],
        hint: tr("タップでジャンプ"),
        hintIcon: "hand.tap.fill",
        items: [
            HowToPlayItem(goal),
            HowToPlayItem(tr("画面をタップするとおじさんが走り出し、あとは自動で右へ進みます。")),
            HowToPlayItem(tr("タップでジャンプ。長く押すほど高く跳べます。")),
            HowToPlayItem(tr("空中でもう一度タップすると、二段ジャンプできます。")),
            HowToPlayItem(miss),
        ],
        notes: notes
    ) }

    /// 花札こいこい（#495）。役の一覧は 3 行に収まらないので、対局中の「役」ボタンと
    /// 「くわしいルール」に送る。ここには**合わせ方**だけを書く。
    static var hanafuda: HowToPlayGuide { HowToPlayGuide(
        gameID: "hanafuda",
        title: tr("花札こいこいの遊び方"),
        lines: [
            tr("手札を1枚選ぶと、場にある同じ月の札と合わせて取れます。左上の数字が月です。"),
            tr("続けて山札が1枚めくれます。こちらも同じ月の札と合わさります。"),
            tr("役ができたら「あがり」で得点、「こいこい」で続けて役を伸ばせます。"),
        ],
        hint: tr("同じ月を合わせる"),
        hintIcon: "leaf.fill",
        items: [
            HowToPlayItem(tr("札は 12 か月が 4 枚ずつ。札の左上の数字が月です。")),
            HowToPlayItem(tr("手札を 1 枚選ぶと、場にある同じ月の札と合わせて取れます。")),
            HowToPlayItem(tr("続けて山札が 1 枚めくれます。こちらも同じ月の札と合わさります。")),
            HowToPlayItem(tr("役ができたら「あがり」で得点、「こいこい」で続けて役を伸ばせます。")),
        ],
        notes: [
            tr("こいこいのあとに相手にあがられると、相手の得点が 2 倍になります。"),
            tr("役の一覧は、画面上の「役の早見表」と「くわしいルール」で見られます。"),
        ]
    ) }

    static var fifteen: HowToPlayGuide { HowToPlayGuide(
        gameID: "fifteen",
        title: tr("15パズルの遊び方"),
        lines: [
            tr("空白の隣にあるタイルをタップすると、空白へスライドします。"),
            tr("空白と同じ列・行にあるタイルをタップすると、間のタイルをまとめて動かせます。"),
            tr("1〜15 を左上から順に並べたらクリアです。手数が少ないほど良い記録です。"),
        ],
        hint: tr("空白の隣をタップで動く"),
        hintIcon: "square.grid.4x3.fill",
        items: [
            HowToPlayItem(tr("空白の隣にあるタイルをタップすると、空白へスライドします。")),
            HowToPlayItem(tr("空白と同じ列・行のタイルをタップすると、間のタイルをまとめて動かせます。")),
            HowToPlayItem(tr("1〜15 を左上から順に並べたらクリアです。")),
        ],
        notes: [
            tr("手数が少ないほど良い記録です。"),
        ]
    ) }

    /// 明かり消しパズル（#1883・企画倉庫）。図は `GameAkariKeshi` 側で `illustrated(_:)` を使って差し込む。
    static var akariKeshi: HowToPlayGuide { HowToPlayGuide(
        gameID: "akarikeshi",
        title: tr("明かり消しパズルの遊び方"),
        lines: [
            tr("マスを押すと、そのマスと上下左右の明かりが入れ替わります（点いていれば消え、消えていれば点く）。"),
            tr("盤の端や角では、盤の中にある隣だけが入れ替わります。"),
            tr("明かりをぜんぶ消したらクリア。最短の手数に近いほど良い記録です。"),
        ],
        hint: tr("押すと上下左右も入れ替わる"),
        hintIcon: "lightbulb.fill",
        items: [
            HowToPlayItem(tr("マスを押すと、そのマスと上下左右の明かりが入れ替わります。")),
            HowToPlayItem(tr("盤の端や角では、盤の中にある隣だけが入れ替わります。")),
            HowToPlayItem(tr("明かりをぜんぶ消したらクリアです。")),
        ],
        notes: [
            tr("押す順番は関係ありません。同じマスを 2 回押すと元に戻ります。"),
            tr("難易度は 3 段階で、最短の手数（4・7・10 手）が変わります。少ない手数ほど良い記録です。"),
        ]
    ) }

    static var fruits: HowToPlayGuide { HowToPlayGuide(
        gameID: "fruits",
        title: tr("おじさんの盆栽の遊び方"),
        lines: [
            tr("指を左右に動かすと、縁側のおじさんが盆栽を持って付いてきます。離すとその真下の庭へ落とします。"),
            tr("同じ盆栽どうしが触れるとくっついて、1 つ立派な盆栽になります。いちばん立派なのは金の松です。"),
            tr("上の点線より上に盆栽がとどまるとゲームオーバー。立派に育てて高得点を狙いましょう。"),
        ],
        hint: tr("左右に動かして、離すと落ちる"),
        hintIcon: "hand.draw.fill",
        items: [
            HowToPlayItem(tr("指を左右に動かすと、縁側のおじさんが盆栽を持って付いてきます。")),
            HowToPlayItem(tr("指を離すと、その真下の庭へ盆栽が落ちます。")),
            HowToPlayItem(tr("同じ盆栽どうしが触れるとくっついて、1 つ立派な盆栽になります。")),
            HowToPlayItem(tr("盆栽は 11 種類。いちばん立派なのは金の松です。")),
            HowToPlayItem(tr("上の点線より上に盆栽がとどまると、ゲームオーバーです。")),
        ],
        notes: [
            tr("立派に育てるほど高得点です。"),
        ]
    ) }

    static var colorRelay: HowToPlayGuide { HowToPlayGuide(
        gameID: "colorrelay",
        title: tr("いろリレーの遊び方"),
        lines: [
            tr("場の札と同じ色か、同じ数字・記号の札を出します。手札を先になくした人が勝ちです。"),
            tr("出せる札がなければ山から 1 枚引きます。引いた札が出せるなら、そのまま出せます。"),
            tr("とばし・ぎゃく・+2・いろがえ・いろがえ+4 の特殊札で流れを変えましょう。"),
        ],
        hint: tr("同じ色か同じ数字の札を出そう"),
        hintIcon: "rectangle.on.rectangle.angled",
        items: [
            HowToPlayItem(tr("場の札と同じ色か、同じ数字・記号の札を出せます。")),
            HowToPlayItem(tr("出せる札がなければ、山から 1 枚引きます。引いた札が出せるなら、そのまま出せます。")),
            HowToPlayItem(tr("とばしは次の人の番を飛ばし、ぎゃくは回る向きを逆にします。")),
            HowToPlayItem(tr("+2 は、次の人が 2 枚引いて番を飛ばされます。")),
            HowToPlayItem(tr("いろがえはどの札の上にも出せて、次の色を選べます。いろがえ+4 は次の人が 4 枚引きます。")),
            HowToPlayItem(tr("手札を先になくした人が勝ちです。")),
        ]
    ) }

    static var anzan: HowToPlayGuide { HowToPlayGuide(
        gameID: "anzan",
        title: tr("ぱっと暗算の遊び方"),
        lines: [
            tr("数が 1 つずつ、パッと出ては消えます。出た数を頭の中でぜんぶ足していきましょう。"),
            tr("最後の数が消えたら、合計をテンキーで入力して「決定」。正解すると連続正解が伸びます。"),
            tr("右上の「難易度」で桁数・個数・速さをそれぞれ選べます。まずは 1 桁・5 個から。"),
        ],
        hint: tr("出た数をぜんぶ足そう"),
        hintIcon: "sum",
        items: [
            HowToPlayItem(tr("数が 1 つずつ、パッと出ては消えます。")),
            HowToPlayItem(tr("出た数を、頭の中でぜんぶ足していきましょう。")),
            HowToPlayItem(tr("最後の数が消えたら、合計をテンキーで入力して「決定」。")),
            HowToPlayItem(tr("右上の「難易度」で、桁数・個数・速さをそれぞれ選べます。")),
        ],
        notes: [
            tr("正解すると連続正解が伸びます。まずは 1 桁・5 個から。"),
        ]
    ) }

    static var backgammon: HowToPlayGuide { HowToPlayGuide(
        gameID: "backgammon",
        title: tr("バックギャモンの遊び方"),
        lines: [
            tr("あなたは白。サイコロは自動で振られ、出た目のぶんだけ駒を右下の自陣へ向けて進めます。動かす駒 → 行き先の順にタップ。"),
            tr("相手の駒が 2 個以上あるポイントには止まれません。1 個だけなら叩いてバー（中央）へ送れます。バーの駒は先に戻さないと他の駒を動かせません。"),
            tr("15 個すべてが自陣（1〜6 ポイント）に入ったら、右端の置き場へ「あがり」。先に全部あげたほうの勝ちです。"),
        ],
        hint: tr("動かす駒 → 行き先の順にタップ"),
        hintIcon: "dice.fill",
        items: [
            HowToPlayItem(tr("あなたは白。サイコロの目のぶん、駒を右下の自陣へ向けて進めます。")),
            HowToPlayItem(tr("動かす駒 → 行き先の順にタップします。")),
            HowToPlayItem(tr("相手の駒が 2 個以上あるポイントには止まれません。")),
            HowToPlayItem(tr("相手の駒が 1 個だけなら、叩いてバー（中央）へ送れます。")),
            HowToPlayItem(tr("15 個すべてが自陣（1〜6 ポイント）に入ったら、右端の置き場へ「あがり」。")),
        ],
        notes: [
            tr("バーに自分の駒があるときは、先にその駒を盤へ戻さないと、他の駒を動かせません。"),
            tr("先に 15 個すべてをあげたほうの勝ちです。"),
        ]
    ) }

    /// マンカラ（#1626・企画倉庫）。図は `GameMancala` 側で `illustrated(_:)` を使って差し込む。
    static var mancala: HowToPlayGuide { HowToPlayGuide(
        gameID: "mancala",
        title: tr("マンカラの遊び方"),
        lines: [
            tr("手前の 6 つの穴があなたの陣地。穴をタップすると、中の種を右どなりから 1 個ずつ反時計回りにまきます。"),
            tr("最後の 1 個が自分のストア（右端）に入ればもう一度。自分の空の穴に入れば、向かいの種もまとめて取れます。"),
            tr("どちらかの側の穴が空になったら終わり。ストアの種が多いほうの勝ちです。"),
        ],
        hint: tr("手前の穴をタップして種をまこう"),
        items: [
            HowToPlayItem(tr("手前の穴をタップすると、中の種を右どなりから 1 個ずつまきます。")),
            HowToPlayItem(tr("最後の 1 個が自分のストア（右端）に入ったら、もう一度あなたの番。")),
            HowToPlayItem(tr("最後の 1 個が自分の空の穴に入ると、向かいの種もまとめて取れます。")),
            HowToPlayItem(tr("片側の穴がすべて空になったら終わり。ストアの種が多いほうの勝ちです。")),
        ],
        notes: [
            tr("種は反時計回りにまき、相手のストアは飛ばします。"),
            tr("終わったとき穴に残った種は、その側のストアに入ります。"),
        ]
    ) }

    /// 四目並べ（#1738・企画倉庫）。図は `GameYonmoku` 側で `illustrated(_:)` を使って差し込む。
    static var yonmoku: HowToPlayGuide { HowToPlayGuide(
        gameID: "yonmoku",
        title: tr("四目並べの遊び方"),
        lines: [
            tr("列をタップすると、石が上から落ちて、その列の一番下の空きに入ります。"),
            tr("たて・よこ・ななめのどれかで先に 4 つ並べたら勝ちです。"),
            tr("相手が 3 つ並べたら、4 つ目の場所を先にふさぎましょう。"),
        ],
        hint: tr("列をタップして石を落とそう"),
        items: [
            HowToPlayItem(tr("列をタップすると、石が上から落ちて、その列の一番下の空きに入ります。")),
            HowToPlayItem(tr("たて・よこ・ななめのどれかで先に 4 つ並べたら勝ちです。")),
            HowToPlayItem(tr("相手が 3 つ並べたら、4 つ目の場所を先にふさぎましょう。")),
        ],
        notes: [
            tr("黒が先手です。盤が全部埋まったら引き分けです。"),
        ]
    ) }

    /// サイコロ役づくり（#1752・企画倉庫）。図は `GameDiceCombo` 側で `illustrated(_:)` を使って差し込む。
    static var diceCombo: HowToPlayGuide { HowToPlayGuide(
        gameID: "dicecombo",
        title: tr("サイコロ役づくりの遊び方"),
        lines: [
            tr("「振る」でサイコロ 5 個を振ります。残したい目はタップでキープし、1 ターンに 3 回まで振れます。"),
            tr("得点表の役を 1 つタップして点を入れるとターン終了。条件に合わない役に入れると 0 点です。"),
            tr("12 の役をぜんぶ埋めたら終わり。1〜6 の目の小計が 63 点以上ならボーナス +35 点です。"),
        ],
        hint: tr("残したい目をタップでキープ"),
        hintIcon: "dice.fill",
        items: [
            HowToPlayItem(tr("「振る」でサイコロ 5 個を振ります。1 ターンに 3 回まで振れます。")),
            HowToPlayItem(tr("残したい目をタップするとキープ。キープした目は振り直しません。")),
            HowToPlayItem(tr("得点表の役をタップして点を入れるとターン終了。条件に合わない役は 0 点です。")),
            HowToPlayItem(tr("ストレートは目が続く並び、ファイブダイスは 5 個とも同じ目です。")),
            HowToPlayItem(tr("1〜6 の目の小計が 63 点以上なら、ボーナス +35 点。")),
        ],
        notes: [
            tr("12 の役をぜんぶ埋めたら終わり。合計点で自己ベストを目指そう。"),
            tr("フォーダイス・フルハウスは 5 個の合計が点になります（5 個とも同じ目もフルハウスに数えます）。"),
        ]
    ) }

    static var speed: HowToPlayGuide { HowToPlayGuide(
        gameID: "speed",
        title: tr("スピードの遊び方"),
        lines: [
            tr("台札は真ん中の2山。台札の数字と1つ違い（A と K もつながる）の手札を、重ねたい台札のほうへ払って出します。順番はなく、CPU も同時に出してきます。"),
            tr("出した札のぶん、山札から手札に補充されます。手札も山札も先に出し切ったほうの勝ちです。"),
            tr("どちらも出せなくなったら「めくる」で、両方の山札から1枚ずつ台札に置きます。CPU の速さは右上の「＋」で始めるときに選べます。あなたの側に制限時間はありません。"),
        ],
        hint: tr("1つ違いの札を台札のほうへ払おう"),
        hintIcon: "hare.fill",
        items: [
            HowToPlayItem(tr("台札は真ん中の 2 山。数字が 1 つ違いの札を、どちらかの台札に重ねます。")),
            HowToPlayItem(tr("手札の札を、出したい台札のほうへ払うと出せます。台札の上まで動かして離しても出せます。")),
            HowToPlayItem(tr("A と K もつながります。マークは関係ありません。")),
            HowToPlayItem(tr("順番はなく、CPU も同時に出してきます。出したぶん、山札から手札に補充されます。")),
            HowToPlayItem(tr("どちらも出せなくなったら「めくる」。両方の山札から 1 枚ずつ台札に置きます。")),
            HowToPlayItem(tr("手札も山札も先に出し切ったほうの勝ち。山札が無くなったら、めくらずに手札を出し切れば勝ちです。")),
        ],
        notes: [
            tr("出せない札を払うと手札に戻ります（ペナルティはありません）。"),
            tr("CPU の速さは、右上の「＋」で始めるときに選べます。あなたの側に制限時間はありません。"),
        ]
    ) }

    /// ババ抜き（#1577・企画倉庫）。図は `GameOldMaid` 側で `illustrated(_:)` を使って差し込む。
    static var oldMaid: HowToPlayGuide { HowToPlayGuide(
        gameID: "oldmaid",
        title: tr("ババ抜きの遊び方"),
        lines: [
            tr("配られた手札から同じ数字の 2 枚（ペア）を捨てて始めます。ジョーカーはペアになりません。"),
            tr("自分の番では、次の CPU の伏せた札を 1 枚選んで引きます。ペアができたら捨て、手札がなくなったら抜けられます。"),
            tr("最後にジョーカーを持って残った人が負けです。札を選ぶと、CPU の顔に出ることがあります。"),
        ],
        hint: tr("引く札を選んで、CPU の顔をよく見よう"),
        hintIcon: "theatermasks.fill",
        items: [
            HowToPlayItem(tr("同じ数字の 2 枚（ペア）は捨てます。配られた手札のペアは最初に捨ててから始めます。")),
            HowToPlayItem(tr("自分の番では、次の CPU の伏せた札を 1 枚選んで引きます。ペアができたら捨てます。")),
            HowToPlayItem(tr("札を選ぶと、ジョーカーを持つ CPU は顔に出ることがあります。にやりとしたらジョーカーかも。")),
            HowToPlayItem(tr("手札がなくなった人から抜けていき、最後にジョーカーを持って残った人が負けです。")),
        ],
        notes: [
            tr("引いたジョーカーは手札の右端に入り、CPU に場所を見られます。「シャッフル」で並びを混ぜましょう。"),
            tr("CPU の強さは右上の「新規対局」から 4 段階で選べます。強いほど顔に出にくく、置き場所をよく覚えます。"),
        ]
    ) }

    /// ハーツ（Issue #1884・企画倉庫）。図は `GameHearts` 側で `illustrated(_:)` を使って差し込む。
    static var hearts: HowToPlayGuide { HowToPlayGuide(
        gameID: "hearts",
        title: tr("ハーツの遊び方"),
        lines: [
            tr("取らないゲームです。点が少ないほど勝ちで、ハートは 1 点、スペードの Q は 13 点です。"),
            tr("最初に出たマークと同じマークのうち、数字がいちばん大きい人が 4 枚を取ります。A が最強、2 が最弱です。"),
            tr("だれかが 50 点に届いたら終わり。合計の少ない人が勝ちです。"),
        ],
        hint: tr("ハートとスペードのQを取らないように"),
        hintIcon: "suit.heart.fill",
        items: [
            HowToPlayItem(tr("札の強さは A がいちばん強く、2 がいちばん弱い。比べるのは同じマークの中だけです。")),
            HowToPlayItem(tr("最初に出たマークと同じマークで、いちばん強い札を出した人が 4 枚を取ります。別のマークは A でも勝てません。")),
            HowToPlayItem(tr("取った札のハートは 1 枚 1 点、スペードの Q は 13 点。点は少ないほど勝ち、取らないゲームです。")),
            HowToPlayItem(tr("13 枚ずつ配られます。まず 3 枚を選んで、左どなりへ渡します。")),
            HowToPlayItem(tr("最初はクラブの 2 から。出された札と同じマークを、順に 1 枚ずつ出します。")),
            HowToPlayItem(tr("同じマークが無いときは、どの札でも出せます。点の札を押し付けるチャンス。")),
            HowToPlayItem(tr("だれかが 50 点に届いたら終わり。合計の少ない人が勝ちです。")),
        ],
        notes: [
            tr("ハートは、だれかが場に出すまで先頭に出せません（手札がハートだけなら出せます）。"),
            tr("1 巡目はハートとスペードの Q を出せません（それしか無いときは出せます）。"),
            tr("札の強さと点数は、対局中にヘッダーのボタンから見られます。CPU の強さは「新規対局」で選べます。"),
        ]
    ) }

    /// 線つなぎ（#2235・企画倉庫）。図は `GameTsunagi` 側で `illustrated(_:)` を使って差し込む。
    static var tsunagi: HowToPlayGuide { HowToPlayGuide(
        gameID: "tsunagi",
        title: tr("線つなぎの遊び方"),
        lines: [
            tr("同じ数字の点どうしを、指でなぞって線でつなぎます。"),
            tr("線は交差できません。別の線に触れると、その線はそこで切れます。"),
            tr("全部の数字をつなぎ、全マスを線で埋めたらクリアです。"),
        ],
        hint: tr("同じ数字の点を、なぞってつなごう"),
        hintIcon: "point.topleft.down.to.point.bottomright.curvepath.fill",
        items: [
            HowToPlayItem(tr("同じ数字の点どうしを、指でなぞって線でつなぎます。")),
            HowToPlayItem(tr("線は交差できません。別の線に触れると、その線はそこで切れます。")),
            HowToPlayItem(tr("全部の数字をつなぎ、全マスを線で埋めたらクリアです。")),
        ],
        notes: [
            tr("線の途中から触ると、そこから引き直せます。"),
            tr("盤の大きさは 5×5 と 7×7 から選べます。どの問題も答えは 1 つです。"),
            tr("手数は、別の数字の線に持ち替えた回数です。少ないほど良い記録です。"),
        ]
    ) }

    /// ハノイの塔（#2003・企画倉庫）。図は `GameHanoi` 側で `illustrated(_:)` を使って差し込む。
    static var hanoi: HowToPlayGuide { HowToPlayGuide(
        gameID: "hanoi",
        title: tr("ハノイの塔の遊び方"),
        lines: [
            tr("柱をタップすると、いちばん上の円盤を取ります。別の柱をタップすると、そこへ置きます。"),
            tr("大きい円盤は、小さい円盤の上には置けません。"),
            tr("左の柱の円盤を全部、右の柱へ移したらクリア。最少手数は 3 枚で 7 手、1 枚増えるごとに約 2 倍です。"),
        ],
        hint: tr("柱をタップして取り、別の柱に置く"),
        hintIcon: "square.stack.3d.up.fill",
        items: [
            HowToPlayItem(tr("柱をタップして、いちばん上の円盤を取ります。別の柱をタップすると置けます。")),
            HowToPlayItem(tr("大きい円盤は、小さい円盤の上には置けません。")),
            HowToPlayItem(tr("円盤を全部、右の柱へ移したらクリアです。")),
        ],
        notes: [
            tr("円盤は 3〜7 枚から選べます。最少手数は 3 枚で 7 手、1 枚増えるごとに約 2 倍です。"),
            tr("手数が少ないほど良い記録です。クリアまでのタイムも残ります。"),
        ]
    ) }

    /// おじさんちのねこさがし（#2250）。図は `GameCatPuzzle` 側で `illustrated(_:)` を使って差し込む。
    static var catPuzzle: HowToPlayGuide { HowToPlayGuide(
        gameID: "catpuzzle",
        title: tr("おじさんちのねこさがしの遊び方"),
        lines: [
            tr("おじさんの家の間取りに、飼い猫が隠れています。部屋・行・列のそれぞれに、猫がちょうど 1 匹ずついます。"),
            tr("猫どうしは、ななめも含めて隣り合いません。"),
            tr("マスをタップすると ×（いない）を付け外しし、ダブルタップでそのマスの猫を見つけます。全部の猫を見つけたらクリアです。"),
        ],
        hint: tr("部屋・行・列に猫を 1 匹ずつ。隣には置けない"),
        hintIcon: "cat.fill",
        items: [
            HowToPlayItem(tr("部屋・行・列のそれぞれに、猫がちょうど 1 匹ずついます。")),
            HowToPlayItem(tr("猫どうしは、ななめも含めて隣り合いません。")),
            HowToPlayItem(tr("タップで ×（いない）を付け外し、ダブルタップで猫を見つけます。全部見つけたらクリアです。")),
        ],
        notes: [
            tr("× の付け外しはミスになりません。答えでないマスをダブルタップすると、赤い × が付いてミスになります（赤い × は消せません）。ミスが 3 回になると終わりです。"),
            tr("盤は 6×6・7×7・8×8・9×9 の 4 段階で、問題は毎回変わります（答えは 1 通り）。"),
            tr("ヒントは 1 問につき 3 回まで。記録はクリアまでのタイムです。"),
        ]
    ) }

    static var homerun: HowToPlayGuide { HowToPlayGuide(
        gameID: "homerun",
        title: tr("柵越えおじさんの遊び方"),
        lines: [
            tr("1回の挑戦は10球。画面の下のほうを押したままずらすと、水色のミートカーソルが指の動きだけ動きます。"),
            tr("縮む輪が白い的に重なった瞬間に指を離すとスイング。カーソルをボールの少し下に置くと打球が上がり、左右と離す早さで方向が決まります。"),
            tr("合計飛距離を伸ばそう。挑戦は1日3回で、打席に立った時点で1回減ります（0:00 に戻ります）。"),
        ],
        hint: tr("押したままずらし、輪が的に重なった瞬間に離す"),
        hintIcon: "figure.baseball",
        items: [
            HowToPlayItem(tr("1 回の挑戦は 10 球。10 球の合計飛距離を伸ばそう。")),
            HowToPlayItem(tr("画面の下のほうを押したままずらすと、水色のミートカーソルが指の動きだけ動きます。")),
            HowToPlayItem(tr("縮む輪が白い的に重なった瞬間に指を離すと、スイングします。")),
            HowToPlayItem(tr("カーソルをボールの少し下に置くと打球が上がります。左右と離す早さで方向が決まります。")),
            HowToPlayItem(tr("挑戦は 1 日 3 回。打席に立った時点で 1 回減り、0:00 に戻ります。")),
        ],
        notes: [
            tr("回数が 0 のときは、広告を見て 1 回遊べます（1 日の本数に上限があります）。"),
        ]
    ) }

    /// 図入りの遊び方の最初のゲーム（#2044 の先駆け・会長決定 2026-10-12）。
    /// 図は `GameOjisanPuzzle` 側で `illustrated(_:)` を使って差し込む。
    ///
    /// 「？」は遊んでいるモードに合わせて出し分ける（会長指示 2026-10-12）。この `.ojisanPuzzleBackpain`
    /// は荷運びモード（表示名、enum ケース名・解析の `mode` 値は旧名の `backpain` のまま）用で、
    /// 登録漏れ検査（`HowToPlayGuideContentTests`）はこちらが担う。パズルモード用の
    /// `.ojisanPuzzlePuzzle` は `gameID` が同じなので `all` には入れない（五目並べの `gomokuRenju` と同じ作法）。
    static var ojisanPuzzleBackpain: HowToPlayGuide { HowToPlayGuide(
        gameID: "ojisanpuzzle",
        title: tr("おじさんの荷物運びパズルの遊び方"),
        lines: [
            tr("2 つひと組の荷物が落ちてきます。よこにスワイプで動かし、タップで回し、下にスワイプで落とします。"),
            tr("同じ荷物がたて・よこに 4 つ以上つながると消えます。消えたあとに落ちてきた荷物がまたつながれば、れんさです。"),
            tr("荷運びモードはラインより下まで片付けたらクリア。重い荷物をかかえるほど腰にきて、満タンで入院です。"),
        ],
        hint: tr("よこスワイプで動かす・タップで回す"),
        hintIcon: "hand.draw.fill",
        items: [
            HowToPlayItem(tr("荷物を 4 つそろえて消して、ラインより下まで片付けたらクリア。腰をいたわろう。")),
            HowToPlayItem(tr("2 つひと組の荷物を、スワイプとタップで動かします。画面のどこを触っても OK。")),
            HowToPlayItem(tr("同じ荷物がたて・よこに 4 つ以上つながると消えます。落ちてきてまたつながれば「れんさ」。")),
            HowToPlayItem(tr("荷物は 5 種類。重いものほど腰にきます。")),
            HowToPlayItem(tr("腰痛ゲージがあり、重い荷物をかかえるほど腰にきて、満タンになると入院です。")),
            HowToPlayItem(tr("入院か、荷物が出てくる位置（▼の列のいちばん上）が埋まったら終わりです。どちらも記録は残ります。")),
        ],
        notes: [
            tr("途中の盤面は保存されません。"),
        ]
    ) }

    /// パズルモード用（会長指示 2026-10-12）。`gameID` は `.ojisanPuzzleBackpain` と同じなので `all` には
    /// 入れない＝登録漏れ検査は `.ojisanPuzzleBackpain` のほうで担保される。
    static var ojisanPuzzlePuzzle: HowToPlayGuide { HowToPlayGuide(
        gameID: "ojisanpuzzle",
        title: tr("おじさんの荷物運びパズルの遊び方"),
        lines: [
            tr("2 つひと組の荷物が落ちてきます。よこにスワイプで動かし、タップで回し、下にスワイプで落とします。"),
            tr("同じ荷物がたて・よこに 4 つ以上つながると消えます。消えたあとに落ちてきた荷物がまたつながれば、れんさです。"),
            tr("パズルモードは空の盤から始まり、ゲージなしで得点をのばします。埋まるまで続きます。"),
        ],
        hint: tr("よこスワイプで動かす・タップで回す"),
        hintIcon: "hand.draw.fill",
        items: [
            HowToPlayItem(tr("荷物を 4 つそろえて消して、得点をのばそう。空の盤から始まり、埋まるまで続きます。")),
            HowToPlayItem(tr("2 つひと組の荷物を、スワイプとタップで動かします。画面のどこを触っても OK。")),
            HowToPlayItem(tr("同じ荷物がたて・よこに 4 つ以上つながると消えます。落ちてきてまたつながれば「れんさ」。")),
            HowToPlayItem(tr("荷物は 5 種類あります。")),
            HowToPlayItem(tr("荷物が出てくる位置（▼の列のいちばん上）が埋まったら終わりです。記録は得点として残ります。")),
        ],
        notes: [
            tr("得点は 消した数 × 10 × れんさ数。"),
            tr("荷物を置くほど少しずつ速くなります。"),
            tr("途中の盤面は保存されません。"),
        ]
    ) }

    /// 全ゲームぶん。テストで「登録漏れが無いか」を突き合わせるのに使う。
    static var all: [HowToPlayGuide] { [
        .game2048, .shogi, .gomoku, .minesweeper, .othello,
        .poker, .concentration, .blackjack, .daifugo, .mahjongSolitaire, .mahjong,
        .sudoku, .go, .solitaire, .chess, .blocks, .freecell, .runner,
        .hanafuda, .spider, .shiritori, .fifteen, .akariKeshi, .fruits, .colorRelay, .anzan, .backgammon, .speed,
        .diceCombo,
        .mancala,
        .homerun, .ojisanPuzzleBackpain,
        .oldMaid,
        .hearts,
        .tsunagi, .hanoi,
        .yonmoku,
        .catPuzzle,
    ] }
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
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    // 自動では開かない。ボタンを押したときだけ図のカードが開く（#2827）。
                    OnboardingEntry(guide.onboarding, style: .prominent)
                    if !guide.items.isEmpty {
                        illustratedItems
                    } else {
                        plainLines
                    }
                    if hasExtra {
                        NavigationLink {
                            extra()
                        } label: {
                            HStack {
                                Label(tr("くわしいルール"), systemImage: "book")
                                    .themeBody(15)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .scaledFont(13, weight: .bold)
                                    .foregroundStyle(Theme.inkSubText)
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
            #if DEBUG
            // 撮影用（DEBUG 限定・#2044）: `-howToPlayScroll <番号>` でその番号のカードを上端に寄せて開く
            // （`notes` は補足カード）。シミュレータは自動でスクロールできないため、下の図はこれで撮る。
            .task {
                let args = ProcessInfo.processInfo.arguments
                guard let i = args.firstIndex(of: "-howToPlayScroll"), i + 1 < args.count else { return }
                try? await Task.sleep(for: .milliseconds(400))
                proxy.scrollTo(HowToPlayScrollID(args[i + 1]), anchor: .top)
            }
            #endif
            }
            .popBackground()
            .navigationTitle(guide.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("閉じる")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        // モーダルは縦長（large）固定（#2096）。半分の高さで開くと 3 行ルールの下が余る。
        .presentationDetents([.large])
    }

    /// 従来の 3 行ルール。
    private var plainLines: some View {
        ForEach(Array(guide.lines.enumerated()), id: \.offset) { index, line in
            HStack(alignment: .top, spacing: 10) {
                HowToPlayNumberBadge(number: index + 1)
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
    }

    /// 図入りの項目（#2044）。1 項目 = 番号＋短文＋その図のカード。最後に補足を文だけのカードで出す。
    @ViewBuilder
    private var illustratedItems: some View {
        ForEach(Array(guide.items.enumerated()), id: \.offset) { index, item in
            HowToPlayItemCard(item, number: index + 1)
                .id(HowToPlayScrollID("\(index + 1)"))
        }
        if !guide.notes.isEmpty {
            HowToPlayNotesCard(guide.notes)
                .id(HowToPlayScrollID("notes"))
        }
    }
}

/// 遊び方シートのカードの位置（撮影用のスクロール先）。
private struct HowToPlayScrollID: Hashable {
    let value: String
    init(_ value: String) { self.value = value }
}

/// 番号の丸。3 行ルールと図カードで同じ部品を使う。
private struct HowToPlayNumberBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .scaledFont(13, weight: .black, design: .rounded)
            .foregroundStyle(Theme.onAccent)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Theme.Fill.coral))
            // 番号は見た目の飾り。「1」だけが単独のフォーカスにならないよう読み上げから外す（#2641）。
            .accessibilityHidden(true)
    }
}

/// 図入りの遊び方の 1 項目のカード（短文＋図）。遊び方シートと、開始シートに遊び方を直接並べるゲーム
/// （おじさんの荷物運びパズル・会長指示 2026-10-12）で同じ見た目にするため、部品として切り出している。
public struct HowToPlayItemCard: View {
    private let item: HowToPlayItem
    private let number: Int?

    /// - Parameter number: 左に出す番号。`nil` なら番号の丸を出さない（項目を抜き出して並べるとき）。
    public init(_ item: HowToPlayItem, number: Int? = nil) {
        self.item = item
        self.number = number
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                if let number { HowToPlayNumberBadge(number: number) }
                Text(item.text)
                    .themeBody(15, weight: .bold)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if let figure = item.figure {
                figure()
                    .frame(maxWidth: .infinity)
                    // 図は説明の絵なので、読み上げは上の文に任せる。
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popCard(corner: Theme.cornerSmall)
    }
}

/// 図入りの遊び方の補足（文だけのカード）。`HowToPlayItemCard` と同じく遊び方シートと開始シートで共有する。
public struct HowToPlayNotesCard: View {
    private let notes: [String]

    public init(_ notes: [String]) {
        self.notes = notes
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .themeBody(13, weight: .medium)
                    .foregroundStyle(Theme.inkSubText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popCard(corner: Theme.cornerSmall)
    }
}

// MARK: - 図入りの遊び方の部品（#2044）

/// 「前 → 後」のコマ図。各コマの間に矢印を挟んで横に並べる。コマの中身（盤・駒・札）は各ゲームが描く。
///
/// おじさんの荷物運びパズルの操作・れんさ、2048 の合体、オセロの裏返しなど、「こうすると、こうなる」を見せる図に使う。
public struct RuleFrames<Frame: View>: View {
    private let count: Int
    private let spacing: CGFloat
    private let frame: (Int) -> Frame

    public init(count: Int, spacing: CGFloat = 4, @ViewBuilder frame: @escaping (Int) -> Frame) {
        self.count = count
        self.spacing = spacing
        self.frame = frame
    }

    public var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<count, id: \.self) { index in
                frame(index)
                if index < count - 1 {
                    Image(systemName: "arrow.right")
                        .scaledFont(12, weight: .black, maxScale: 1.2)
                        .foregroundStyle(Theme.inkSubText)
                }
            }
        }
    }
}

/// 種類の一覧図。種類を等幅で横に並べ、下に「軽い → 重い」のような向きの矢印を添える。
/// 中身（絵・名前・値の印）は各ゲームが描く。荷物の重さ・駒の動き・役の点などに使う。
public struct RuleLineup<Entry: View>: View {
    private let count: Int
    private let low: String?
    private let high: String?
    private let entry: (Int) -> Entry

    public init(count: Int, low: String? = nil, high: String? = nil, @ViewBuilder entry: @escaping (Int) -> Entry) {
        self.count = count
        self.low = low
        self.high = high
        self.entry = entry
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 2) {
                ForEach(0..<count, id: \.self) { index in
                    entry(index).frame(maxWidth: .infinity)
                }
            }
            if low != nil || high != nil {
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.inkSub).frame(height: 2)
                    Image(systemName: "chevron.right")
                        .scaledFont(12, weight: .black, maxScale: 1.2)
                        .foregroundStyle(Theme.inkSubText)
                        .padding(.leading, -6)
                }
                .padding(.horizontal, 6)
                HStack {
                    if let low { Text(low).foregroundStyle(Theme.inkSubText) }
                    Spacer()
                    if let high { Text(high).foregroundStyle(Theme.coralText) }
                }
                .scaledFont(11, weight: .black, design: .rounded, maxScale: 1.2)
                .padding(.horizontal, 6)
            }
        }
    }
}

/// 段階の帯図。横長の帯を段階ごとの色で塗り分け、下に段階の名前を出す。帯の上には段階ごとの絵を置ける。
/// 腰痛ゲージ・体力・ブラックジャックの 21 など「どこまで来ると何が起きるか」を見せる図に使う。
public struct RuleStageBand<Above: View>: View {
    /// 1 段階。`share` は帯全体に対する幅の割合（合計 1）。
    public struct Stage: Sendable {
        public let caption: String
        public let share: CGFloat
        public let color: Color
        public let captionColor: Color

        public init(_ caption: String, share: CGFloat, color: Color, captionColor: Color = Theme.inkSubText) {
            self.caption = caption
            self.share = share
            self.color = color
            self.captionColor = captionColor
        }
    }

    private let stages: [Stage]
    private let width: CGFloat
    private let above: (Int) -> Above

    /// `width` は帯の幅（pt）。図は固定寸法で描くので、呼び出し側がカードに収まる幅を渡す。
    public init(stages: [Stage], width: CGFloat, @ViewBuilder above: @escaping (Int) -> Above) {
        self.stages = stages
        self.width = width
        self.above = above
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    above(index).frame(width: width * stage.share)
                }
            }
            HStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    Rectangle()
                        .fill(stage.color.opacity(0.45))
                        .frame(width: width * stage.share, height: 16)
                        .overlay(alignment: .leading) {
                            if index > 0 { Rectangle().fill(Theme.ink).frame(width: 1.5, height: 20) }
                        }
                }
            }
            .clipShape(Capsule())
            HStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.offset) { _, stage in
                    Text(stage.caption)
                        .scaledFont(11, weight: .black, design: .rounded, maxScale: 1.2)
                        .foregroundStyle(stage.captionColor)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: width * stage.share)
                }
            }
        }
        .frame(width: width)
    }
}

// MARK: - くわしいルール

/// `HowToPlaySheet` の `extra` から開く「くわしいルール」ページ。見出しと本文の組をカードで縦に並べる（#829）。
///
/// 全ゲームの「くわしいルール」はこの 1 つに揃える（#1414）。**題名は「くわしいルール」に固定**で、
/// ゲームごとに変えられない。駒の動き・札の見かたのような図が要るゲームは、`figures` に
/// `RuleFigureCard` を並べる（ルールの行より上に出る）。
/// **文言は各ゲームの `rules` に残す**（テストが文言そのものを検証するため）。
public struct RuleListSheet<Figures: View>: View {
    private let rules: [(String, String)]
    private let figures: Figures

    public init(rules: [(String, String)], @ViewBuilder figures: () -> Figures) {
        self.rules = rules
        self.figures = figures()
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                figures
                ForEach(rules, id: \.0) { rule in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(rule.0)
                            .themeBody(14, weight: .black)
                            .foregroundStyle(Theme.coralText)
                            .accessibilityAddTraits(.isHeader)
                        Text(rule.1)
                            .themeBody(13, weight: .medium)
                            .foregroundStyle(Theme.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RuleCardBackground())
                }
            }
            .padding(Theme.pad)
        }
        .popBackground()
        .navigationTitle(tr("くわしいルール"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

public extension RuleListSheet where Figures == EmptyView {
    init(rules: [(String, String)]) {
        self.init(rules: rules) { EmptyView() }
    }
}

/// 「くわしいルール」と役の早見表で共通の、1 枚のカード背景。
private struct RuleCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

/// `RuleListSheet` の `figures` に置く、図の枠。見出し（任意）の下に好きな図を入れられる。
public struct RuleFigureCard<Content: View>: View {
    private let title: String?
    private let detail: String?
    private let content: Content

    public init(title: String? = nil, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if title != nil || detail != nil {
                HStack(spacing: 6) {
                    if let title {
                        Text(title)
                            .themeBody(14, weight: .black)
                            .foregroundStyle(Theme.coralText)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if let detail {
                        Text(detail)
                            .themeCaption(12, weight: .medium)
                            .foregroundStyle(Theme.inkSubText)
                    }
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RuleCardBackground())
    }
}

// MARK: - 役の早見表

/// 麻雀・花札・ポーカーの役の早見表の共通枠（#1414）。クリーム色の背景（`popBackground`）にカードを並べる。
///
/// 以前は麻雀・花札がシステム標準の `List`（灰色背景）、ポーカーが `ScrollView` と3通りだった。
/// `standalone` が true のときは `NavigationStack` と「閉じる」ボタンごと持つ（単体のシート用）。
/// false のときは、呼び出し側の `NavigationStack` に積まれるページとして振る舞う。
public struct YakuTableSheet<Content: View>: View {
    private let title: String
    private let standalone: Bool
    private let content: Content
    @Environment(\.dismiss) private var dismiss

    public init(title: String, standalone: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.standalone = standalone
        self.content = content()
    }

    public var body: some View {
        if standalone {
            NavigationStack {
                page.toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("閉じる")) { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
            }
        } else {
            page
        }
    }

    private var page: some View {
        ScrollView {
            VStack(spacing: 14) {
                content
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

/// `YakuTableSheet` の中の 1 まとまり。見出し・カードに入った行・注記を縦に並べる。
public struct YakuTableSection<Content: View>: View {
    private let header: String?
    private let footer: String?
    private let content: Content

    public init(header: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Text(header)
                    .themeBody(13, weight: .black)
                    .foregroundStyle(Theme.inkSubText)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RuleCardBackground())
            if let footer {
                Text(footer)
                    .themeCaption(12, weight: .medium)
                    .foregroundStyle(Theme.inkSubText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - ツールバーの `?` ボタン

/// 「遊び方」シートを開く操作。`.howToPlay` が環境へ入れ、`gameChrome` がヘッダー右の所定の位置に
/// `?` ボタンとして置く（#1418。ボタンを各自のツールバーに足す形だと、役の早見表・新規ボタンとの
/// 並びが宣言順しだいになる）。
///
/// `public`: ヘッダーの `?` を隠す画面（`hidesHowToPlay`）が、別の場所（一時停止の画面など）から
/// 同じシートを開けるよう、ゲーム側のモジュールからも読める（柵越えおじさんの打席・#1617）。
public struct HowToPlayTrigger {
    public let present: () -> Void
}

private struct HowToPlayTriggerKey: EnvironmentKey {
    nonisolated(unsafe) static var defaultValue: HowToPlayTrigger? = nil
}

public extension EnvironmentValues {
    var howToPlayTrigger: HowToPlayTrigger? {
        get { self[HowToPlayTriggerKey.self] }
        set { self[HowToPlayTriggerKey.self] = newValue }
    }
}

/// 「遊び方」シートを開いているか（#2406）。`.howToPlay` が上へ流し、`gameTimerLifecycle` が読んで
/// 計時を止める。環境値ではなく preference なのは、`gameTimerLifecycle` が `.howToPlay` より外側に
/// 付くため（環境は下にしか流れない）。ゲームごとの `onPresent` を増やさずに済む。
struct HowToPlayPresentedKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct HowToPlayToolbar<Extra: View>: ViewModifier {
    let guide: HowToPlayGuide
    let extra: (() -> Extra)?
    var onPresent: (() -> Void)?
    var onDismiss: (() -> Void)?
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .preference(key: HowToPlayPresentedKey.self, value: isPresented)
            .environment(\.howToPlayTrigger, HowToPlayTrigger {
                onPresent?()
                isPresented = true
            })
            #if DEBUG
            // 撮影用（DEBUG 限定・#2044）: `-showHowToPlay` で開いた直後に「？」のシートを出す。
            // シミュレータはタップを自動化できないため。開始シートのあるゲームは `-autoStartSetup` と併用する。
            .task {
                guard ProcessInfo.processInfo.arguments.contains("-showHowToPlay") else { return }
                try? await Task.sleep(for: .milliseconds(1500))
                onPresent?()
                isPresented = true
            }
            #endif
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
    /// 卓（フェルト）の上に置かれたときは白系で出す（全画面の枠 #2531）。地の上では従来の `Theme.inkSub` と同じ値。
    @Environment(\.cardTableInk) private var ink

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
                .foregroundStyle(ink.labelSub)
                .allowsHitTesting(false)
        }
    }
}
