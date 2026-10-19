import CoreGraphics

/// ブラックジャックの操作まわりの寸法。**View から切り出した定数**として置く。
///
/// 切り出しの理由はポーカー（`PokerMetrics`・#207）と同じで、ここが「押しにくい」の急所だから。
/// 値が縮んだらテストで気づけるようにする。
enum BlackjackMetrics {

    /// Apple HIG の最小タップ標的。
    static let minimumTapTarget: CGFloat = 44

    /// 操作ボタン（ベット・ヒット・スタンド・ダブルダウン・スプリット・次のゲーム・結果まで進める）の
    /// 高さの下限（#709）。
    ///
    /// もとは本文 14pt + 上下 10pt の余白しか無く、高さは約 37pt で HIG を下回っていた。
    /// 毎局必ず押すヒット／スタンドを含むので、ポーカー（#207）と同じ 44pt に揃える。
    /// 文字は `lineLimit(1)` + `minimumScaleFactor` で折り返さない（#189）ため、
    /// 高さを下限で固定してもボタンの背が跳ねることはない。
    static let actionButtonMinHeight: CGFloat = minimumTapTarget
}

/// 画面の中身に使える高さで変える縦の寸法（#2498）。`AdaptiveLayout`（#458）は幅しか持たないので、
/// 縦の狭さはこの画面で持つ。iPhone SE（使える高さ 603pt）はスプリット中（ハンド 2 つ・ダブルダウンの段あり）に
/// 固定 pt の中身が約 656pt（初回ミニガイドが出る回は約 678pt）になり、溢れた分が上下に出て
/// チップの帯がナビバーの下に、バナーが画面の下に潜る。
enum BlackjackVerticalMetrics: Equatable {
    case regular
    case compact

    /// 「縦が狭い」と見なす境目（pt）。通常寸法が要る高さ（ミニガイド込みで約 678pt）より上に置く。
    /// iPhone SE は 603pt で詰める側、13 mini は約 687pt・iPhone 17 は約 724pt で通常の側。
    static let compactHeightThreshold: CGFloat = 680

    /// 詰めるのは縦に溢れるスプリット中だけ。配牌前・1 手のときの見た目は変えない。
    static func metrics(forHeight height: CGFloat, isSplit: Bool) -> BlackjackVerticalMetrics {
        isSplit && height < compactHeightThreshold ? .compact : .regular
    }

    /// 画面の要素どうしの縦の間隔。
    var spacing: CGFloat { self == .regular ? 10 : 6 }
    /// ディーラーとあなたの間の間隔。
    var tableSpacing: CGFloat { self == .regular ? 10 : 6 }
    /// 画面の外周の余白。
    var pad: CGFloat { self == .regular ? 16 : 8 }
    /// チップの帯の上下の余白。
    var chipsVerticalPadding: CGFloat { self == .regular ? 8 : 4 }
    /// ディーラー・あなたの白い札の内側の上下の余白。
    var areaVerticalPadding: CGFloat { self == .regular ? 14 : 8 }

    /// 固定部分の高さの見積もり（#2498 の実測の内訳: チップの帯 17 + 余白・ディーラー 見出し 17 + 札 90 ・
    /// あなた 行 94 × 2 + 行間・間隔の最小 4・ダブルダウンの段ありの操作欄 116・バナー 50・ミニガイド 22）。
    /// 間隔は外側 5 箇所（チップ・テーブル・ミニガイド・操作欄・バナー）と、テーブルの中 2 箇所。
    /// `BlackjackMetricsTests` が境目との整合を固定する。
    var estimatedSplitMinimumHeight: CGFloat {
        let chips = 17 + chipsVerticalPadding * 2
        let dealer = 17 + tableSpacing + 90 + areaVerticalPadding * 2
        let player = 94 * 2 + tableSpacing + areaVerticalPadding * 2
        return chips + dealer + 4 + player + 116 + 50 + 22 + spacing * 5 + pad * 2
    }
}
