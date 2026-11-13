import SwiftUI

/// ゲーム画面の共通枠（#528）。
///
/// 20 本のゲーム View が、**同じ骨格を各自で組み直していた**——画面背景・評価リクエストの紐づけ・
/// ナビゲーションバーの構成・戻るボタン・タイトル。新しいゲームを足すたびに既存の View から
/// 20 行ほどを写して回ることになり、写し漏れがそのまま画面ごとのばらつきになる
/// （#515 の「確認ダイアログがあるゲームと無いゲーム」がこの形で生まれた）。
///
/// **ここに置くのは「全ゲームで同じでなければならないもの」だけ**。ツールバー右側の操作
/// （新規対局・役の早見表・投了など）はゲームごとに違って当然なので、呼び出し側から渡す。
///
/// 盤ゲーム（将棋・チェス）だけで共有する演出・層の重ね順は `BoardGameChrome.swift` にある。
/// あちらは「2 ゲームで同じ」、こちらは「全ゲームで同じ」で対象が違う。

// MARK: - 画面の枠

/// ヘッダー右の「役の早見表」ボタン（#1418）。アイコンは全ゲームで 1 種類（`list.bullet.rectangle`）に固定し、
/// 麻雀の文字「役」・ポーカーの `list.number` のようなばらつきを作らない。
public struct GameChromeReference {
    let accessibilityLabel: String
    let action: () -> Void

    /// - Parameter accessibilityLabel: 読み上げ名（「役の早見表」「役ボーナス配当表」など）。
    public init(_ accessibilityLabel: String? = nil, action: @escaping () -> Void) {
        self.accessibilityLabel = accessibilityLabel ?? tr("役の早見表")
        self.action = action
    }
}

/// ヘッダー右の「新規」ボタン（#1418）。種類ごとに読み上げ名が決まる（会長決裁 #1011）。
/// 絵柄は種類によらず `plus.circle.fill` の 1 つにそろえる（#2370。アクションだけ `arrow.clockwise` で＋と⟳が混ざっていた）。
public struct GameChromeNewGame {
    public enum Kind {
        /// 対戦ゲーム（CPU 戦）＝「新規対局」。
        case match
        /// 一人用＝「新規ゲーム」。
        case solo
        /// アクション（リアルタイム進行）＝「はじめから」。
        case restart

        var accessibilityLabel: String {
            switch self {
            case .match: tr("新規対局")
            case .solo: tr("新規ゲーム")
            case .restart: tr("はじめから")
            }
        }

        /// 全種類で同じ絵柄（#2370）。種類の違いは読み上げ名だけで表す。
        var systemImage: String { "plus.circle.fill" }
    }

    let kind: Kind
    let isDisabled: Bool
    let hasProgressToLose: Bool
    let onAskConfirm: (() -> Void)?
    let action: () -> Void

    /// - Parameter hasProgressToLose: 押すと捨ててしまう進行があるとき true（#3148）。true の間は、共通の確認
    ///   （「終了して新しく始めますか？」）を出し、了承されたときだけ `action` を呼ぶ。各画面が確認を手書きして
    ///   書き漏らす（確認なしで盤を捨てる）のを防ぐ。**自前で確認や「終了して…」の開始シートを持つ画面は渡さない**
    ///   （確認が二重になる）。
    /// - Parameter onAskConfirm: 確認を出す直前に呼ぶ。リアルタイムのゲームが確認を読んでいる間に止めるのに使う。
    public init(_ kind: Kind, isDisabled: Bool = false, hasProgressToLose: Bool = false,
                onAskConfirm: (() -> Void)? = nil, action: @escaping () -> Void) {
        self.kind = kind
        self.isDisabled = isDisabled
        self.hasProgressToLose = hasProgressToLose
        self.onAskConfirm = onAskConfirm
        self.action = action
    }

    /// ボタンが押されたとき。進行を捨てるなら確認を出し（`askConfirm`）、そうでなければそのまま `action`。
    func tapped(askConfirm: () -> Void) {
        if hasProgressToLose {
            onAskConfirm?()
            askConfirm()
        } else {
            action()
        }
    }
}

