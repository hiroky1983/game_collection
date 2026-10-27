import Testing
import SwiftUI
@testable import Core

/// 図で見る「はじめての遊び方」の共通部品（#2827）。
@MainActor
@Suite("はじめての遊び方: 共通部品")
struct OnboardingGuideTests {
    private func page(lines: Int = 2) -> OnboardingPage {
        OnboardingPage(heading: "見出し", lines: Array(repeating: "言葉", count: lines)) { AnyView(EmptyView()) }
    }

    private func guide(pages: Int, lines: Int = 2) -> OnboardingGuide {
        OnboardingGuide(gameID: "x", title: "題名", pages: Array(repeating: page(lines: lines), count: pages))
    }

    @Test("カードは 4〜6 枚・1 枚の言葉は 2〜3 行だけが型に合う")
    func wellFormedBounds() {
        #expect(guide(pages: 4).isWellFormed)
        #expect(guide(pages: 6, lines: 3).isWellFormed)
        #expect(!guide(pages: 3).isWellFormed)
        #expect(!guide(pages: 7).isWellFormed)
        #expect(!guide(pages: 5, lines: 1).isWellFormed)
        #expect(!guide(pages: 5, lines: 4).isWellFormed)
    }

    @Test("入口は「はじめての遊び方」を持つゲームの遊び方だけに付く")
    func onlyGamesWithOnboardingHaveEntry() {
        let withGuide = HowToPlayGuide.chess.onboarding(guide(pages: 4))
        #expect(withGuide.onboarding != nil)
        #expect(HowToPlayGuide.shogi.onboarding == nil)
        // 図を差し込んでも中身は消えない。
        let illustrated = withGuide.illustrated(HowToPlayGuide.chess.items.map { _ in { AnyView(EmptyView()) } })
        #expect(illustrated.onboarding == withGuide.onboarding)
        // 中身の有無は等しさにも効く。
        #expect(withGuide != HowToPlayGuide.chess)
    }

    @Test("全部の文言（題名・見出し・言葉）が texts に出る")
    func textsListsEverything() {
        #expect(guide(pages: 4).texts.count == 1 + 4 * 3)
    }

    @Test("共通部品の文言に英語の訳がある")
    func chromeTextsHaveEnglish() {
        for key in ["はじめての遊び方（図で見る）", "次へ", "前へ", "閉じる", "%1$lld / %2$lld"] {
            #expect(Core.tr.hasTranslation(key, language: .english), "「\(key)」に英語の訳が無い")
        }
    }

    /// v1.1.14 では隠していた入口を v1.1.15 で出し直した（#3002）。切り替えは `isAvailable` の 1 か所だけ。
    @Test("v1.1.15 では入口を出す（#3002）")
    func entryShownForV1115() {
        #expect(OnboardingGuide.isAvailable)
    }

    /// 入口が出ているとき、ガイドを持つゲームはボタンの分だけ描かれ、ガイドが無いゲーム
    /// （`OnboardingEntry(nil, ...)`）は 0 サイズのままであること。
    @Test("ガイドがあれば入口が描かれ、無ければ何も描かれない")
    @MainActor
    func entryRendersOnlyWithGuide() {
        for style: OnboardingEntry.Style in [.prominent, .compact] {
            let withGuideRenderer = ImageRenderer(content: OnboardingEntry(guide(pages: 4), style: style).fixedSize())
            withGuideRenderer.scale = 1
            let withoutGuideRenderer = ImageRenderer(content: OnboardingEntry(nil, style: style).fixedSize())
            withoutGuideRenderer.scale = 1

            #expect((withGuideRenderer.cgImage?.height ?? 0) > 0)
            #expect((withoutGuideRenderer.cgImage?.height ?? 0) == 0)
        }
    }
}
