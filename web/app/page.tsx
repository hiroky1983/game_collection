import Link from "next/link";
import { games } from "./lib/games";
import {
  APP_SIZE_MB,
  APP_STORE_URL,
  MIN_IOS_VERSION,
  SITE_NAME,
  SITE_URL,
} from "./lib/site";

const points = [
  { icon: "✈️", title: "オフラインで遊べる", desc: "通信不要。電波の無い場所でも8本すべて動きます" },
  { icon: "🔓", title: "登録もログインも不要", desc: "入れてすぐ遊べます。アカウント作成はありません" },
  { icon: "🪶", title: `約${APP_SIZE_MB}と軽い`, desc: "ダウンロードもインストールもすぐ終わります" },
  {
    icon: "🤫",
    title: "広告は控えめ",
    desc: "画面下のバナーが中心。全画面広告は「待った」やコンティニューを自分で選んだときだけです",
  },
];

/// 検索エンジンにアプリとして認識させるための構造化データ。
const jsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: SITE_NAME,
  description: `将棋・2048・五目並べ・マインスイーパー・オセロ・ポーカー・神経衰弱・ブラックジャックの8つを収録した iPhone 用ゲームコレクション。オフラインで遊べて、会員登録も不要。`,
  applicationCategory: "GameApplication",
  operatingSystem: `iOS ${MIN_IOS_VERSION}+`,
  url: SITE_URL,
  installUrl: APP_STORE_URL,
  inLanguage: "ja",
  offers: {
    "@type": "Offer",
    price: "0",
    priceCurrency: "JPY",
  },
};

export default function Home() {
  return (
    <div>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />

      <div className="text-center py-10 mb-10">
        <div className="text-6xl mb-4">🎮</div>
        <h1 className="text-4xl font-bold text-gray-900 dark:text-white mb-3">あそびば</h1>
        <p className="text-gray-500 dark:text-gray-400 text-lg">
          定番ゲーム8種の詰め合わせ
        </p>
        <p className="text-gray-500 dark:text-gray-400 mt-3 leading-relaxed">
          将棋・2048・五目並べ・マインスイーパー・オセロ・ポーカー・神経衰弱・ブラックジャックを1本に。
          <strong className="font-semibold text-gray-700 dark:text-gray-200">
            すべてオフラインで遊べて、通信も会員登録も不要
          </strong>
          。広告は控えめ、アプリは約{APP_SIZE_MB}と軽量です。
        </p>
        <a
          href={APP_STORE_URL}
          className="inline-block mt-6 bg-black dark:bg-white text-white dark:text-black text-sm font-semibold px-6 py-3 rounded-full hover:bg-gray-800 dark:hover:bg-gray-200 transition-colors"
        >
          App Storeでダウンロード（無料）
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

      <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-4">収録ゲーム（8本）</h2>
      <div className="grid grid-cols-1 gap-3 mb-12">
        {games.map((g) => (
          <Link
            key={g.slug}
            href={`/games/${g.slug}`}
            className="bg-white dark:bg-gray-800 rounded-2xl px-5 py-4 flex items-center gap-4 shadow-sm border border-gray-100 dark:border-gray-700 hover:border-orange-300 dark:hover:border-orange-700 transition-colors"
          >
            <span className="text-3xl">{g.emoji}</span>
            <div>
              <p className="font-bold text-gray-900 dark:text-white">{g.name}</p>
              <p className="text-sm text-gray-500 dark:text-gray-400">{g.tagline}</p>
            </div>
          </Link>
        ))}
      </div>

      <div className="text-center mb-12">
        <a
          href={APP_STORE_URL}
          className="inline-block bg-orange-500 text-white text-sm font-semibold px-6 py-3 rounded-full hover:bg-orange-600 transition-colors"
        >
          App Storeで「あそびば」を入手
        </a>
      </div>

      <div className="flex justify-center gap-8 text-sm">
        <Link href="/privacy" className="text-orange-500 hover:underline">プライバシーポリシー</Link>
        <Link href="/terms" className="text-orange-500 hover:underline">利用規約</Link>
      </div>
    </div>
  );
}
