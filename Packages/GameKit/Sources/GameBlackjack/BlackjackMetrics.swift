import CoreGraphics

/// ブラックジャックの操作まわりの寸法。**View から切り出した定数**として置く。
///
/// 切り出しの理由はポーカー（`PokerMetrics`・#207）と同じで、ここが「押しにくい」の急所だから。
/// 値が縮んだらテストで気づけるようにする。
enum BlackjackMetrics {

    /// Apple HIG の最小タップ標的。
    static let minimumTapTarget: CGFloat = 44

    /// 操作ボタン（配る・ヒット・スタンド・スプリット・次の回へ・結果まで進める）の
    /// 高さの下限（#709）。
    ///
    /// もとは本文 14pt + 上下 10pt の余白しか無く、高さは約 37pt で HIG を下回っていた。
    /// 毎局必ず押すヒット／スタンドを含むので、ポーカー（#207）と同じ 44pt に揃える。
    /// 文字は `lineLimit(1)` + `minimumScaleFactor` で折り返さない（#189）ため、
    /// 高さを下限で固定してもボタンの背が跳ねることはない。
    static let actionButtonMinHeight: CGFloat = minimumTapTarget
}

/// 画面の中身に使える高さで変える縦の寸法（#2498 → #2531）。`AdaptiveLayout`（#458）は幅しか持たないので、
/// 縦の狭さはこの画面で持つ。
///
/// レイアウトパターン A（全画面・#2531）では、中身に使える高さは全画面の枠のヘッダー（52pt）の下からバナーの帯の上まで
/// （iPhone SE で 537pt・iPhone 17 で 668pt。バナーは枠が置くので中身に含まない）。ディーラー・あなたの白い札と
/// 操作欄の白い札は無くなったが、SE のスプリット中（ハンド 2 つ・スプリットの段あり・初回のミニガイド）は
/// 通常の寸法で約 555pt になり SE の 537pt を超えるので、SE では引き続き詰める（#2498 の再発防止）。
enum BlackjackVerticalMetrics: Equatable {
    case regular
    case compact

    /// 「縦が狭い」と見なす境目（pt）。通常寸法が要る高さ（`estimatedSplitMinimumHeight` の regular）より上に置く。
    /// iPhone SE（537pt）は詰める側、iPhone 17（668pt）・13 mini（約 618pt）は通常の側。
    static let compactHeightThreshold: CGFloat = 580

    /// 詰めるのは縦に溢れうるスプリット中だけ。配牌前・1 手のときの見た目は変えない。
    static func metrics(forHeight height: CGFloat, isSplit: Bool) -> BlackjackVerticalMetrics {
        isSplit && height < compactHeightThreshold ? .compact : .regular
    }

    /// 画面の要素どうしの縦の間隔。
    var spacing: CGFloat { self == .regular ? 8 : 6 }
    /// ディーラーとあなたの間の間隔。
    var tableSpacing: CGFloat { self == .regular ? 10 : 6 }
    /// 中身の上下の余白（左右は全画面の枠の 8pt）。
    var pad: CGFloat { self == .regular ? 4 : 2 }
    /// 勝負の帯（何回目・勝ち点・連勝）の上下の余白。
    var chipsVerticalPadding: CGFloat { self == .regular ? 8 : 4 }
    /// ディーラー・あなたの段の上下の余白。
    var areaVerticalPadding: CGFloat { self == .regular ? 6 : 2 }

    /// スプリット中の固定部分の高さの見積もり（勝負の帯 17 + 余白・ディーラー 見出し 17 + 札 90 ・
    /// あなた 行 94 × 2 + 行間・間隔の最小 4・スプリットの段ありの操作欄 96（44 + 8 + 44）・ミニガイド 22）。
    /// 間隔は外側 4 箇所（帯・テーブル・ミニガイド・操作欄のあいだ）と、テーブルの `tableSpacing` 4 箇所
    /// （ディーラーの中・あなたの中・ディーラーと Spacer・Spacer とあなた）。バナーは全画面の枠が持つので含めない。
    /// `BlackjackMetricsTests` が境目との整合を固定する。
    var estimatedSplitMinimumHeight: CGFloat {
        let chips = 17 + chipsVerticalPadding * 2
        return chips + estimatedSplitTableHeight + actionAreaMinHeight + 22 + spacing * 4 + pad * 2
    }

    /// スプリット中の卓（ディーラーの段・間隔の最小 4・ハンド 2 つの段）の高さの見積もり。
    ///
    /// 卓の高さの上限にも使う（会長 QA 2026-10-22・#2531）。全画面にしてディーラーとあなたの間が大きく空いたので、
    /// 卓をこの高さまでに抑え、卓と操作欄のまとまりを上下の余白の真ん中に置く。上限をスプリット中の高さにしておけば、
    /// 1 手 → スプリットで卓の高さが変わらず、ディーラーの札も操作欄も動かない（1 手のときはその差の分だけ間が空く）。
    var estimatedSplitTableHeight: CGFloat {
        let dealer = 17 + tableSpacing + 90 + areaVerticalPadding * 2
        let player = 94 * 2 + tableSpacing + areaVerticalPadding * 2
        return dealer + tableSpacing * 2 + 4 + player
    }

    /// 操作欄に取っておく高さ（ボタン 2 段 = 44 + 8 + 44）。スプリットのボタンが出る・消える、結果にやり直しの
    /// 広告ボタンが付く、で操作欄の背が変わっても、真ん中に置いた卓が上下に動かないようにする（#1485）。
    var actionAreaMinHeight: CGFloat { BlackjackMetrics.actionButtonMinHeight * 2 + 8 }
}
