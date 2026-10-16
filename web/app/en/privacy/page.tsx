import type { Metadata } from "next";

/// プライバシーポリシー（`app/(ja)/privacy/page.tsx`）の英語訳（#2170）。日本語版を改定したらこちらも同じ内容に直すこと。
/// 中身は日本語版と同じにし、訳で足したり削ったりしない。設定項目名はアプリの英語表示に合わせる。
export const metadata: Metadata = {
  title: "Privacy Policy",
  alternates: { canonical: "/en/privacy", languages: { ja: "/privacy", en: "/en/privacy" } },
};

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mb-10">
      <h2 className="text-lg font-bold text-gray-900 dark:text-white mb-3 pb-2 border-b border-gray-200 dark:border-gray-700">{title}</h2>
      <div className="text-gray-700 dark:text-gray-300 leading-relaxed space-y-3">{children}</div>
    </section>
  );
}

export default function PrivacyPageEn() {
  return (
    <div>
      <div className="mb-8">
        <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-2">Privacy Policy</h1>
        <p className="text-sm text-gray-400">Last updated: October 9, 2026</p>
      </div>

      <div className="bg-orange-50 dark:bg-orange-950 border border-orange-200 dark:border-orange-900 rounded-xl p-5 mb-10 text-sm text-orange-800 dark:text-orange-300 leading-relaxed">
        We value the privacy of everyone who uses the Asobiba app (the &quot;App&quot;).
        This policy explains how we collect and use information.
      </div>

      <Section title="1. Information We Collect">
        <p>The App may collect the following information.</p>
        <ul className="list-disc pl-5 space-y-1">
          <li>Device identifiers used to deliver ads (advertising ID)</li>
          <li>Anonymous statistics about how the App is used (such as the games played, play time and results; this does not include information that identifies you personally)</li>
          <li>When a crash or bug occurs, diagnostic information used to improve the App&apos;s stability (such as the device model, OS version and where the problem occurred)</li>
          <li>To optimize ad delivery, Google&apos;s advertising and analytics SDKs may use your approximate location (at roughly the city level)</li>
          <li>If you are signed in to Game Center, your scores, leaderboards and achievements (sent and displayed through Apple&apos;s Game Center service)</li>
        </ul>
        <p>
          On Game Center leaderboards, the nickname (display name) and avatar set in Game Center, along with your score, are also shown to other players viewing the same leaderboard.
          What is shown follows your Apple Game Center settings, and the App does not add any other name or information.
          Signing in to Game Center and taking part in leaderboards are optional, and you can play every game as usual without signing in.
        </p>
        <p className="mt-2">
          We never collect information that directly identifies you, such as your name, address or email address.
        </p>
      </Section>

      <Section title="2. Storage of Game Data">
        <p>
          Progress and settings for each game are stored only on your device.
        </p>
        <p>
          Records such as best scores are sent to Apple&apos;s servers only if you are signed in to Game Center (if you are not signed in, they are stored only on your device).
        </p>
        <p>
          Notifications such as reminders to continue a game you left unfinished, reminders when you haven&apos;t played in a while, and alerts when your plays have been restored are local notifications processed on your device. No information is sent to external servers for these notifications. You only receive notifications if you allow them in the iOS permission dialog, and you can turn them off at any time in iOS Settings.
        </p>
        <p>
          The App can generally be used without an internet connection, but a connection is required to display ads, send statistics and connect to Game Center.
        </p>
      </Section>

      <Section title="3. External Services We Use">
        <p>The App uses the following external services.</p>
        <ul className="list-disc pl-5 space-y-2">
          <li>
            <span className="font-semibold">Google AdMob</span> (ad delivery: banner ads, large banner ads and rewarded video ads): may use information such as your advertising ID to show more relevant ads.
          </li>
          <li>
            <span className="font-semibold">Firebase Analytics</span> (Google): collects data on how the App is used, as the anonymous statistics described in section 1 above.
          </li>
          <li>
            <span className="font-semibold">Firebase Crashlytics</span> (Google): when a crash occurs, automatically sends diagnostic information used to improve the App&apos;s stability. This diagnostic information continues to be sent even if you turn off &quot;Share Usage Data&quot; in Settings.
          </li>
          <li>
            <span className="font-semibold">Apple Game Center</span>: if you are signed in, used to send and display scores and achievements. Because it is based on your Apple account, the App does not separately keep this information. The content and availability of leaderboards may change due to the specifications of Apple&apos;s service or updates to the App, and leaderboards may be changed or discontinued without notice.
          </li>
        </ul>
        <p>
          On iOS, we may ask for your permission to track you under App Tracking Transparency (ATT).
          If you do not allow tracking, you can still use all features without restriction. Even after allowing it, you can change this at any time in iOS Settings. Turning off the App&apos;s &quot;Share Usage Data&quot; setting stops statistics from being sent through Firebase Analytics.
        </p>
        <p>
          Please see{" "}
          <a
            href="https://policies.google.com/privacy"
            className="text-orange-500 underline"
            target="_blank"
            rel="noopener noreferrer"
          >
            Google&apos;s Privacy Policy
          </a>
          {" "}and{" "}
          <a
            href="https://www.apple.com/legal/privacy/"
            className="text-orange-500 underline"
            target="_blank"
            rel="noopener noreferrer"
          >
            Apple&apos;s Privacy Policy
          </a>
          .
        </p>
      </Section>

      <Section title="4. Disclosure to Third Parties">
        <p>
          Except in the following cases, we do not sell, rent or provide the information we collect to third parties.
        </p>
        <ul className="list-disc pl-5 space-y-1">
          <li>When disclosure is required by law</li>
          <li>When shared with Google AdMob to deliver ads (within the scope described in section 3 above)</li>
          <li>When shared with Google (Firebase Analytics and Crashlytics) to analyze usage and improve the App&apos;s stability (within the scope described in section 3 above)</li>
          <li>When shared with Apple (Game Center) to record and display scores and achievements (only if you are signed in)</li>
        </ul>
      </Section>

      <Section title="5. Children's Privacy">
        <p>
          The App does not knowingly collect personal information from children under the age of 13.
          If we learn that a child has provided personal information, we will delete it promptly.
        </p>
      </Section>

      <Section title="6. Security">
        <p>
          We strive to manage personal information appropriately, but we do not guarantee that any method of
          transmission over the internet or method of electronic storage is 100% secure.
        </p>
      </Section>

      <Section title="7. Changes to This Policy">
        <p>
          This policy may be changed as necessary.
          The revised policy takes effect when it is posted on this page.
        </p>
      </Section>

      <Section title="8. Revision History">
        <ul className="list-disc pl-5 space-y-1">
          <li>October 9, 2026: Added how display names and scores are shown on Game Center leaderboards, changes to and discontinuation of leaderboards, the types of ads, and a description of notifications</li>
          <li>September 23, 2026: Updated the content to match the current implementation</li>
        </ul>
      </Section>

      <Section title="9. Contact">
        <p>For questions or requests regarding this policy, please contact us at the address below.</p>
        <p>
          <a href="mailto:hirockysan1983@gmail.com" className="text-orange-500 underline">
            hirockysan1983@gmail.com
          </a>
        </p>
      </Section>
    </div>
  );
}