/// ヘッダー右のゲーム固有の操作（難易度・盤面選択など・#3475）。
///
/// 狭い画面では「…」のメニューにまとめるため、`ToolbarContent` ではなく **タイトル・アイコン・処理を値で**渡す。
/// `title` は並びの中ではアイコンの読み上げ名、メニューでは項目名になる。
public struct GameChromeAction {
    let title: String
    let systemImage: String
    let isDisabled: Bool
    let action: () -> Void

    public init(_ title: String, systemImage: String, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isDisabled = isDisabled
        self.action = action
    }
}

/// ヘッダー右のボタンを「…」にまとめるかの判定（#3475）。幅の決め打ちはせず、題字が下限まで縮んでも入るかで決める。
public enum GameChromeHeaderMetrics {
    /// 題字を縮める下限（`GameChromeTitle` の `minimumScaleFactor` と同じ値）。
    public static let minTitleScale: CGFloat = 0.6
    /// 戻るボタン 1 つぶんの幅。
    public static let backButtonWidth: CGFloat = 44
    /// ヘッダー右のボタン 1 つぶんの幅（ボタン間の隙間込み）。
    public static let buttonWidth: CGFloat = 44
    /// 題字の左右に残す余白（バーの左右の余白＋題字との隙間）。
    public static let margin: CGFloat = 32

    /// - Parameters:
    ///   - titleWidth: 縮めていない題字の本来の幅。
    ///   - screenWidth: 画面（ナビバー）の幅。
    ///   - buttonCount: ヘッダー右のボタン数（「…」にまとめる前）。
    ///   - hasBackButton: 戻るボタンがあるか。
    ///   - buttonScale: 文字サイズ設定に応じたボタンの拡大率（標準で 1。特大ではボタンが約 1.4 倍の幅になり、
    ///     固定幅で数えると題字が「…」に切れるのを見逃した・#3495）。
    /// - Returns: 題字が 0.6 倍まで縮んでも入らないとき true。ボタンが 1 つ以下なら「…」にしても幅は減らないので false。
    public static func shouldCollapse(titleWidth: CGFloat, screenWidth: CGFloat, buttonCount: Int,
                                      hasBackButton: Bool = true, buttonScale: CGFloat = 1) -> Bool {
        guard buttonCount >= 2 else { return false }
        let scale = max(1, buttonScale)
        let available = screenWidth - (hasBackButton ? backButtonWidth * scale : 0)
            - CGFloat(buttonCount) * buttonWidth * scale - margin
        return titleWidth * minTitleScale > available
    }
}

/// 「新規」ボタンの共通の確認ダイアログ（#3148）。`GameChromeNewGame.hasProgressToLose` が true のときだけ使われる。
struct GameChromeNewGameConfirmation: ViewModifier {
    let newGame: GameChromeNewGame?
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.dialogs { anchor in
            anchor.confirmationDialog(tr("今の進行を終了して始めますか？"), isPresented: $isPresented,
                                      titleVisibility: .visible) {
                if let newGame {
                    Button(tr("終了して始める"), role: .destructive) { newGame.action() }
                }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("今の盤面は失われます。"))
            }
        }
    }
}

/// タイトルの下に出す「今の条件」のチップ（#1690・会長決裁 2026-10-25。#2906 でタップできない表示だけに変更）。
///
/// 対局中も今の条件（例「ふつう・先手」）が分かる**表示専用**のチップ。置き場所は全ゲーム共通の
/// 1 か所（ナビバーのタイトルの下。全画面の枠ではヘッダーの表示名の下）に固定する。
/// タップでは何も起きない（設定を開く役割は既存の「＋」ボタンとかぶるため、#2906 で外した）。
public struct GameChromeCondition {
    /// 条件の言葉。**先頭ほど大事**（難易度を先頭に置く）。幅が足りないときは先頭だけに縮める。
    let parts: [String]

    public init(_ parts: [String]) {
        self.parts = parts.filter { !$0.isEmpty }
    }

    /// 全文（「ふつう・先手」）。
    var fullText: String { parts.joined(separator: tr("・")) }
    /// 縮めた文（先頭 = 難易度だけ）。
    var shortText: String { parts.first ?? "" }
    var hasShortForm: Bool { parts.count > 1 }
}

