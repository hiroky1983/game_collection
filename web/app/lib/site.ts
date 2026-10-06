/// サイト全体で使う定数。独自ドメインを取得したら SITE_URL だけ差し替える
/// （canonical / sitemap / OGP の絶対 URL はすべてここから組み立てている）。
export const SITE_URL = "https://web-murex-sigma-62.vercel.app";

export const APP_STORE_ID = "6781719499";
export const APP_STORE_URL = `https://apps.apple.com/jp/app/id${APP_STORE_ID}`;

export const SITE_NAME = "あそびば";

/// アプリサイズは LP に数値で出さない（#670・2026-09-13 案Aで決裁）。v1.0.2 の「約4.6MB」を
/// v1.1.4（15,191,040 bytes）まで直し忘れて3.3倍ずれていたうえ、「軽さ」を訴求する前提だった
/// 10MB 未満（docs/aso/metadata-v1.1.0.md:121）を既に超えている。Lookup API の fileSizeBytes は
/// 端末ごとの表示サイズとも一致しないため、数値を掲げる限り版ごとの確認作業が残る。

/// 対応 OS（App Store の minimumOsVersion に合わせる）。
export const MIN_IOS_VERSION = "17.0";
