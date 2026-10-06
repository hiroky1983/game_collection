# docs/analytics/

KPI の取得スクリプトと、取得した数字の記録置き場。

## fetch-kpi.mjs（#781）

ASC・GA4・AdMob を**読み取り専用**で叩いて Markdown の表にする。週次会議（`Scripts/ai-weekly-meeting-prompt.md`）が KPI 表に使う。

```bash
export PATH="$HOME/.nodenv/shims:$PATH"   # 既定の node v14 では fetch が無い。Node 18 以上
node docs/analytics/fetch-kpi.mjs all     # asc-sales + ga4 + ga4-reward + admob
node docs/analytics/fetch-kpi.mjs ga4 28  # 個別実行・日数指定
```

| サブコマンド | 読むもの | 備考 |
|---|---|---|
| `asc-sales [日数]` | ASC 売上レポート（日次）の初回 DL・再 DL・アップデート | 日付は太平洋時間。レポートの無い日は 404 で「レポート無し（0件または未確定）」と出る（販売 0 件の日にもレポートは無い）。他の失敗は表にエラーを出し、終了コード 1 |
| `asc-analytics` | App Analytics レポートの有無と中身 | ONGOING の依頼を 2026-10-06 に1本作成済み。最初のレポートは作成の 1〜2 日後から。依頼が無い環境では `--create-analytics-request` で作る |
| `ga4 [日数]` | アクティブユーザー・イベント別・ゲーム別 `game_start` | `customUser:build_channel = appstore` に固定（#347） |
| `ga4-reward [日数]` | リワードの `purpose` 別の受諾率・先読み不足率・完了率 | 式は `docs/spec-app.md`「解析仕様」の `reward_offer` の項 |
| `admob [日数]` | 広告ユニット別の推定収益・表示回数・eCPM（JPY） | 昨日まで。ユニット名が同じ `banner` でも別アプリ／別ユニットは別行 |

### 認証（リポジトリには入れない）

- ASC: `~/.appstoreconnect/asc-key.json`（Key ID NP99RBDM3Y・Admin。2026-10-06 に再発行）。ベンダー番号 94327451 はスクリプトの定数
- Google（GA4・AdMob）: `~/.config/gcloud/application_default_credentials.json` の refresh_token。gcloud の標準クライアントは GA4・AdMob のスコープがブロックされるため、会長作成の OAuth クライアント（`~/asobiba-secrets/google_auth_asobiba.json`）で `application-default login` したもの。切れたら会長が同じ手順で入れ直す

### 読み方の注意

- GA4 のゲーム別 `game_start` は回数の単位が揃わない（麻雀は 1 対局、ポーカー・ブラックジャックは 1 ハンド。`2026-09-14-kpi-snapshot.md` §3）。比較は `duration_sec`（カスタム指標登録済み）の合計時間で
- ASC の DL（売上レポート）と GA4 のユーザーは母集団が違う（GA4 は計測を許可した利用者だけ）
- AdMob は広告ユニット単位でしか読めず、`build_channel` で絞れない。GA4（appstore 限定）の `reward_ad` と件数を突き合わせて「合わない」と読まない。ユニット名が同じ `banner` は末尾 4 桁のユニット ID で区別する
- 出力に publisher ID・鍵は出さない（週次レポートの Issue は PUBLIC）