/// 条件のチップ本体。12pt・タップできない表示専用（#2906。押せる見た目になる「⌄」は付けない）。
/// 文字色は置き場所の面に合わせて呼び出し側が渡す。
struct GameConditionChip: View {
    let text: String
    let ink: Color

    var body: some View {
        Text(text)
            .themeCaption(12, weight: .semibold, maxScale: 1.3)
            .lineLimit(1)
            .foregroundStyle(ink)
            .padding(.horizontal, 6)
            .frame(minHeight: 16)
            // ボタンではなく、値を読み上げるだけの表示（#2906）。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tr("今の条件: %@", text))
    }
}

/// 全文 → 先頭だけ、の順に幅へ収まる方を出す（`ViewThatFits`）。収まる方が無ければ先頭だけ。
struct GameConditionChipFitting: View {
    let condition: GameChromeCondition
    let ink: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            GameConditionChip(text: condition.fullText, ink: ink)
            if condition.hasShortForm {
                GameConditionChip(text: condition.shortText, ink: ink)
            }
        }
    }
}

public extension View {
    /// ゲーム画面の共通枠を当てる（背景・評価リクエスト・ナビバー・戻る・タイトル）。
    ///
    /// - Parameters:
    ///   - title: ナビゲーションバー中央に出す表示名。
    ///   - review: 評価リクエストの実行をこの画面に紐づける（`GameServices.review`）。
    ///   - condition: タイトルの下に出す今の条件のチップ（#1690）。条件を選べるゲームだけ渡す。
    ///   - reference: 役の早見表。あるゲームだけ渡す。
    ///   - newGame: 新規ボタン。あるゲームだけ渡す。
    ///   - actions: 上の 2 つに収まらないゲーム固有の操作（難易度・盤面選択メニューなど）。最後尾に並ぶ。
    ///     狭い画面では他のボタンと一緒に「…」のメニューにまとまる（#3475）ので、`ToolbarContent` ではなく値で渡す。
    ///   - hidesBackButton: 左上の戻るを隠す。誤タップで進行中の挑戦が終わってはいけない画面だけが渡す
    ///     （柵越えおじさんの打席・#1550。やめる操作はゲーム側の一時停止に置く）。
    ///   - hidesHowToPlay: ヘッダー右上の `?`（`.howToPlay`）を隠す。一時停止の画面など、ゲーム側の別の場所に
    ///     同じ「遊び方」への導線を置く画面だけが渡す（柵越えおじさんの打席・#1617）。`.howToPlay` の環境値
    ///     自体は隠さないので、渡す側は `howToPlayTrigger` を読んで自前のボタンから開ける。
    ///
    /// ヘッダー右の並びは **役の早見表 → `?`（`.howToPlay`）→ 新規 → その他** で固定し、
    /// ゲーム側からは変えられない（#1418。並びが各ゲームの書き方しだいだった）。
    ///
    /// ナビバーの背景は全ゲームで画面の背景色（`Theme.background`）に揃え、ツールバーのボタンは
    /// `Theme.coralText`（文字用の濃い赤・#2377）に固定する（#1412・会長決裁 2026-09-25。既定の白い帯が
    /// クリーム色の画面と食い違う、神経衰弱だけボタンが紫、というばらつきを引数ごと無くした）。
    func gameChrome(
        title: String,
        review: ReviewRequestService?,
        condition: GameChromeCondition? = nil,
        reference: GameChromeReference? = nil,
        newGame: GameChromeNewGame? = nil,
        hidesBackButton: Bool = false,
        hidesHowToPlay: Bool = false,
        actions: [GameChromeAction] = []
    ) -> some View {
        modifier(GameChromeBase(review: review))
            .modifier(GameChromeToolbar(title: title, condition: condition, reference: reference, newGame: newGame,
                                        hidesBackButton: hidesBackButton, hidesHowToPlay: hidesHowToPlay,
                                        actions: actions))
    }
}

