import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "あそびば",
  description: "将棋・2048・五目並べ・マインスイーパー・オセロが楽しめるゲームコレクションアプリ",
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
            <a href="/" className="text-xl font-bold text-gray-900 dark:text-white hover:text-orange-500 transition-colors">
              あそびば
            </a>
          </div>
        </header>

        <main className="max-w-2xl mx-auto w-full px-6 py-10 flex-1">
          {children}
        </main>

        <footer className="border-t border-gray-100 dark:border-gray-700 bg-white dark:bg-gray-800">
          <div className="max-w-2xl mx-auto px-6 py-8 flex flex-col sm:flex-row justify-between items-center gap-4 text-sm text-gray-500 dark:text-gray-400">
            <span>© 2025 あそびば</span>
            <nav className="flex gap-6">
              <a href="/privacy" className="hover:text-orange-500 transition-colors">プライバシーポリシー</a>
              <a href="/terms" className="hover:text-orange-500 transition-colors">利用規約</a>
            </nav>
          </div>
        </footer>
      </body>
    </html>
  );
}
