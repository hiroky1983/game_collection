/// サイト全体で使う定数。独自ドメインを取得したら SITE_URL だけ差し替える
/// （canonical / sitemap / OGP の絶対 URL はすべてここから組み立てている）。
export const SITE_URL = "https://web-murex-sigma-62.vercel.app";

export const APP_STORE_ID = "6781719499";
export const APP_STORE_URL = `https://apps.apple.com/jp/app/id${APP_STORE_ID}`;

export const SITE_NAME = "あそびば";

/// App Store の実測ダウンロードサイズ（iTunes Lookup API・v1.0.2 時点で 4,628,480 bytes）。
/// バージョンを上げてサイズが変わったらここを更新する。
export const APP_SIZE_MB = "4.6MB";

/// 対応 OS（App Store の minimumOsVersion に合わせる）。
export const MIN_IOS_VERSION = "17.0";
