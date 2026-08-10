import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { findGame, games } from "../../lib/games";
import { APP_SIZE_MB, APP_STORE_URL, SITE_NAME } from "../../lib/site";

type Props = { params: Promise<{ slug: string }> };

export function generateStaticParams() {
  return games.map((g) => ({ slug: g.slug }));
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const game = findGame(slug);
  if (!game) return {};

  const url = `/games/${game.slug}`;
  return {
    title: game.pageTitle,
    description: game.description,
    alternates: { canonical: url },
    openGraph: {
      type: "article",
      siteName: SITE_NAME,
      locale: "ja_JP",
      url,
      title: `${game.pageTitle} | ${SITE_NAME}`,
      description: game.description,
      images: [{ url: `/og/${game.slug}.png`, width: 1200, height: 630, alt: `${game.name}（${SITE_NAME}）` }],
    },
    twitter: {
      card: "summary_large_image",
      title: `${game.pageTitle} | ${SITE_NAME}`,
      description: game.description,
      images: [`/og/${game.slug}.png`],
    },
  };
}

export default async function GamePage({ params }: Props) {
  const { slug } = await params;
  const game = findGame(slug);
  if (!game) notFound();

  const others = games.filter((g) => g.slug !== game.slug);

  return (
    <div>
      <nav className="text-sm text-gray-400 mb-6">
        <Link href="/" className="hover:text-orange-500">あそびば</Link>
        <span className="mx-2">/</span>
        <span className="text-gray-500 dark:text-gray-300">{game.name}</span>
      </nav>

      <div className="mb-8">
        <div className="text-5xl mb-3">{game.emoji}</div>
        <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-2">{game.name}</h1>
        <p className="text-gray-500 dark:text-gray-400">{game.tagline}</p>
      </div>

      <p className="text-gray-700 dark:text-gray-300 leading-relaxed mb-8">{game.description}</p>

      <section className="mb-10">
        <h2 className="text-lg font-bold text-gray-900 dark:text-white mb-3 pb-2 border-b border-gray-200 dark:border-gray-700">
          遊び方
        </h2>
        <ol className="list-decimal pl-5 space-y-2 text-gray-700 dark:text-gray-300 leading-relaxed">
          {game.howTo.map((step) => (
            <li key={step}>{step}</li>
          ))}
        </ol>
      </section>

      <section className="mb-10">
        <h2 className="text-lg font-bold text-gray-900 dark:text-white mb-3 pb-2 border-b border-gray-200 dark:border-gray-700">
          このアプリの{game.name}の特徴
        </h2>
        <ul className="list-disc pl-5 space-y-2 text-gray-700 dark:text-gray-300 leading-relaxed">
          {game.features.map((f) => (
            <li key={f}>{f}</li>
          ))}
        </ul>
      </section>

      <div className="bg-white dark:bg-gray-800 rounded-2xl border border-gray-100 dark:border-gray-700 shadow-sm p-6 text-center mb-10">
        <p className="text-gray-700 dark:text-gray-300 leading-relaxed mb-4">
          {game.name}は、ゲームコレクションアプリ「あそびば」に収録されています。無料・約
          {APP_SIZE_MB}、オフラインで遊べて会員登録も不要です。
        </p>
        <a
          href={APP_STORE_URL}
          className="inline-block bg-black dark:bg-white text-white dark:text-black text-sm font-semibold px-6 py-3 rounded-full hover:bg-gray-800 dark:hover:bg-gray-200 transition-colors"
        >
          App Storeでダウンロード（無料）
        </a>
      </div>

      <section>
        <h2 className="text-lg font-bold text-gray-900 dark:text-white mb-3">ほかの収録ゲーム</h2>
        <div className="flex flex-wrap gap-2">
          {others.map((g) => (
            <Link
              key={g.slug}
              href={`/games/${g.slug}`}
              className="bg-white dark:bg-gray-800 border border-gray-100 dark:border-gray-700 rounded-full px-4 py-2 text-sm text-gray-700 dark:text-gray-300 hover:border-orange-300 dark:hover:border-orange-700 transition-colors"
            >
              <span className="mr-1">{g.emoji}</span>
              {g.name}
            </Link>
          ))}
        </div>
      </section>
    </div>
  );
}