/// ツールバー左（戻る）と中央（表示名）。**全ゲームで同じでなければならない部分**。
///
/// 戻るは OS 既定のものを隠して自前で置いている（`navigationBarBackButtonHidden`）。
/// 直前の画面名が入ると表示名の幅を圧迫するため。
@MainActor @ToolbarContentBuilder
private func gameChromeBarItems(title: String, condition: GameChromeCondition?, dismiss: DismissAction,
                                showsBack: Bool) -> some ToolbarContent {
    if showsBack {
        ToolbarItem(placement: .cancellationAction) {
            Button { dismiss() } label: { Label(tr("戻る"), systemImage: "chevron.left") }
        }
    }
    ToolbarItem(placement: .principal) {
        GameChromePrincipal(title: title, condition: condition)
    }
}

/// ナビバー中央の表示名。文字サイズ設定に追従させつつ、幅を超える分は縮めて 1 行に収める（#1469）。
/// `themeBody` は MainActor 隔離なので、非隔離の `ToolbarContentBuilder` 関数から直接は呼べず View に切り出している。
private struct GameChromeTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .themeBody(20, weight: .bold, maxScale: 1.5)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// ナビバー中央: 表示名と、その下の今の条件のチップ（#1690）。
///
/// チップは表示名の下に積む（バーは iOS 26 で 54pt・iOS 17 の SE で 44pt。20pt の題字 + 12pt のチップは収まる）。
/// 文字サイズが「アクセシビリティ」の段になったらチップを畳む（バーに収まらず題字が欠けるため。
/// 設定は「新規」ボタンからも開ける）。
private struct GameChromePrincipal: View {
    let title: String
    let condition: GameChromeCondition?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            GameChromeTitle(title: title)
            if let condition, !dynamicTypeSize.isAccessibilitySize {
                GameConditionChipFitting(condition: condition, ink: Theme.coralText)
            }
        }
    }
}

/// 背景・評価リクエスト・ナビバーの構成。ツールバーの中身より前に当てる。
///
/// `paintsBackground` は全画面の枠（`FullScreenGameChrome.swift`・#2531）が false で渡す。あちらは面（フェルト）を
/// 自分で画面全体に敷くので、ここで地の色を塗ると中身の範囲だけ地の色が面の上に乗ってしまう。
struct GameChromeBase: ViewModifier {
    let review: ReviewRequestService?
    var paintsBackground = true

    func body(content: Content) -> some View {
        content
            .background { if paintsBackground { Theme.background.ignoresSafeArea() } }
            .reviewRequestPrompt(review)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .modifier(NavigationBarBackgroundMatch())
            #endif
            .tint(Theme.coralText)
    }
}

private struct GameChromeToolbar: ViewModifier {
    let title: String
    let condition: GameChromeCondition?
    let reference: GameChromeReference?
    let newGame: GameChromeNewGame?
    let hidesBackButton: Bool
    let hidesHowToPlay: Bool
    let actions: [GameChromeAction]
    @State private var confirmsNewGame = false
    @State private var screenWidth: CGFloat = 0
    @State private var titleWidth: CGFloat = 0
    /// 文字サイズに追従するボタン幅の拡大率（標準で 1）。
    @ScaledMetric(relativeTo: .body) private var buttonScale: CGFloat = 1
    @Environment(\.dismiss) private var dismiss
    @Environment(\.howToPlayTrigger) private var howToPlay
    /// お気に入りの☆（#3478）。ハブから開いたときだけ環境にあり、右端（その他の後ろ）に置く。
    @Environment(\.favoriteGame) private var favorite
    @State private var favoriteToast: FavoriteHeaderToast?

    private var showsHowToPlay: Bool { howToPlay != nil && !hidesHowToPlay }

    /// ☆込みの数。狭い画面で「…」にまとめる判定（#3475）にも☆を数える。
    private var buttonCount: Int {
        (reference == nil ? 0 : 1) + (showsHowToPlay ? 1 : 0) + (newGame == nil ? 0 : 1) + actions.count
            + (favorite == nil ? 0 : 1)
    }

