import type { Metadata } from "next";
import Link from "next/link";
import "../globals.css";
import { games } from "../lib/games";
import { APP_STORE_URL_GLOBAL, SITE_NAME_EN, SITE_URL } from "../lib/site";
import LanguageSwitch from "../components/LanguageSwitch";

/// 英語ページ（/en 以下）のルートレイアウト。`<html lang="en">` にするため、日本語ページ（`app/(ja)/layout.tsx`）とは
/// 別のルートレイアウトにしている（#2170）。見た目は日本語側と同じに揃える。
/// 本数は日本語側と同じく `games` から数える（配信済み = `comingSoon` 無しだけ）。
const gameCount = games.filter((g) => !g.comingSoon).length;
const defaultTitle = `${SITE_NAME_EN} - ${gameCount} free games you can play offline`;
const defaultDescription = `${gameCount} classic games in one iPhone app. Every game works offline, with no internet connection or sign-up needed. Free.`;

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: defaultTitle,
    template: `%s | ${SITE_NAME_EN}`,
  },
  description: defaultDescription,
  applicationName: SITE_NAME_EN,
  alternates: { canonical: "/en", languages: { ja: "/", en: "/en" } },
  openGraph: {
    type: "website",
    siteName: SITE_NAME_EN,
    locale: "en_US",
    url: "/en",
    title: defaultTitle,
    description: defaultDescription,
    images: [{ url: "/og/default.png", width: 1200, height: 630, alt: SITE_NAME_EN }],
  },
  twitter: {
    card: "summary_large_image",
    title: defaultTitle,
    description: defaultDescription,
    images: ["/og/default.png"],
  },
};

export default function EnglishRootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="bg-gray-50 dark:bg-gray-900 text-gray-800 dark:text-gray-100 min-h-screen flex flex-col">
        <header className="bg-white dark:bg-gray-800 border-b border-gray-100 dark:border-gray-700 sticky top-0 z-10">
          <div className="max-w-2xl mx-auto px-6 py-4 flex items-center gap-3">
            <span className="text-2xl">🎮</span>
            <Link href="/en" className="text-xl font-bold text-gray-900 dark:text-white hover:text-orange-500 transition-colors">
              {SITE_NAME_EN}
            </Link>
            <LanguageSwitch to="ja" />
          </div>
        </header>

        <main className="max-w-2xl mx-auto w-full px-6 py-10 flex-1">
          {children}
        </main>

        <footer className="border-t border-gray-100 dark:border-gray-700 bg-white dark:bg-gray-800">
          <div className="max-w-2xl mx-auto px-6 py-8 flex flex-col sm:flex-row justify-between items-center gap-4 text-sm text-gray-500 dark:text-gray-400">
            <span>© 2025 {SITE_NAME_EN}</span>
            <nav className="flex flex-wrap justify-center gap-6">
              <a href={APP_STORE_URL_GLOBAL} className="hover:text-orange-500 transition-colors">App Store</a>
              <Link href="/en/privacy" className="hover:text-orange-500 transition-colors">Privacy Policy</Link>
              <Link href="/en/terms" className="hover:text-orange-500 transition-colors">Terms of Use</Link>
            </nav>
          </div>
        </footer>
      </body>
    </html>
  );
}
