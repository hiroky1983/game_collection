import Foundation

/// 終局のおじさんの一言（#3255）。クリアは通常 12 種＋条件つき、ミス 3 回の負けは 6 種。
/// 返すのは文言の表のキー（日本語）で、画面が `tr` で引く。選び方は**面番号（自由に遊ぶは局の通し番号）だけで決まる**ので、
/// 同じ面なら同じ一言になる。直前に出した一言（`previous`）と同じなら次の候補にずらし、同じ一言を続けて出さない。
enum CatPuzzleUncleLines {
    static let clearNormal = [
        "みんなでくつろいでおる", "全員見つかったわい", "ようやく静かになったのう", "ふう、これで夕飯にできる",  // i18n-keep: 文言の表のキー（画面が tr で引く）
        "猫らしい隠れ方じゃった", "わしより家に詳しいのう", "今日もよう見つけたな", "やるのう、お主",  // i18n-keep: 文言の表のキー（画面が tr で引く）
        "まったく、どこにでも入りおる", "見事な探しっぷりじゃ", "猫たちもほっとしておる", "これで安心して昼寝ができるわい",  // i18n-keep: 文言の表のキー（画面が tr で引く）
    ]
    static let clearNoMiss = ["一度も外さんとは、恐れ入った", "ぴたりと当てたな、見事じゃ"]  // i18n-keep: 文言の表のキー（画面が tr で引く）
    static let clearKey = "鍵の猫まで見つけるとは、たいしたもんじゃ"  // i18n-keep: 文言の表のキー（画面が tr で引く）
    static let clearNewBoard = "家が広うなっても、お主にかかれば楽勝じゃな"  // i18n-keep: 文言の表のキー（画面が tr で引く）
    static let clearBig = "こんな広い家でよう見つけたのう"  // i18n-keep: 文言の表のキー（画面が tr で引く）
    static let fail = [
        "猫はどこへ行ったんじゃ…", "うーむ、今日は猫の勝ちじゃな", "猫のほうが一枚上手じゃったか",  // i18n-keep: 文言の表のキー（画面が tr で引く）
        "次こそは見つけてやるわい", "どこに隠れたんじゃ、まったく", "惜しかったのう、もう一度じゃ",  // i18n-keep: 文言の表のキー（画面が tr で引く）
    ]

    /// クリアの一言。条件に合うものを優先する（盤が広がった最初の面 → 鍵の面 → ミス 0 回 → 10×10 以上）。
    /// 優先の候補が直前と同じなら、次の優先の候補へ、無ければ通常の 12 種から選ぶ。
    static func clear(number: Int, mistakes: Int, isKey: Bool, entersNewBoard: Bool, side: Int, previous: String?) -> String {
        var special: [String] = []
        if entersNewBoard { special.append(clearNewBoard) }
        if isKey { special.append(clearKey) }
        if mistakes == 0 { special.append(clearNoMiss[abs(number) % clearNoMiss.count]) }
        if side >= 10 { special.append(clearBig) }
        if let line = special.first(where: { $0 != previous }) { return line }
        return pick(clearNormal, number: number, previous: previous)
    }

    /// ミス 3 回の一言。
    static func failed(number: Int, previous: String?) -> String {
        pick(fail, number: number, previous: previous)
    }

    private static func pick(_ lines: [String], number: Int, previous: String?) -> String {
        let start = abs(number) % lines.count
        let line = lines[start]
        return line == previous ? lines[(start + 1) % lines.count] : line
    }
}