    /// 測れるまで（幅が 0 のあいだ）は並べたままにする。
    private var collapses: Bool {
        screenWidth > 0 && titleWidth > 0
            && GameChromeHeaderMetrics.shouldCollapse(titleWidth: titleWidth, screenWidth: screenWidth,
                                                      buttonCount: buttonCount, hasBackButton: !hidesBackButton,
                                                      buttonScale: buttonScale)
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
            // 題字の本来の幅を、縮めない隠した Text で測る（大きい文字サイズでも追従する）。
            .background(alignment: .topLeading) {
                GameChromeTitle(title: title).fixedSize().hidden().accessibilityHidden(true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { titleWidth = $0 }
            }
            .modifier(GameChromeNewGameConfirmation(newGame: newGame, isPresented: $confirmsNewGame))
            .modifier(FavoriteToastOverlay(toast: $favoriteToast)).toolbar {
                gameChromeBarItems(title: title, condition: condition, dismiss: dismiss, showsBack: !hidesBackButton)
                // `if / else` は古い Xcode の ToolbarContentBuilder で通らないので、`if` を 2 つに分ける。
                if collapses {
                    ToolbarItem(placement: .primaryAction) { overflowMenu }
                }
                // 並びはここで固定する: 役の早見表 → ？ → 新規 → その他。
                if !collapses, let reference {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: reference.action) {
                            Image(systemName: "list.bullet.rectangle")
                        }
                        .accessibilityLabel(reference.accessibilityLabel)
                    }
                }
                if !collapses, let howToPlay, !hidesHowToPlay {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: howToPlay.present) {
                            Image(systemName: "questionmark.circle")
                        }
                        .accessibilityLabel(tr("遊び方"))
                    }
                }
                if !collapses, let newGame {
                    ToolbarItem(placement: .primaryAction) {
                        Button { newGame.tapped { confirmsNewGame = true } } label: {
                            Image(systemName: newGame.kind.systemImage)
                        }
                        .accessibilityLabel(newGame.kind.accessibilityLabel)
                        .disabled(newGame.isDisabled)
                    }
                }
                if !collapses, !actions.isEmpty {
                    ToolbarItemGroup(placement: .primaryAction) {
                        ForEach(actions.indices, id: \.self) { index in
                            let item = actions[index]
                            Button(action: item.action) { Image(systemName: item.systemImage) }
                                .accessibilityLabel(item.title)
                                .disabled(item.isDisabled)
                        }
                    }
                }
                if !collapses, let favorite {
                    ToolbarItem(placement: .primaryAction) {
                        FavoriteToolbarButton(favorite: favorite) { favoriteToast = $0.toggle(source: .header) }
                    }
                }
            }
    }

    /// 狭い画面で、右のボタン全部を 1 つにまとめた「…」（#3475）。並びは並べたときと同じ固定順。
    /// 盤の右下の「⋯」（`GameOverflowBar`）とは別物で、合流させない。
    private var overflowMenu: some View {
        Menu {
            if let reference {
                Button(action: reference.action) {
                    Label(reference.accessibilityLabel, systemImage: "list.bullet.rectangle")
                }
            }
            if let howToPlay, !hidesHowToPlay {
                Button(action: howToPlay.present) { Label(tr("遊び方"), systemImage: "questionmark.circle") }
            }
            if let newGame {
                Button { newGame.tapped { confirmsNewGame = true } } label: {
                    Label(newGame.kind.accessibilityLabel, systemImage: newGame.kind.systemImage)
                }
                .disabled(newGame.isDisabled)
            }
            ForEach(actions.indices, id: \.self) { index in
                let item = actions[index]
                Button(action: item.action) { Label(item.title, systemImage: item.systemImage) }
                    .disabled(item.isDisabled)
            }
            if let favorite {
                Button { favoriteToast = favorite.toggle(source: .headerMenu) } label: {
                    Label(favorite.actionTitle, systemImage: favorite.isOn ? "star.fill" : "star")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(tr("メニュー"))
    }
}

/// ヘッダー右端の☆（#3478）。`isOn` を自分の `body` で読み、付け外しがすぐ見た目に出る。
private struct FavoriteToolbarButton: View {
    let favorite: FavoriteGameContext
    let onToggle: (FavoriteGameContext) -> Void

    var body: some View {
        Button { onToggle(favorite) } label: {
            FavoriteStar(isOn: favorite.isOn, size: 20)
        }
        .accessibilityLabel(favorite.actionTitle)
    }
}

#if os(iOS)
/// ナビバーの背景をコンテンツの背景色に揃える。
///
/// 可視性（`.visible`）は指定しない。常時不透明にすると、結果表示などの「画面全体を暗くする覆い」が
/// バーの手前まで届かず、バーだけ明るく残る（#1444 の CodeRabbit 指摘）。自動のままなら、
/// 先頭にいるあいだはバーが透けて背景と覆いがそのまま見え、スクロールしたときだけこの色で塗られる。
private struct NavigationBarBackgroundMatch: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(Theme.background, for: .navigationBar)
    }
}
#endif

