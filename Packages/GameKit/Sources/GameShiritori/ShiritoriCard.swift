import Core

/// しりとりの札 1 枚（#1243）。絵は神経衰弱と共有する `ObjectCardKind`。
///
/// **1 枚が複数の読みを持てる（裏読み）**。`readings[0]` が表読みで、札の下に見せる。
/// 2 つ目以降は本家の持ち味の言い換え（ねこ→にゃんこ など）で、
/// 画面には出さず、その読みで選んだときだけ「うらよみ！」として見える。
/// 読みは正規化（ひらがな）済みで持つ。
public struct ShiritoriCard: Identifiable, Equatable, Hashable, Sendable {
    public let kind: ObjectCardKind
    public let readings: [String]

    public var id: String { kind.rawValue }
    /// 札の下に見せる表読み。
    public var primaryReading: String { readings[0] }

    init(_ kind: ObjectCardKind, _ readings: String...) {
        precondition(!readings.isEmpty, "読みが 1 つも無い札")
        self.kind = kind
        self.readings = readings.map { ShiritoriKana.hiragana($0) }
    }

    /// 山札（50 枚）。最初の 20 枚は会長決裁 2026-09-21（#1243）の初期カード案そのまま、
    /// 後ろの 10 枚は #1245（会長決裁: 20 枚では連鎖がすぐ途切れる）で足した。
    /// 神経衰弱の絵柄（#1244）もこの 50 種に揃える。
    ///
    /// 足した 10 枚は、既存の語尾（こ・ら・す・か・ま・ね など）から始まる札と、その語頭で終わる札を
    /// 混ぜて連鎖が伸びやすくしてある。この 10 枚（#1245 時点）には裏読みを足していない（先頭字が既存のどの語尾とも重ならない
    /// 裏読みは、表読みが受けられない札にしか使われず連鎖に効かなかったため）。
    ///
    /// **裏読みは山札のいずれかの語尾から受けられるものだけを残す**（#1271）。
    /// 「どらむ」（語頭 ど・語尾 む→ゆ の受け皿が無い）・「えみゅー」は #1292 で、
    /// 「ぐらす」（語頭 ぐ）・「おうぎ」（語頭 お）は #1271 で、同じ理由（受け皿となる語頭の
    /// 濁音・清音のどちらの語尾も山札に無く、選ぶ契機が絶対に来ない）で裏読み自体を削除した。
    ///
    /// #1298 で会長不採用の 5 枚（こねこ・まくら・うちわ・ねぎ・まり）を くま・まふらー・まいく・くり・にく に
    /// 差し替えた（`ObjectCardKind` の識別子は中断データのため据え置き）。「ま」で始まる札（こま・うま の受け）と
    /// 「り」で終わる札（りんご・りす の送り）を残すよう選び、全札の語尾が受けられることはテストが縛る。
    public static let deck: [ShiritoriCard] = [
        ShiritoriCard(.apple, "りんご"),
        ShiritoriCard(.gorilla, "ごりら"),
        ShiritoriCard(.seaOtter, "らっこ"),
        ShiritoriCard(.koala, "こあら"),
        ShiritoriCard(.camel, "らくだ"),
        ShiritoriCard(.rabbit, "うさぎ"),
        ShiritoriCard(.guitar, "ぎたー"),
        ShiritoriCard(.drum, "たいこ"),
        ShiritoriCard(.kitten, "くま", "こぐま"),
        ShiritoriCard(.glass, "こっぷ"),
        ShiritoriCard(.squirrel, "りす"),
        ShiritoriCard(.watermelon, "すいか"),
        ShiritoriCard(.turtle, "かめ", "うみがめ"),
        ShiritoriCard(.eyeglasses, "めがね"),
        ShiritoriCard(.cat, "ねこ", "にゃんこ"),
        ShiritoriCard(.spinningTop, "こま"),
        ShiritoriCard(.pillow, "まふらー", "すかーふ"),
        ShiritoriCard(.ostrich, "だちょう"),
        ShiritoriCard(.handFan, "まいく"),
        ShiritoriCard(.crocodile, "わに"),
        ShiritoriCard(.boat, "ふね"),
        ShiritoriCard(.leek, "くり"),
        ShiritoriCard(.ball, "にく", "すてーき"),
        ShiritoriCard(.mushroom, "きのこ", "しいたけ"),
        ShiritoriCard(.horse, "うま"),
        ShiritoriCard(.deer, "しか"),
        ShiritoriCard(.cow, "うし", "ぎゅう"),
        ShiritoriCard(.bell, "すず"),
        ShiritoriCard(.moon, "つき"),
        ShiritoriCard(.octopus, "たこ"),
        // #1502（会長決裁 2026-09-29）で足した 20 枚。裏読みは 10 件足して計 11 件にした。
        ShiritoriCard(.lifebuoy, "うきわ"),
        ShiritoriCard(.umbrella, "かさ"),
        ShiritoriCard(.fish, "さかな"),
        ShiritoriCard(.eggplant, "なす"),
        ShiritoriCard(.fox, "きつね", "こぎつね"),
        ShiritoriCard(.whale, "くじら"),
        ShiritoriCard(.ice, "こおり"),
        ShiritoriCard(.zebra, "しまうま"),
        ShiritoriCard(.sushi, "すし", "にぎり"),
        ShiritoriCard(.egg, "たまご"),
        ShiritoriCard(.dango, "だんご"),
        ShiritoriCard(.chicken, "にわとり", "こっこ"),
        ShiritoriCard(.taiyaki, "たいやき"),
        ShiritoriCard(.manju, "まんじゅう"),
        ShiritoriCard(.friedEgg, "めだまやき"),
        ShiritoriCard(.cake, "けーき"),
        ShiritoriCard(.cottonCandy, "わたあめ"),
        ShiritoriCard(.shoe, "くつ", "しゅーず"),
        ShiritoriCard(.bamboo, "たけ"),
        ShiritoriCard(.flask, "すいとう"),
    ]
}
