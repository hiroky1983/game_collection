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
            "「ヒット」でもう 1 枚引き、「スタンド」でそこで止めます。最初の 2 枚では、賭けを倍にして 1 枚だけ引く「ダブルダウン」と、同じ数字を 2 手に分ける「スプリット」も選べます。",
        ],
        hint: "21 に近づけたほうが勝ち",
        hintIcon: "suit.spade.fill"
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

    static let blocks = HowToPlayGuide(
        gameID: "blocks",
        title: "ブロック崩しの遊び方",
        lines: [
            "画面を指でなぞるとパドルが動きます。タップすると球が飛び出します。",
            "球をはね返してブロックに当てます。灰色のブロックは壊れません。",
            "壊せるブロックを全部消すと次のステージへ。球を 3 回落とすと終わりです。",
        ],
        hint: "なぞってパドルを動かそう",
        hintIcon: "hand.draw.fill"
    )

    /// 全ゲームぶん。テストで「登録漏れが無いか」を突き合わせるのに使う。
    static let all: [HowToPlayGuide] = [
        .game2048, .shogi, .gomoku, .minesweeper, .othello,
        .poker, .concentration, .blackjack, .daifugo, .mahjongSolitaire, .mahjong,
        .sudoku, .go, .solitaire, .chess, .blocks,
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

// MARK: - ツールバーの `?` ボタン

private struct HowToPlayToolbar<Extra: View>: ViewModifier {
    let guide: HowToPlayGuide
    let extra: (() -> Extra)?
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresented = true } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("遊び方")
                }
            }
            .sheet(isPresented: $isPresented) {
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
    func howToPlay(_ guide: HowToPlayGuide) -> some View {
        modifier(HowToPlayToolbar<EmptyView>(guide: guide, extra: nil))
    }

    /// 詳細ページ付きの `?` ボタン（ポーカーの役一覧・大富豪のルール）。
    func howToPlay<Extra: View>(
        _ guide: HowToPlayGuide,
        @ViewBuilder extra: @escaping () -> Extra
    ) -> some View {
        modifier(HowToPlayToolbar(guide: guide, extra: extra))
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

    public var body: some View {
        if isVisible {
            Label(guide.hint, systemImage: guide.hintIcon)
                .themeBody(14)
                .foregroundStyle(Theme.inkSub)
                .allowsHitTesting(false)
        }
    }
}
