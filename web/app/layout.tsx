import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";
import { games } from "./lib/games";
import { APP_SIZE_MB, APP_STORE_URL, SITE_NAME, SITE_URL } from "./lib/site";

/// 収録本数とゲーム名は `games` から導出する（`app/page.tsx` と同じ理由。本数をベタ書きしない）。
/// 「収録◯種」と数えてよいのは配信済み（`comingSoon` 無し）のものだけ（2026-08-28・会長指示）。
const releasedGames = games.filter((g) => !g.comingSoon);
const gameCount = releasedGames.length;
const defaultTitle = `${SITE_NAME} - オフラインで遊べる無料ゲーム${gameCount}種の詰め合わせ`;
const defaultDescription = `${gameCount}種類のゲーム（${releasedGames.map((g) => g.name).join("・")}）を1本にまとめた iPhone 用ゲームコレクション。すべてオフラインで遊べて、通信も会員登録も不要。無料・約${APP_SIZE_MB}。`;

export const metadata: Metadata = {
  // 相対パスの canonical / OGP 画像をここを起点に絶対 URL 化する
  metadataBase: new URL(SITE_URL),
  title: {
    default: defaultTitle,
    template: `%s | ${SITE_NAME}`,
  },
  description: defaultDescription,
  applicationName: SITE_NAME,
  alternates: { canonical: "/" },
  openGraph: {
    type: "website",
    siteName: SITE_NAME,
    locale: "ja_JP",
    url: "/",
    title: defaultTitle,
    description: defaultDescription,
    images: [{ url: "/og/default.png", width: 1200, height: 630, alt: SITE_NAME }],
  },
  twitter: {
    card: "summary_large_image",
    title: defaultTitle,
    description: defaultDescription,
    images: ["/og/default.png"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ja">
      <body className="bg-gray-50 dark:bg-gray-900 text-gray-800 dark:text-gray-100 min-h-screen flex flex-col">
        <header className="bg-white dark:bg-gray-800 border-b border-gray-100 dark:border-gray-700 sticky top-0 z-10">
          <div className="max-w-2xl mx-auto px-6 py-4 flex items-center gap-3">
            <span className="text-2xl">🎮</span>
            <Link href="/" className="text-xl font-bold text-gray-900 dark:text-white hover:text-orange-500 transition-colors">
              あそびば
            </Link>
          </div>
        </header>

        <main className="max-w-2xl mx-auto w-full px-6 py-10 flex-1">
          {children}
        </main>

        <footer className="border-t border-gray-100 dark:border-gray-700 bg-white dark:bg-gray-800">
          <div className="max-w-2xl mx-auto px-6 py-8 flex flex-col sm:flex-row justify-between items-center gap-4 text-sm text-gray-500 dark:text-gray-400">
            <span>© 2025 あそびば</span>
            <nav className="flex flex-wrap justify-center gap-6">
              <a href={APP_STORE_URL} className="hover:text-orange-500 transition-colors">App Store</a>
              <Link href="/privacy" className="hover:text-orange-500 transition-colors">プライバシーポリシー</Link>
              <Link href="/terms" className="hover:text-orange-500 transition-colors">利用規約</Link>
            </nav>
          </div>
        </footer>
      </body>
    </html>
  );
}
