import type { MetadataRoute } from "next";
import { games } from "./lib/games";
import { SITE_URL } from "./lib/site";

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    { url: SITE_URL, changeFrequency: "weekly", priority: 1 },
    ...games.map((g) => ({
      url: `${SITE_URL}/games/${g.slug}`,
      changeFrequency: "monthly" as const,
      priority: 0.8,
    })),
    { url: `${SITE_URL}/privacy`, changeFrequency: "yearly" as const, priority: 0.3 },
    { url: `${SITE_URL}/terms`, changeFrequency: "yearly" as const, priority: 0.3 },
    // 英語版（#2170）。ゲーム別ページの英語版は無い
    { url: `${SITE_URL}/en`, changeFrequency: "weekly" as const, priority: 0.9 },
    { url: `${SITE_URL}/en/privacy`, changeFrequency: "yearly" as const, priority: 0.3 },
    { url: `${SITE_URL}/en/terms`, changeFrequency: "yearly" as const, priority: 0.3 },
  ];
}
