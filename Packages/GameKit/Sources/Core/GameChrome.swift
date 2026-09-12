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

public extension View {
    /// ゲーム画面の共通枠を当てる（背景・評価リクエスト・ナビバー・戻る・タイトル）。
    ///
    /// - Parameters:
    ///   - title: ナビゲーションバー中央に出す表示名。
    ///   - review: 評価リクエストの実行をこの画面に紐づける（`GameServices.review`）。
    ///   - tint: ツールバーのボタンの色。既定は `Theme.coral`。
    ///   - matchesNavigationBarBackground: ナビバーの背景をコンテンツの背景色に揃えるか。
    ///     既定の白い帯がクリーム色のコンテンツと食い違い、画面上部だけ白く見えるという
    ///     会長指摘を受けて麻雀に入れたもの。**現状これを立てているのは麻雀だけ**で、
    ///     他ゲームは既定の帯のまま。見た目を変えないための引数なので、全ゲームで揃えるかは
    ///     別途決めること（この差自体が #528 の言う「ばらつき」の一例）。
    ///   - actions: ツールバー右側に置くゲーム固有の操作。
    func gameChrome<Actions: ToolbarContent>(
        title: String,
        review: ReviewRequestService?,
        tint: Color = Theme.coral,
        matchesNavigationBarBackground: Bool = false,
        @ToolbarContentBuilder actions: () -> Actions
    ) -> some View {
        modifier(GameChromeBase(review: review, tint: tint,
                                matchesNavigationBarBackground: matchesNavigationBarBackground))
            .modifier(GameChromeToolbar(title: title, actions: actions()))
    }

    /// ツールバー右側に何も置かないゲーム用（ブラックジャックなど）。
    func gameChrome(
        title: String,
        review: ReviewRequestService?,
        tint: Color = Theme.coral,
        matchesNavigationBarBackground: Bool = false
    ) -> some View {
        modifier(GameChromeBase(review: review, tint: tint,
                                matchesNavigationBarBackground: matchesNavigationBarBackground))
            .modifier(GameChromeToolbarOnly(title: title))
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
        Text(title)
            .font(.system(size: 20, weight: .bold, design: .rounded))
    }
}

/// 背景・評価リクエスト・ナビバーの構成。ツールバーの中身より前に当てる。
private struct GameChromeBase: ViewModifier {
    let review: ReviewRequestService?
    let tint: Color
    let matchesNavigationBarBackground: Bool

    func body(content: Content) -> some View {
        content
            .popBackground()
            .reviewRequestPrompt(review)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .modifier(NavigationBarBackgroundMatch(isEnabled: matchesNavigationBarBackground))
            #endif
            .tint(tint)
    }
}

private struct GameChromeToolbar<Actions: ToolbarContent>: ViewModifier {
    let title: String
    let actions: Actions
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.toolbar {
            gameChromeBarItems(title: title, dismiss: dismiss)
            actions
        }
    }
}

private struct GameChromeToolbarOnly: ViewModifier {
    let title: String
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.toolbar {
            gameChromeBarItems(title: title, dismiss: dismiss)
        }
    }
}

#if os(iOS)
/// ナビバーの背景をコンテンツの背景色に揃える（立てたときだけ）。
private struct NavigationBarBackgroundMatch: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .toolbarBackground(Theme.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            content
        }
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
    private let result: () -> Result
    private let playing: () -> Playing

    /// - Parameters:
    ///   - isFinished: 決着してリザルトを出している状態か。
    ///   - services: レコメンドの取得元。
    ///   - result: 終局後に出す操作列（「もう一度」など）。高さのひな形にも同じものを使う。
    ///   - playing: 対局中に出す操作列。出すものが無い局面では空でよい。
    public init(
        isFinished: Bool,
        services: GameServices,
        @ViewBuilder result: @escaping () -> Result,
        @ViewBuilder playing: @escaping () -> Playing
    ) {
        self.isFinished = isFinished
        self.services = services
        self.result = result
        self.playing = playing
    }

    public var body: some View {
        ZStack(alignment: .top) {
            finished { RecommendationCard.heightPlaceholder }
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if isFinished {
                finished {
                    RecommendationSlot(services: services, isFinished: true)
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
