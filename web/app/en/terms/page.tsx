import type { Metadata } from "next";

/// 利用規約（`app/(ja)/terms/page.tsx`）の英語訳（#2170）。日本語版を改定したらこちらも同じ内容に直すこと。
/// 法的な中身は日本語版と同じにし、訳で足したり削ったりしない。
export const metadata: Metadata = {
  title: "Terms of Use",
  alternates: { canonical: "/en/terms", languages: { ja: "/terms", en: "/en/terms" } },
};

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mb-10">
      <h2 className="text-lg font-bold text-gray-900 dark:text-white mb-3 pb-2 border-b border-gray-200 dark:border-gray-700">{title}</h2>
      <div className="text-gray-700 dark:text-gray-300 leading-relaxed space-y-3">{children}</div>
    </section>
  );
}

export default function TermsPageEn() {
  return (
    <div>
      <div className="mb-8">
        <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-2">Terms of Use</h1>
        <p className="text-sm text-gray-400">Last updated: October 9, 2026</p>
      </div>

      <div className="bg-orange-50 dark:bg-orange-950 border border-orange-200 dark:border-orange-900 rounded-xl p-5 mb-10 text-sm text-orange-800 dark:text-orange-300 leading-relaxed">
        By using the Asobiba app (the &quot;App&quot;), you are deemed to have agreed to these Terms of Use.
        Please be sure to read them before using the App.
      </div>

      <Section title="1. About the App">
        <p>
          Asobiba is a game collection app that brings together games in a variety of genres, such as card games,
          board games like shogi and chess, and puzzles (for example: card games, board games and puzzles). The
          games included may be added to or changed in future updates. The App can be used on devices running
          iOS 17.0 or later.
        </p>
      </Section>

      <Section title="2. Conditions of Use">
        <ul className="list-disc pl-5 space-y-1">
          <li>The App may be used for personal, non-commercial purposes only.</li>
          <li>An Apple ID may be required to use the App.</li>
          <li>You can enjoy the games without an internet connection, but a connection may be required to display ads.</li>
          <li>
            The points and chips used in some games (such as Poker and Blackjack) are virtual items that can be used
            only within the games. They cannot be exchanged for cash or anything of monetary value, or redeemed in
            any way. Chips cannot be purchased with real money.
            If you run out of chips, they may be restored by watching a rewarded ad.
          </li>
          <li>
            If you are signed in to Apple&apos;s Game Center, you can use scores, achievements and leaderboards. Signing in
            is optional, and you can play every game without signing in. On leaderboards, your Game Center nickname
            (display name) and score are also shown to other players.
            Apple&apos;s terms of use apply to your use of Game Center.
          </li>
          <li>
            Leaderboards (including weekly and limited-time leaderboards) may be changed, have their rankings reset, or
            be discontinued without notice. We do not guarantee leaderboard rankings or records, and there are no
            prizes or rewards for leaderboards. Scores that we determine to have been submitted by illegitimate means
            may be removed from leaderboards.
          </li>
        </ul>
      </Section>

      <Section title="3. Prohibited Conduct">
        <p>The following conduct is prohibited.</p>
        <ul className="list-disc pl-5 space-y-1">
          <li>Reverse engineering, decompiling, modifying or copying the App</li>
          <li>Using or redistributing the App for commercial purposes</li>
          <li>Altering game data by illegitimate means, or submitting illegitimate scores to leaderboards</li>
          <li>Any conduct that violates laws or regulations, or public order and morals</li>
          <li>Any conduct that infringes the rights of the developer or any third party</li>
        </ul>
      </Section>

      <Section title="4. Intellectual Property">
        <p>
          The copyright and all other intellectual property rights in all content included in the App (text,
          graphics, sounds, code, etc.) belong to the developer.
          These Terms grant you only a non-exclusive, non-transferable license to use the App for personal purposes.
        </p>
      </Section>

      <Section title="5. Disclaimer">
        <ul className="list-disc pl-5 space-y-1">
          <li>The App is provided &quot;as is.&quot; We do not guarantee that it will operate completely or accurately.</li>
          <li>The developer accepts no liability whatsoever for any damage arising from the use of the App (such as loss of data or device failure).</li>
          <li>Features of the App may be added, changed, suspended or discontinued without notice.</li>
          <li>The developer is not liable for any damage arising from the use of third-party services (such as Google AdMob, Firebase and Apple Game Center).</li>
        </ul>
      </Section>

      <Section title="6. Updates to and Discontinuation of the App">
        <p>
          The developer reserves the right to update, change or discontinue the App at any time.
          The developer is not liable for any damage resulting from the discontinuation of the App.
        </p>
      </Section>

      <Section title="7. Changes to These Terms">
        <p>
          These Terms may be changed without notice.
          If you continue to use the App after a change, you are deemed to have agreed to the revised Terms.
          If there are significant changes, we will announce them in the App or on this page.
        </p>
      </Section>

      <Section title="8. Governing Law and Jurisdiction">
        <p>
          These Terms are governed by and construed in accordance with the laws of Japan.
          The Tokyo District Court shall have exclusive jurisdiction by agreement as the court of first instance
          for any dispute relating to the App.
        </p>
      </Section>

      <Section title="9. Revision History">
        <ul className="list-disc pl-5 space-y-1">
          <li>October 9, 2026: Added the use of Game Center and leaderboards, changes to and discontinuation of leaderboards, and the prohibition on submitting illegitimate scores</li>
          <li>September 23, 2026: Updated the description of the included games and of in-game chips and rewarded ads</li>
        </ul>
      </Section>

      <Section title="10. Contact">
        <p>For questions or requests regarding these Terms, please contact us at the address below.</p>
        <p>
          <a href="mailto:hirockysan1983@gmail.com" className="text-orange-500 underline">
            hirockysan1983@gmail.com
          </a>
        </p>
      </Section>
    </div>
  );
}
