import Core

/// しりとりの札 1 枚（#1243）。絵は神経衰弱と共有する `ObjectCardKind`。
///
/// **1 枚が複数の読みを持てる（裏読み）**。`readings[0]` が表読みで、札の下に見せる。
/// 2 つ目以降は本家の持ち味の言い換え（たいこ→ドラム、こっぷ→グラス など）で、
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

    /// 山札（30 枚）。最初の 20 枚は会長決裁 2026-09-21（#1243）の初期カード案そのまま、
    /// 後ろの 10 枚は #1245（会長決裁: 20 枚では連鎖がすぐ途切れる）で足した。
    /// 神経衰弱の絵柄（#1244）もこの 30 種に揃える。
    ///
    /// 足した 10 枚は、既存の語尾（こ・ら・す・か・ま・ね など）から始まる札と、その語頭で終わる札を
    /// 混ぜて連鎖が伸びやすくしてある。裏読みは足していない（先頭字が既存のどの語尾とも重ならない
    /// 裏読みは、表読みが受けられない札にしか使われず連鎖に効かなかったため）。
    public static let deck: [ShiritoriCard] = [
        ShiritoriCard(.apple, "りんご"),
        ShiritoriCard(.gorilla, "ごりら"),
        ShiritoriCard(.seaOtter, "らっこ"),
        ShiritoriCard(.koala, "こあら"),
        ShiritoriCard(.camel, "らくだ"),
        ShiritoriCard(.rabbit, "うさぎ"),
        ShiritoriCard(.guitar, "ぎたー"),
        ShiritoriCard(.drum, "たいこ", "どらむ"),
        ShiritoriCard(.kitten, "こねこ"),
        ShiritoriCard(.glass, "こっぷ", "ぐらす"),
        ShiritoriCard(.squirrel, "りす"),
        ShiritoriCard(.watermelon, "すいか"),
        ShiritoriCard(.turtle, "かめ"),
        ShiritoriCard(.eyeglasses, "めがね"),
        ShiritoriCard(.cat, "ねこ", "にゃんこ"),
        ShiritoriCard(.spinningTop, "こま"),
        ShiritoriCard(.pillow, "まくら"),
        ShiritoriCard(.ostrich, "だちょう", "えみゅー"),
        ShiritoriCard(.handFan, "うちわ", "おうぎ"),
        ShiritoriCard(.crocodile, "わに"),
        ShiritoriCard(.boat, "ふね"),
        ShiritoriCard(.leek, "ねぎ"),
        ShiritoriCard(.ball, "まり"),
        ShiritoriCard(.mushroom, "きのこ"),
        ShiritoriCard(.horse, "うま"),
        ShiritoriCard(.deer, "しか"),
        ShiritoriCard(.cow, "うし"),
        ShiritoriCard(.bell, "すず"),
        ShiritoriCard(.moon, "つき"),
        ShiritoriCard(.octopus, "たこ"),
    ]
}
