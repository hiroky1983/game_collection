import type { Metadata } from "next";
import Link from "next/link";
import { games } from "../lib/games";
import {
  APP_STORE_URL_GLOBAL,
  MIN_IOS_VERSION,
  SITE_NAME_EN,
  SITE_URL,
} from "../lib/site";
import GameMark from "../components/GameMark";

/// LP トップの英語版（#2170）。構成と書いてある事実は日本語トップ（`app/(ja)/page.tsx`）に揃える。
/// 日本語側に無い主張は足さないこと。本数・ゲーム名は日本語側と同じく `games` から導出する。
/// ゲーム別ページ（/games/<slug>）は日本語のみなので、一覧のカードはリンクにしない。
export const metadata: Metadata = {
  alternates: { canonical: "/en", languages: { ja: "/", en: "/en" } },
};

const releasedGames = games.filter((g) => !g.comingSoon);
const upcomingGames = games.filter((g) => g.comingSoon);
const gameCount = releasedGames.length;
const gameNames = releasedGames.map((g) => g.nameEn).join(", ");

const points = [
  { icon: "✈️", title: "Play offline", desc: `No connection needed. All ${gameCount} games work even where there's no signal` },
  { icon: "🔓", title: "No sign-up, no login", desc: "Install it and start playing right away. There's no account to create" },
  {
    icon: "🧺",
    title: `${gameCount} games in one app`,
    desc: "No need to find and install each game separately. It takes up just one app on your home screen",
  },
  {
    icon: "🤫",
    title: "Low-key ads",
    desc: "Mostly a banner at the bottom of the screen. Full-screen ads only appear when you choose to use Undo or Continue",
  },
];

/// 検索エンジンにアプリとして認識させるための構造化データ（日本語トップと同じ形）。
const jsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: SITE_NAME_EN,
  description: `An iPhone game collection with ${gameCount} games (${gameNames}). Play offline, with no sign-up needed.`,
  applicationCategory: "GameApplication",
  operatingSystem: `iOS ${MIN_IOS_VERSION}+`,
  url: `${SITE_URL}/en`,
  installUrl: APP_STORE_URL_GLOBAL,
  inLanguage: "en",
  offers: {
    "@type": "Offer",
    price: "0",
    priceCurrency: "USD",
  },
};

export default function EnglishHome() {
  return (
    <div>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />

      <div className="text-center py-10 mb-10">
        <div className="text-6xl mb-4">🎮</div>
        <h1 className="text-4xl font-bold text-gray-900 dark:text-white mb-3">{SITE_NAME_EN}</h1>
        <p className="text-gray-500 dark:text-gray-400 text-lg">
          {gameCount} classic games in one app
        </p>
        <p className="text-gray-500 dark:text-gray-400 mt-3 leading-relaxed">
          {gameNames}, all in one app.{" "}
          <strong className="font-semibold text-gray-700 dark:text-gray-200">
            Every game works offline, with no internet connection or sign-up needed
          </strong>
          . Ads are kept low-key.
        </p>
        <a
          href={APP_STORE_URL_GLOBAL}
          className="inline-block mt-6 bg-black dark:bg-white text-white dark:text-black text-sm font-semibold px-6 py-3 rounded-full hover:bg-gray-800 dark:hover:bg-gray-200 transition-colors"
        >
          Download on the App Store (Free)
        </a>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-12">
        {points.map((p) => (
          <div
            key={p.title}
            className="bg-white dark:bg-gray-800 rounded-2xl px-5 py-4 shadow-sm border border-gray-100 dark:border-gray-700"
          >
            <p className="font-bold text-gray-900 dark:text-white">
              <span className="mr-2">{p.icon}</span>
              {p.title}
            </p>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">{p.desc}</p>
          </div>
        ))}
      </div>

      <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-4">Games ({gameCount})</h2>
      <div className="grid grid-cols-1 gap-3 mb-12">
        {releasedGames.map((g) => (
          <div
            key={g.slug}
            className="bg-white dark:bg-gray-800 rounded-2xl px-5 py-4 flex items-center gap-4 shadow-sm border border-gray-100 dark:border-gray-700"
          >
            <GameMark game={g} scale={3} className="text-3xl" />
            <div>
              <p className="font-bold text-gray-900 dark:text-white">{g.nameEn}</p>
              <p className="text-sm text-gray-500 dark:text-gray-400">{g.taglineEn}</p>
            </div>
          </div>
        ))}
      </div>

      {upcomingGames.length > 0 && (
        <>
          <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-1">Coming soon</h2>
          <p className="text-sm text-gray-500 dark:text-gray-400 mb-4">
            Coming in the next update (not yet included in the current version of the app).
          </p>
          <div className="grid grid-cols-1 gap-3 mb-12">
            {upcomingGames.map((g) => (
              <div
                key={g.slug}
                className="bg-white dark:bg-gray-800 rounded-2xl px-5 py-4 flex items-center gap-4 shadow-sm border border-gray-100 dark:border-gray-700"
              >
                <GameMark game={g} scale={3} className="text-3xl" />
                <div>
                  <p className="font-bold text-gray-900 dark:text-white">
                    {g.nameEn}
                    <span className="ml-2 align-middle text-xs font-semibold text-orange-600 dark:text-orange-400 border border-orange-300 dark:border-orange-700 rounded-full px-2 py-0.5">
                      Coming soon
                    </span>
                  </p>
                  <p className="text-sm text-gray-500 dark:text-gray-400">{g.taglineEn}</p>
                </div>
              </div>
            ))}
          </div>
        </>
      )}

      <div className="text-center mb-12">
        <a
          href={APP_STORE_URL_GLOBAL}
          className="inline-block bg-orange-500 text-white text-sm font-semibold px-6 py-3 rounded-full hover:bg-orange-600 transition-colors"
        >
          Get {SITE_NAME_EN} on the App Store
        </a>
      </div>

      <div className="flex justify-center gap-8 text-sm">
        <Link href="/en/privacy" className="text-orange-500 hover:underline">Privacy Policy</Link>
        <Link href="/en/terms" className="text-orange-500 hover:underline">Terms of Use</Link>
      </div>
    </div>
  );
}
