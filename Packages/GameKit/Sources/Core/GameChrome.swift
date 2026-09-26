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
    public init(_ accessibilityLabel: String = "役の早見表", action: @escaping () -> Void) {
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }
}

/// ヘッダー右の「新規」ボタン（#1418）。種類ごとに絵柄と読み上げ名が決まる（会長決裁 #1011）。
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
            case .match: "新規対局"
            case .solo: "新規ゲーム"
            case .restart: "はじめから"
            }
        }

        var systemImage: String {
            switch self {
            case .match, .solo: "plus.circle.fill"
            case .restart: "arrow.clockwise"
            }
        }
    }

    let kind: Kind
    let isDisabled: Bool
    let action: () -> Void

    public init(_ kind: Kind, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.kind = kind
        self.isDisabled = isDisabled
        self.action = action
    }
}

public extension View {
    /// ゲーム画面の共通枠を当てる（背景・評価リクエスト・ナビバー・戻る・タイトル）。
    ///
    /// - Parameters:
    ///   - title: ナビゲーションバー中央に出す表示名。
    ///   - review: 評価リクエストの実行をこの画面に紐づける（`GameServices.review`）。
    ///   - reference: 役の早見表。あるゲームだけ渡す。
    ///   - newGame: 新規ボタン。あるゲームだけ渡す。
    ///   - actions: 上の 2 つに収まらないゲーム固有の操作（難易度・盤面選択メニューなど）。最後尾に並ぶ。
    ///
    /// ヘッダー右の並びは **役の早見表 → `?`（`.howToPlay`）→ 新規 → その他** で固定し、
    /// ゲーム側からは変えられない（#1418。並びが各ゲームの書き方しだいだった）。
    ///
    /// ナビバーの背景は全ゲームで画面の背景色（`Theme.background`）に揃え、ツールバーのボタンは
    /// `Theme.coral` に固定する（#1412・会長決裁 2026-09-25。既定の白い帯がクリーム色の画面と
    /// 食い違う、神経衰弱だけボタンが紫、というばらつきを引数ごと無くした）。
    func gameChrome<Actions: ToolbarContent>(
        title: String,
        review: ReviewRequestService?,
        reference: GameChromeReference? = nil,
        newGame: GameChromeNewGame? = nil,
        @ToolbarContentBuilder actions: () -> Actions
    ) -> some View {
        modifier(GameChromeBase(review: review))
            .modifier(GameChromeToolbar(title: title, reference: reference, newGame: newGame, actions: actions()))
    }

    /// ゲーム固有の操作が無いゲーム用。
    func gameChrome(
        title: String,
        review: ReviewRequestService?,
        reference: GameChromeReference? = nil,
        newGame: GameChromeNewGame? = nil
    ) -> some View {
        modifier(GameChromeBase(review: review))
            .modifier(GameChromeToolbar<ToolbarItem<Void, EmptyView>>(
                title: title, reference: reference, newGame: newGame, actions: nil))
    }
}

/// ツールバー左（戻る）と中央（表示名）。**全ゲームで同じでなければならない部分**。
///
/// 戻るは OS 既定のものを隠して自前で置いている（`navigationBarBackButtonHidden`）。
/// 直前の画面名が入ると表示名の幅を圧迫するため。
@ToolbarContentBuilder
private func gameChromeBarItems(title: String, dismiss: DismissAction) -> some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
        Button { dismiss() } label: { Label("戻る", systemImage: "chevron.left") }
    }
    ToolbarItem(placement: .principal) {
        GameChromeTitle(title: title)
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

/// 背景・評価リクエスト・ナビバーの構成。ツールバーの中身より前に当てる。
private struct GameChromeBase: ViewModifier {
    let review: ReviewRequestService?

    func body(content: Content) -> some View {
        content
            .popBackground()
            .reviewRequestPrompt(review)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .modifier(NavigationBarBackgroundMatch())
            #endif
            .tint(Theme.coral)
    }
}

private struct GameChromeToolbar<Actions: ToolbarContent>: ViewModifier {
    let title: String
    let reference: GameChromeReference?
    let newGame: GameChromeNewGame?
    let actions: Actions?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.howToPlayTrigger) private var howToPlay

    func body(content: Content) -> some View {
        content.toolbar {
            gameChromeBarItems(title: title, dismiss: dismiss)
            // 並びはここで固定する: 役の早見表 → ？ → 新規 → その他。
            if let reference {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: reference.action) {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .accessibilityLabel(reference.accessibilityLabel)
                }
            }
            if let howToPlay {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: howToPlay.present) {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("遊び方")
                }
            }
            if let newGame {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: newGame.action) {
                        Image(systemName: newGame.kind.systemImage)
                    }
                    .accessibilityLabel(newGame.kind.accessibilityLabel)
                    .disabled(newGame.isDisabled)
                }
            }
            if let actions {
                actions
            }
        }
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
        @ViewBuilder result: @escaping () -> Result,
        @ViewBuilder playing: @escaping () -> Playing
    ) {
        self.isFinished = isFinished
        self.services = services
        self.ladder = ladder
        self.result = result
        self.playing = playing
    }

    public var body: some View {
        // 対局中の操作（右下の「⋯」・#1468）は、ひな形の高さの**下端**（= 広告バナーの直上）に寄せる。
        // 上端に置くと、ゲームごとに「⋯」の高さがひな形の余りぶんずれる。決着後の中身はひな形と同じ高さなので、
        // 寄せる向きは終局後の見た目に影響しない。
        ZStack(alignment: .bottom) {
            finished { RecommendationCard.heightPlaceholder }
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if isFinished {
                finished {
                    RecommendationSlot(services: services, isFinished: true, ladder: ladder)
                }
                // 決着後は従来どおり上寄せ（レコメンドが無い局で「もう一度」が下へ寄らない）。
                .frame(maxHeight: .infinity, alignment: .top)
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
