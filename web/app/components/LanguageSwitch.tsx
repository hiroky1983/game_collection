"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

/// 英語版があるページ（日本語のパス → 英語のパス）。ゲーム別ページ（/games/<slug>）の英語版は無いので、
/// 対応の無いページからの切り替えは英語トップ（/en）へ飛ばす（#2170）。
const EN_PATHS: Record<string, string> = {
  "/": "/en",
  "/terms": "/en/terms",
  "/privacy": "/en/privacy",
};

/// ヘッダの言語切り替え。いま見ているページの反対の言語版へリンクする。
/// 日本語ページと英語ページはルートレイアウトが別（`app/(ja)` / `app/en`）なので、遷移は全体の再読み込みになる。
export default function LanguageSwitch({ to }: { to: "en" | "ja" }) {
  const pathname = usePathname() ?? "/";
  if (to === "en") {
    return (
      <Link href={EN_PATHS[pathname] ?? "/en"} hrefLang="en" lang="en" className={className}>
        English
      </Link>
    );
  }
  const jaPath = Object.keys(EN_PATHS).find((ja) => EN_PATHS[ja] === pathname) ?? "/";
  return (
    <Link href={jaPath} hrefLang="ja" lang="ja" className={className}>
      日本語
    </Link>
  );
}

const className =
  "ml-auto text-sm text-gray-500 dark:text-gray-400 hover:text-orange-500 transition-colors";
