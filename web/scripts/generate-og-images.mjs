// OGP 画像（1200×630 PNG）を web/public/og/ に生成する。
//
// 使い方（macOS + Homebrew の rsvg-convert が必要）:
//   brew install librsvg
//   cd web && node --experimental-strip-types scripts/generate-og-images.mjs
//
// ゲームを追加・改名したら再実行して PNG をコミットする。
// ビルド時ではなく手動生成にしているのは、Vercel のビルド環境に日本語フォントが無く
// ImageResponse（next/og）では日本語が豆腐になるため。
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { games } from "../app/lib/games.ts";

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, "..", "public", "og");

const BG = "#FF7A5A";
const CARD = "#FFFFFF";
const INK = "#2B2B2B";
const INK_SUB = "#7A7A7A";

/// 本数・ゲーム名は `games` から導出する（画像にベタ書きすると追加のたびに古い数字が焼き付く）。
const gameCount = games.length;
const footer = `オフラインで遊べる無料ゲーム${gameCount}種｜App Store で配信中`;

const esc = (s) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

/** 大見出し（複数行可）と小見出しを載せた OGP カードの SVG を作る。 */
function card({ title, subtitle }) {
  const titleSize = title.length > 12 ? 76 : 96;
  const titleY = 300 - (subtitle ? 0 : 30);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630">
  <rect width="1200" height="630" fill="${BG}"/>
  <rect x="48" y="48" width="1104" height="534" rx="48" fill="${CARD}"/>
  <text x="104" y="168" font-family="Hiragino Sans" font-size="40" font-weight="bold" fill="${BG}">あそびば</text>
  <text x="104" y="${titleY}" font-family="Hiragino Sans" font-size="${titleSize}" font-weight="bold" fill="${INK}">${esc(title)}</text>
  <text x="104" y="${titleY + 78}" font-family="Hiragino Sans" font-size="40" fill="${INK_SUB}">${esc(subtitle)}</text>
  <text x="104" y="512" font-family="Hiragino Sans" font-size="34" fill="${INK_SUB}">${esc(footer)}</text>
</svg>`;
}

function render(name, svg) {
  const svgPath = join(outDir, `${name}.svg`);
  const pngPath = join(outDir, `${name}.png`);
  writeFileSync(svgPath, svg);
  execFileSync("rsvg-convert", ["-w", "1200", "-h", "630", svgPath, "-o", pngPath]);
  execFileSync("rm", [svgPath]);
  console.log(`generated ${pngPath}`);
}

mkdirSync(outDir, { recursive: true });

render(
  "default",
  card({
    title: `定番ゲーム${gameCount}種の詰め合わせ`,
    subtitle: `${games.slice(0, 5).map((g) => g.name).join("・")}ほか`,
  }),
);

for (const game of games) {
  render(game.slug, card({ title: game.name, subtitle: game.tagline }));
}