public extension View {
    /// ナビバーの背景を隠し、背面の描画（3D の球場など）をバーの裏まで見せる（#1789）。
    ///
    /// 共通枠の `toolbarBackground`（自動）は、直前の画面でスクロール済みだとバーを塗った状態のまま
    /// 次の画面へ持ち越される。背景をバーの裏まで続ける画面だけがこれで隠す。
    /// 指定そのものは枠の中身なので、ゲーム側で `toolbarBackground` を直書きせずここを通す。
    @ViewBuilder
    func gameNavigationBarBackgroundHidden() -> some View {
        #if os(iOS)
        toolbarBackground(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}

// MARK: - 盤の下の操作エリア

/// 盤・場の下に置く操作エリア（#148・#528）。
///
/// 対局中と終局後で中身が入れ替わるが、**高さは常に終局後の最大構成に揃える**。
/// ここが伸び縮みすると、`aspectRatio` + `layoutPriority` で組んだ盤が帳尻合わせに縮み、
/// 決着した瞬間に盤が一段小さくなって見える。レコメンドは出るとは限らず×でも閉じられるため、
/// カードのぶんは常にひな形（`RecommendationCard.heightPlaceholder`）で確保しておく。
///
/// ひな形と実物で**同じ組み方**を通すのがこの型の主眼で、7 ゲームがそれぞれ同じ
/// `ZStack` + `finishedControls` を書き写していた。ひな形か実物の片方だけ直すと高さが揃わなくなる。
public struct GameControlArea<Result: View, Playing: View>: View {
    private let isFinished: Bool
    private let services: GameServices
    private let ladder: DifficultyLadderPrompt?
    private let showsPlayStreak: Bool
    private let result: () -> Result
    private let playing: () -> Playing

    /// - Parameters:
    ///   - isFinished: 決着してリザルトを出している状態か。
    ///   - services: レコメンドの取得元。
    ///   - ladder: 難易度の「階段」の提案（#722）。レコメンドと同じ枠に出る。
    ///   - result: 終局後に出す操作列（「もう一度」など）。高さのひな形にも同じものを使う。
    ///   - playing: 対局中に出す操作列。出すものが無い局面では空でよい。
    public init(
        isFinished: Bool,
        services: GameServices,
        ladder: DifficultyLadderPrompt? = nil,
        showsPlayStreak: Bool = true,
        @ViewBuilder result: @escaping () -> Result,
        @ViewBuilder playing: @escaping () -> Playing
    ) {
        self.isFinished = isFinished
        self.services = services
        self.ladder = ladder
        self.showsPlayStreak = showsPlayStreak
        self.result = result
        self.playing = playing
    }

    public var body: some View {
        // 対局中の操作（「⋯」の行・#1468）はひな形の**上端**（= 盤・札のすぐ下）に寄せる（#1485）。
        // 下端に寄せると「⋯」が盤から離れ、広告の上に浮いて見えた（会長 QA 2026-09-27）。
        // 余りの高さは「⋯」と広告のあいだに残る。決着後の中身もひな形と同じく上から積む。
        ZStack(alignment: .top) {
            finished { RecommendationCard.heightPlaceholder }
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if isFinished {
                finished {
                    RecommendationSlot(services: services, isFinished: true, ladder: ladder, showsPlayStreak: showsPlayStreak)
                }
            } else {
                playing()
            }
        }
    }

    /// 終局後に出すもの。高さの基準（ひな形）と実物で同じ組み方を使う。
    private func finished<Recommendation: View>(
        @ViewBuilder recommendation: () -> Recommendation
    ) -> some View {
        VStack(spacing: 8) {
            result()
            recommendation()
        }
    }
}
