# 柵越えおじさん「週間ランキング戦 開幕」告知動画 モック 構成表（#1995）

作成 2026-10-09。AI 生成映像は不使用。素材は会長提供の 3D 静止画・表情一覧、自作シミュレータでの実録画、
ランキング入れ替えアニメ B 案（#1792）のみ。BGM 無し（無音トラック無し）。ffmpeg で生成（`build.py`）。

## Apple の仕様（一次情報・2026-10-09 確認）

| 置き場所 | 形式 | 縦横比 | 解像度 | fps | 上限 |
|---|---|---|---|---|---|
| イベントカード 画像 | .jpg/.jpeg/.png | 16:9 | 1920×1080 〜 3840×2160 | - | 500 MB |
| イベントカード 動画 | .mov/.m4v/.mp4 | 16:9 | 1920×1080 〜 3840×2160 | 30 or 60 | 500 MB |
| 詳細ページ 画像 | .jpg/.jpeg/.png | 9:16 | 1080×1920 〜 2160×3840 | - | 500 MB |
| 詳細ページ 動画 | .mov/.m4v/.mp4 | 9:16 | 1080×1920 〜 2160×3840 | 30 or 60 | 500 MB |

- 音声: カードは AAC 256kbps ステレオ、詳細ページは PCM か AAC 256kbps。**音声トラック無しも可**。
  出典: https://developer.apple.com/help/app-store-connect/reference/in-app-events/in-app-event-media-and-audio-specifications
- 長さ: 仕様ページに秒数の記載は無い。WWDC21「Meet in-app events on the App Store」で
  「Videos you use on both the card and details page will loop and are limited to 30 seconds.」
  出典: https://developer.apple.com/videos/play/wwdc2021/10171/
- 内容の決まり（https://developer.apple.com/app-store/in-app-events/ ）:
  - 「Videos autoplay and repeat, so aim to create a seamless loop.」
  - 「When possible, avoid using text or logos in your media, especially if they include your event name or app name.」
  - 「Don't add borders or gradients to your media. Crops and gradients are automatically applied…」
  - アプリ画面以外の絵（イラスト等）を禁じる文言は無い。求められているのは「イベントを表す（represent）」こと。
    審査ガイドライン 2.3.13「All event metadata must be accurate and pertain to the event itself」
    出典: https://developer.apple.com/app-store/review/guidelines/#2.3.13
- 文字数: イベント名 30 / 短い説明 50 / 長い説明 120（参照名 64）。期間は最長 31 日、開始 14 日前から表示可。
  出典: https://developer.apple.com/help/app-store-connect/offer-in-app-events/offer-in-app-events/

## 構成（詳細ページ用・縦 1080×1920・30fps・21.2 秒）v3 2026-10-10 会長指示 3 点すべて反映

| 秒 | シーン | 画 | 動き | テロップ |
|---|---|---|---|---|
| 0.0–3.2 | A 開幕 | おじさん 3D 静止画（ヘルメット B） | 白フラッシュ→ボールのどアップから 1.1 秒で引きながら顔へパン→その後ゆっくり顔へ寄る | 1.05s「週間ランキング戦」ドン、1.35s「開幕！」ドン（黄・赤縁） |
| 3.2–9.4 | B 実録画 | 柵越えおじさん 実際のゲーム画面・**ジャストミートの場外ホームラン 175 m センター**（`rec/homerun_just.mp4` 1 球目）→ 10 球の結果「エクセレント！8 本 1,402 m ニューレコード！」（v3・会長指示 1・2026-10-10） | 構え〜スイング等速、閃光・ヒットストップ等速（0.7 秒）、飛行 2.4 倍速、「場外！」カード 1.2 秒、結果 0.9 秒＋最後のコマ 0.7 秒止め | 「実際のゲーム画面」小、飛行中「飛ばせ！」1.4 秒 |
| 9.4–14.7 | C ランキング | 入れ替えアニメ B 案を **9 位→1 位** に変更（1,480 m）。到着後に王冠＋「1位！」＋「今週のトップに立った！」が黄色い放射の上に弾け、テーマ 5 色の紙吹雪が降る（会長指示 2・2026-10-09） | 0.35s 静止→数え上げ→一気に 1 位へ→3.1s 祝福 | 上「今週、あなたは何位？」、3.3s 下小「全国のおじさんと飛距離で勝負」 |
| 14.7–18.7 | D ルール | 紺地＋表情（真顔→驚き→笑顔・罫線を埋めた一覧から頭〜顎まで丸ごと切り出し直し、会長指示 3） | 3 行が 0.9 秒刻みで叩き込み | 「毎週月曜にリセット」「1ゲーム10球の総飛距離で勝負」「月まで飛ばせ」 |
| 18.7–21.3 | E 締め | 紺地＋おじさん画 | 「あそびば」ポップ→サブ→小さく注意書き→末尾 0.4 秒で白へフェード（冒頭の白フラッシュへループ） | 「あそびば」「柵越えおじさん 週間ランキング戦」「ランキングは予告なく終了する場合があります」 |

## 構成（カード用・横 1920×1080・30fps・同尺）

縦と同じ 5 シーン。A は同じ画を 16:9 で切る（ボール→顔のパン）。B・C は縦の録画を右側に置き、
背景は同じ映像をぼかして敷く。テロップは左側。E はおじさん画を右に。

## 成果物

- `event_portrait.mp4` 詳細ページ用（テロップあり）
- `event_card.mp4` カード用（テロップあり）
- `event_portrait_notext.mp4` / `event_card_notext.mp4` 映像の上にテロップを重ねない版（A・B・C の文字を外す。D のルール 3 行と E の締めは残す。Apple の「文字・ロゴを避ける」に寄せた案、19.5 秒）
- `event_card.png` / `event_card_notext.png` カード用静止画（1920×1080）、`event_portrait.png` / `event_portrait_notext.png` 詳細ページ用静止画（1080×1920）
- `build.py` 生成スクリプト、`work/` 中間ファイル

## 気になる点（会長判断が要るもの）

1. **Apple は媒体内の文字を避けるよう求めている**（「When possible, avoid using text or logos in your media, especially if they include your event name or app name」）。
   イベント名・短い説明は App Store 側がカードと詳細ページの下部に重ねて出すため、冒頭の「週間ランキング戦 開幕！」や締めの「あそびば」は重複になる。
   テロップあり版を正にするか、notext 版を正にするか、要決裁。本案ではテロップを上〜中段に置き、下 1/4 は空けている。
2. **ランキングアニメの日付**は #1792 のモック値（10/5（月）〜10/11（日）・あと 3 日・9 人）のまま。入稿前に v1.1.11 の実画面で録り直す。
3. 3D 静止画（1254×1254）を 1080×1920 / 1920×1080 に切って拡大しているため、冒頭のアップは最大 2.6 倍の拡大でやや甘い。本番用には 2160px 以上の元画像が欲しい。
4. 長さは 19.7 秒（WWDC21 の「30 秒まで」の範囲内）。公式の仕様ページに秒数の記載は無いので、ASC の入稿画面で弾かれたら短縮する。
5. ループ: 冒頭 0.2 秒を白から、末尾 0.4 秒を白へフェードしてつないでいる。Apple が自動でグラデーションを乗せるため、末尾の白が気になれば紺フェードに変える。
6. 録画は自作シミュレータのものを流用（`preview-video/raw/homerun.mp4` 68.3〜77.0 秒）。会長の端末には触れていない。
7. 音声トラックは無し（仕様上「Tracks without audio are supported」）。

## v2（会長の修正指示 3 点・2026-10-09）の差分

| # | 指示 | 状態 | 変更 |
|---|---|---|---|
| 1 | ホームランはジャストミートの当たりに | 済み（v3・2026-10-10 14:12 に 7 回目の録画で成功） | 既存の実録画 3 本の柵越えはすべて「タイミング: ナイス」でジャストミート無し。リポジトリ外のコピー（`preview-video/src`）に起動引数 `-homerunForceJust`（振れば必ずジャストミートの柵越え）を足して build-for-testing まで成功。自作シミュレータ EventVideoSim での録画（`rec_homerun.sh`）を 4 回試行: ①xcodebuild が Resolve Package Graph から 5 分進まず ②UI テストランナーが起動直後に SIGABRT（13:53 のクラッシュレポート） ③④ `-xctestrun` 指定で「Unable to find a device」。`xcodebuild -showdestinations` も 240 秒で応答なし。Mac の load average が 400〜660（Arc/Chrome が CPU 100% 近く・スワップ多発）で CoreSimulator/xcodebuild が応答しない状態。負荷が下がれば `rec_homerun.sh homerun_just` → `build.py` のシーン B の素材差し替えで 30 分。シーン B は v1 のまま（141 m 左中間・ナイス）。 |
| 2 | ランキングは 1 位に立って祝福 | 済み | `ranking-mock/app` を改変（`Data.swift` animNewMeters 1,206→1,480、`RankingPage.swift` に TopBurst/ConfettiOverlay/王冠を追加・元は `*.orig`）。自作シミュレータで録画 `rec/rank_top.mp4`（1206×2622）。C は 4.0 秒→5.3 秒に |
| 3 | 顔の頭・顎が切れている | 済み | 表情一覧の罫線（明るい灰 1〜2px）を上下の行の平均で埋め、セルの余白ごと切り出してから灰背景を抜く（`work/faces_fixed.png` → `work/face2_{normal,smile,surprise}.png`）。顎〜首まで入る |

全体の尺: 19.7 秒 → 21.0 秒（notext は 20.8 秒）。他のシーン（A・B・E）は変えていない。

## v3（2026-10-10）: ジャストミートの差し替え
- 録画: Mac の負荷が下がった 14:11 に EventVideoSim を boot し、`rec_homerun.sh`（`-skipPackageUpdates -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -clonedSourcePackagesDirPath` 付き）で 7 回目に成功。E2E の 10 球中 9 球が「場外、175メートル、センター、ジャスト」（1 球見送り）。`rec/homerun_just.mp4`（1206×2622・133 秒・224 MB）。
- B は 1 球目（31.8–38.4 秒）と 10 球の結果（99.65–100.55 秒）を使用。5.9 秒→6.2 秒。以降のシーンは +0.3 秒ずれる。
- 2 球目以降は画面上部に実績解除のトースト（はじめての柵越え・場外ホームラン・ジャストミート）が出るため使わない。

## v4（2026-10-10）: 締め（E）を案 A に差し替え（会長「A かな」）
- E 18.7–21.9s（3.2 秒）: 紺地に回る黄色の放射＋紙吹雪（`gen_assets.py` で描画）。野球のおじさんの 3D 静止画が 0.1s にドンと出る → 0.55s「柵越えおじさん」→ 0.75s「週間ランキング戦」→ 1.35s「毎週月曜スタート」→ 1.95s「あそびば」→ 末尾 0.4 秒で白へ。注記「ランキングは予告なく終了する場合があります」は小さく残す。
- 横版は左に絵（780px）、右に文字の列、「あそびば」は右上。
- 成果物は `event_*_EA.mp4`（4 本・21.87 秒）。採用前の E の 4 本（`event_*.mp4`）も残置。
- 不採用案: B（打球が月に当たる）`event_portrait_EB.mp4`、C（王冠＋キミだ）`event_portrait_EC.mp4`。
