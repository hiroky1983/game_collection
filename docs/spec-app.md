# アプリ全体仕様

## 概要

**アプリ名**: あそびば (Asobiba)
**プラットフォーム**: iOS 17.0+
**向き**: 縦固定 (Portrait only)
**言語**: 日本語
**収益モデル**: AdMob バナー広告 + リワード広告（インタースティシャルは実装はあるがどこからも呼んでいない）

---

## アーキテクチャ

### パッケージ構成

```
App/                    ← iOS アプリ本体（GameRegistry・AppEnvironment 等）
Packages/GameKit/
  Sources/
    CoreEngine/         ← 共通基盤のうち純ロジック (Analytics, SnapshotStore, PlayLog, PlayRecord, GameCenter 等。release/v1.1.6 から)
    Core/               ← 共通基盤 (Protocol, Theme, AdService, RewardedRescue。`@_exported import CoreEngine` で再公開)
    Game2048/           ← 2048
    GameBlockPuzzle/    ← ブロックならべ（未リリース。2026-09-10 時点）
    GameShogi/          ← 将棋
    GameMahjong/        ← 麻雀（4人打ち）
    GameSudoku/         ← ナンプレ
    GameOthello/        ← オセロ
    GameGo/             ← 囲碁
    GameChess/          ← チェス
    GameMahjongSolitaire/ ← 麻雀ソリティア
    GameSolitaire/      ← ソリティア（クロンダイク）
    GameFreeCell/       ← フリーセル（未リリース。2026-09-10 時点）
    GameSpider/         ← スパイダーソリティア（未リリース。2026-09-15 時点）
    GameDaifugo/        ← 大富豪
    GamePoker/          ← ポーカー
    GameBlackjack/      ← ブラックジャック
    GameMinesweeper/    ← マインスイーパー
    GameGomoku/         ← 五目並べ
    GameConcentration/  ← 神経衰弱
    GameBlocks/         ← ブロック崩し（v1.1.3 で公開済み）
    GameRunner/         ← チャリンコおじさん（横スクロールランナー・未リリース。2026-09-10 時点）
    GameHanafuda/       ← 花札こいこい（未リリース。2026-09-10 時点）
```

登録順・表示順の正典は `App/AppGameServices.swift` の `registry`（新ゲームは 1 行追加するだけ）。
「未リリース」は App Store 配信中のバイナリにまだ含まれていないという意味で、コード上は
他のゲームと同格に動く（`GameRegistry` はストア配信状態を持たない）。配信中かどうかは
別途 ASO ドキュメント（`docs/aso/`）やリリースノートで確認すること。

`CoreEngine` は `import Foundation`（と Observation）だけで書かれたファイルの置き場で、将来 Linux で純ロジックの
テストを回すための層（#834）。SwiftUI・StoreKit・CoreGraphics などに触れるファイルは `Core` に置く。`Core` が
`@_exported import CoreEngine` で再公開するので、ゲームと App は `import Core` のままでよい。
**`release/v1.1.6` から**、AITurnGuard・FirstPick・NewGames・RecordsSummary・Analytics・GameCenter・PlayLog など
20 本と `PlayingCardSuit` / `PlayingCardFigure` が `CoreEngine/` に移っている。本文中のこれらの `Core/…swift` は、
v1.1.6 以降は `CoreEngine/…swift` と読み替えること。

### 主要プロトコル

**`GameModule`**: ゲームをプラグイン形式で登録するプロトコル
- `id: String` — ユニーク識別子
- `title: String` — 表示名
- `icon: Image` — ハブカードのアイコン
- `makeView(services:) -> AnyView` — ゲーム画面を生成

**`AdService`**: 広告サービスの境界
- `makeBannerView(width:) -> AnyView?` — バナー広告
- `showInterstitial() async` — インタースティシャル広告（待機付き。プロトコルには残っているが呼び出し箇所は無い）
- `showRewardedAd() async -> Bool` — リワード広告（視聴完了で true）。`GameServices` 経由で
  呼ぶと `game_id` / `purpose` 付きで `reward_ad` イベントも送られる（v1.1.5 からは要求時に
  `reward_request` も。後述の解析仕様）
- `isRewardedAdReady: Bool` — いまタップされたら読み込みを待たずに出せるか（先読み済みか・#658）。
  `reward_offer` の `accepted` / `not_ready` の判定にだけ使う（`release/v1.1.7` から・#780）。
  先読みを持たない実装は既定で true

**`SnapshotStore`**: ゲーム状態の永続化
- `save(_:for:)` / `load(_:for:)` / `exists(for:)` / `clear(for:)`
- 実装: `FileSnapshotStore`（JSON → アプリの Documents/snapshots/）

### 依存注入

`AppEnvironment` にシングルトンで集約:
```swift
AppEnvironment.services  // GameServices (SnapshotStore + AdService)
AppEnvironment.registry  // GameRegistry (登録ゲーム一覧)
AppEnvironment.settings  // GameSettings (並び順・表示設定)
```

### CPU 手番ループの定石（`AITurnGuarded`・#531 / #817・v1.1.5）

CPU は View の `.task(id:)` から起動し、このタスクは**画面を離れる・キーが変わるとキャンセルされる**。
間合いを挟んで手番を連続で進めるモデル（麻雀・花札・大富豪など）は、次の3点を守る。
実装は `Core/AITurnGuard.swift`（`AITurnGuarded` に準拠して使う）。

1. **門番で引き継ぐ**（`withAITurnRunner`）。先行タスクが走っていたら即リターンせず、終了を待ってから
   走者を取る。即リターンにすると「新タスクが即リターン → 先行タスクがキャンセルで抜ける」の順で
   走者不在になり、手番が止まる（大富豪 #287・麻雀 #311・花札 #726）。
2. **sleep の直後にキャンセルを見る**（`pauseCPUTurn(for:)` の戻り値）。`try? await Task.sleep` は
   キャンセルされると即座に返るので、状態の guard だけでは通過し、離れた後に CPU が待ち時間ゼロで
   打ち、その結果が中断データに残る。ループ先頭の判定は無駄な sleep を省く近道で、代わりにはならない。
3. **テストは sleep に入らせてからキャンセルする**。`Task { ... }` を作ってすぐ `cancel()` すると
   本体の開始前に確定し、ループ先頭の判定しか踏まない（#817: 2 の判定を消しても緑のままだった）。
   `await Task { @MainActor in }.value` で本体を sleep まで走らせてからキャンセルし、2 の判定を消す
   変異で赤くなることを確かめる。引き継ぎ（1）のテストは本物のタスクを sleep させず、門番を直接
   立てる（並列実行で待ちが先に切れて空振りする）。どちらも実時間で待たない。

---

## ハブ画面 (HubView)

- `NavigationStack` ベース
- 最上部: プレイ記録がゼロ（`PlayLog.playedGameIDs` が空）で「つづき・最近」の行も無い初回だけ、「はじめの1本」を1枚出す（#721。出す条件と勧めるゲームは `Core/FirstPick.swift`。`release/v1.1.5` から）
- 登録ゲームをカード形式で 2 列グリッド表示（#119）。ゲーム数が増え、**現在は1画面に収まらず
  スクロールする**（並び順は `AppGameServices.registry` の登録順が新規インストール時の既定
  表示順。ユーザーがドラッグで並び替え・非表示にできる。2026-08-24 会長判断で検索需要の高い
  ゲームを上位へ寄せる調整済み）
- カード: ゲームアイコン / タイトル / 1 行（プレイ記録があれば記録・無ければゲームの説明） /
  右上に「続きから」バッジ（「続きから」で戻れる途中の局があるとき。判定は `GameModule.hasResumableSnapshot`・#809。
  既定は中断データの有無だが、局を復元しないチャリンコおじさんは出さず、終局後も見返しを残す将棋・チェスは保存された
  `phase` が `.playing` のときだけ出す。「つづき・最近」の行と `game_open` の `resume` も同じ判定。`release/v1.1.5` から）
- カードの長押しメニュー（#662。`release/v1.1.5` から）: 「いちばん上に置く」「非表示にする」。設定シートと同じ
  `GameSettings` を触る（保存キーは増やさない）。先頭の判定は非表示も含む並び（`orderedIDs`）で行い、そこで先頭のときだけ
  「いちばん上に置く」を無効にする。非表示にした直後だけ、画面下に「「◯◯」を非表示にしました。設定から戻せます」の案内を
  3 秒出し、VoiceOver には同じ文言をアナウンスする（戻す場所が設定シートの奥にあるため）
- 新しいゲームの印（#723。`release/v1.1.5` から）: アップデートで登録ゲームが増えた最初の起動だけ、増えたカードの右上に
  「NEW」（「続きから」が優先）、ハブ最上部に「新しいあそびが◯本増えました」の1行を出す。NEW はそのゲームを開くと外れ、
  次の起動では出ない。判定は `Core/NewGames.swift`、保存は `PlayLog` の1キー（`playLog_knownGameIDs_v1` = 前回ハブを出した
  時点の登録ゲーム ID の配列。端末内の `UserDefaults` のみ・上限は登録ゲーム数・「プレイ記録を消去」で消える）。
  新規インストールでは出さない（保存値もプレイの痕跡も無い端末は新規とみなす）
- 右上: 🏆 きろくボタン → `RecordsView` (sheet・#669。`release/v1.1.5` から。それまでは Game Center を直接開いていた・#334) /
  ⚙️ 設定ボタン → `SettingsView` (sheet)
- 下部: AdMob バナー

---

## きろく画面 (RecordsView)

#669。`release/v1.1.5` から。ハブのトロフィーから開く Sheet。Game Center 未サインインでも見られる。

- 上から「全部あそぶ N/登録ゲーム数」の進捗バーと「遊んだ種類・通算勝利・最高連勝」、節目、あそびごとの一覧、
  「Game Center で実績・ランキングを見る」ボタン
- 節目: Game Center の実績 4 個（`GameCenterAchievements`）と同じ定義・同じ式。一覧の各行にはゲームごとの
  「初勝利（勝敗以外は初クリア）」「10回あそんだ」を添える
- 一覧は設定シートと同じ並びで、非表示にしたゲームも載せる。未プレイは「まだ遊んでいない」
- 数字・文言・読み上げは `Core/RecordsSummary.swift`（純粋関数）が `PlayLog` の既存の値から開くたびに組み立てる。
  **保存項目は増やさない**ため、「プレイ記録を消去」のあとは全部が未プレイに戻る
- Game Center ボタンはシートを閉じ切ってからハブの `openGameCenter()` を呼ぶ（未サインインの案内もハブ側）

---

## リザルトの枠（レコメンド・難易度の階段）

#722・#917。`release/v1.1.5` から。各ゲームのリザルト直下の枠（`Core/RecommendationCard.swift` の `RecommendationSlot`）には、
決着後に次の順で**1枚だけ**出す。

1. **レコメンド**（別のゲームを勧めるカード）。決着の時点で提示済みとして数える（`PlayLog.markShown`）ので、
   出せるときは常に優先する（隠すと「見せていないのに無視された」回が積み上がる）
2. **難易度の階段**（#722）。レコメンドが無いときだけ出す
3. どちらも無ければ**何も出さない**（#917。以前は「ほかのあそび」＝ハブへ戻るだけのボタン・#661 を出していたが、
   左上の戻ると同じ出口のため 2026-09-15 の会長 QA で取り下げた）。枠の高さはひな形（`RecommendationCard.heightPlaceholder`）が
   確保しているので、何も出なくても周りの寸法は動かない

階段の規則は `Core/DifficultyLadder.swift`（乱数を使わない純粋関数。保存キーを増やさない）:

- **出す条件**: その回の決着を記録した連勝数（`PlayRecord.currentStreak`）が `streakThreshold`（3）の倍数のとき
  （3・6・9…連勝）。連勝は勝ち以外で 0 に戻るので、出るのは勝った回だけ。最上級で遊んでいるとき・プリセットに当たらない盤
  （マインスイーパーの旧サイズの中断データなど）では出さない
- **出し直しの間隔**: 提示間隔を連勝数そのもので持つので、勧めを使わずに同じ段で遊んだ人に次の勝ちで出し直すことは無い
  （次は更に 3 連勝したとき）。×で閉じた提案はその決着のあいだだけ隠れる（決着は `PlayRecord.plays` で見分ける）
- **カード**: 「N連勝中！ つぎは「◯◯」にしてみる？」＋「あそぶ」。押すと一段上の難易度で新しい局を始め、
  `gameDidRestart` を通すので `game_start` の `level` はその段で送られる
- **採用ゲーム**（`DifficultyLadderPrompt` を作る View・9 本）: 将棋・チェス・囲碁・オセロ・五目並べ・神経衰弱・花札こいこい
  （CPU の強さ）、ナンプレ（難易度）、マインスイーパー（盤のプリセット）
- **連勝の単位**は記録の区分（`PlayLog.recordKey(gameID:variant:)`）と同じ。`GameScore.variant` で区分を持つゲームは区分ごとに数える:
  ナンプレは難易度ごと、マインスイーパーは盤の大きさと地雷数ごと、花札こいこいは既定と違うルールの組み合わせごと
  （局数・酒の役・CPU の強さ）。この 3 本は一段上がると別の区分になり、連勝は 0 から数え直す。残りの 6 本は難易度を問わずゲーム単位

---

## 設定画面 (SettingsView)

Sheet で表示。`List` + `EditMode` 常時有効。

| セクション | 内容 |
|------|------|
| アプリ | バージョン表示 |
| あそび | ゲームの並び替え (ドラッグ) + 表示/非表示トグル |
| 規約 | 利用規約 / プライバシーポリシー（外部 URL を `SFSafariViewController` の sheet で表示） |
| 通知 | 続きのお知らせのオン / オフ（#663。既定オン・キー `resumeRemindersEnabled_v1`） |
| その他 | アプリを評価する / アプリをシェア |

- 並び順・非表示設定は `UserDefaults` に保存 (キー: `gameOrder_v1`, `hiddenGames_v1`)
- 新ゲーム追加時は末尾に自動追記

---

## 中断したゲームのお知らせ（#663・v1.1.5）

中断データを持ってハブへ戻った人にだけ、1 日ほど後に「「将棋」が途中のままです」をローカル通知で 1 件届ける。
汎用の「遊びに来てね」・デイリー通知・リモートプッシュは送らない。

- **規則は Core の `ResumeReminderService` / `ResumeReminderPolicy`**、OS へ渡す部分は App の
  `UserNotificationReminderScheduler`（`UNUserNotificationCenter`）。予約済みの一覧は OS が持ち、アプリ側に保存先を増やさない
- **予約**: `GameServices.gameDidLeave` で中断データがあるとき。知らせるのは 24 時間後で、それが 21 時〜9 時に
  当たるなら次の 9 時へずらす（最大 36 時間後）。同じゲームは 1 件に置き換え、全体で 3 件まで（あふれたら古い中断から外す）
- **取り消し**: そのゲームを開いた（`gameDidOpen`）・中断データが消えた（`ClearObservingSnapshotStore` が `clear` を捕まえる）・そのゲームを設定で非表示にした（`gameDidHide`・#810）・設定でオフにした
- **許諾**: 起動時には求めない。初めて予約するときに `.provisional` で求める（許可ダイアログは出ず、通知センターに静かに届く。#663 の決裁 (a)）。拒否されていれば何もしない
- **対象外**: `GameModule.resumesFromSnapshot == false` のゲーム（中断データから局を復元しないチャリンコおじさん）と、設定で非表示にしたゲーム（#810。予約もタップからの遷移もしない）
- **タップ**: `AppDelegate` が受け、ハブが `game_open{source: "notification"}` の導線でそのゲームを開く
- **止める経路**: 撮影モード・DEBUG ビルドでは予約しない。設定の「通知」トグル。動作確認は `-simulateNotificationTap <gameID>`（DEBUG のみ）

---

## ゲーム別の仕様（v1.1.5 で入ったもの）

### スパイダーソリティア（#717）

- 札は常に 2 組 104 枚。難度はスートの数（`SpiderSuitCount`）で、1 スート（入門・♠×8 組）/ 2 スート（標準・♠♥×4 組）/
  4 スート（上級・4 種×2 組）。局の開始時に `SpiderRuleSet` として焼き込み、中断データにも書く（1局=1RuleSet）。
  初回は開始シートを出さず 1 スートで配る
- 配札は解けることを確かめた種（`SpiderVerifiedSeeds`）から選ぶ。種の数は 1・2 スートが各 400、4 スートが 59（2026-09-15 時点・#914）
- **記録**: `GameScore.variant` を **3 難度すべてに付ける**（`1suit` / `2suit` / `4suit`。ナンプレと同じ）。新規のゲームで
  守るべき過去の記録が無く、難度でタイムの水準がまったく違う（1 スートは数分・4 スートは数十分）ため、自己ベストを最初から 3 行に分ける
- **解析**: `game_start` の `level` は 1 スート → `beginner` / 2 スート → `normal` / 4 スート → `hard`（`SpiderSuitCount.analyticsLevel`）
- **救済**: 「戻す」を無料回数＋リワード広告で補充する（`RewardedRescue`・`purpose` は `undo`。回数は他のゲームと共通の `RewardedUndoBudget`）

### チャリンコおじさん（#796 #797 #798 #800 #801）

遊び方はステージ制（18 面）とエンドレス（#675）の 2 つ（解析の `mode`・後述）。ステージ制の 18 面は 6 面ずつ 3 つの世界に分かれる
（`RunnerWorld`: 1〜6 面 朝の下町 / 7〜12 面 夕方の川沿い / 13〜18 面 夜の繁華街・#703）。世界で変わるのは背景・地面・岩・
動く障害の色だけで、当たり判定・速さには触れない。

**動く障害**（`RunnerHazardKind`）: 穴・低い岩・高い岩は置いた場所から動かない。次の 3 種は位置が時計ではなく**走者の進んだ距離**で
決まる（`RunnerHazard.frame(atRunnerDistance:)`）ので、同じ操作からは常に同じ軌道になる（自動操縦のテストにそのまま乗る）。

| 障害 | 初出 | 動き | 越え方 |
|---|---|---|---|
| 飛び立つ鳥（#796・#945） | 5 面 | 地面（低い岩と同じ高さ）に止まっていて、走者が 6 タイル手前に来ると飛び立ち、1 タイル進むあいだに普通のジャンプの頂点の高さまで上がって、そのまま飛ぶ | 走ったまま下を抜ける。着いてから跳ぶと頭が当たる（反射で跳ぶ人を罰する、岩の逆） |
| 犬（#800 → #944 → #955） | 4 面 | 画面の右（前方）の外から現れ、走者の 0.35 倍の速さで走者の方へ歩いて来る。予告の手応えは出さない（遠くから見える） | 低い岩と同じ高さ。跳べば越えられる |
| イノシシ（#801） | 7 面 | 手前で「ドドド」の手応え（`RunnerEvent.boarCharging`）を出し、右から走者と同じ速さで突進する。出会う地点との間に岩があれば岩の右側で止まり、低い岩と同じ置物になる | 低い岩と同じ高さ。跳べば越えられる |

4〜13 面・17〜18 面の犬・イノシシは、既存の低い岩の一部を置き換えたもの（障害の数・位置は変えていない）。

**たこ焼き（無敵・#797）**:

- 取ると `RunnerRules.invincibleDuration`（3 秒）無敵になる。無敵のあいだは岩・台座の正面・動く障害に重なってもミスにならないが、
  **穴には従来どおり落ちる**。速さ・ジャンプには一切触れないので、ステージの成立条件は無敵の有無で変わらない
- 置き場: ステージ制は 4〜17 面に 1 個ずつ（18 面は台座・床の規則を守れる平地が鳥の直前にしか無く、置いていない）。
  **取って 3 秒以内に動く障害へ着く並びには置かない**（跳んでも取れるので、その並びだと動物が必ず素通りになり障害として
  成立しない。2026-09-15 決裁・`movingHazardsHitWhenIgnored` が機械的に確かめる）。エンドレスは全 400 区画の半分の 200 区画目（走行距離 3,200 m・`RunnerEndlessCourse.takoyakiUnlockDistance`）から、
  スピードアップアイテムを置かなかった平地に 1/16 の割合で置く

**ワールドマップと到達面（#798）**:

- 開始シートでステージ制を選ぶと、世界ごとに面を並べたワールドマップから遊ぶ面を選べる。面の表記は「2-3」（世界-面）で、
  面の名前は付けていない（#946 で外した）。**選べるのは到達済みの面だけ**（`RunnerModel.isStageReached`。1 面は常に到達済み）
- 到達面 `reachedStage` は「挑み始めた面」と「クリアした面の次の面」で伸び、下の面を選んで遊んでも戻らない
- 保存は中断データ（`RunnerSnapshot`）の **optional の鍵 `reachedStage`**。v1.1.4 以前のデータには鍵が無く、nil なら再開面
  （`stage`）を到達点とみなす（非 optional にすると旧データの復号が失敗して中断ごと消える）。ステージ制は**決着してもファイルを
  消さない**（消すと選べる面が 1 面に戻る）。エンドレスは保存しない。旧形式のステージごとのベストタイム（`bestSeconds`）は
  読み捨て、書くときは空配列にする（#931）
- 面を選んで始めたときの `game_start` は `level` が選んだ面の `stage-N`、`mode` が `stage`（1 面から順に進んだときと同じ形）

**記録と解析**: ステージ制の記録は到達ステージ数で、`GameScore.variant` は nil のまま（これまでの記録の保存先を変えない）。
エンドレスは走行距離（m）を `variant` 付きで別に持つ。`game_end` の `cause`（解析仕様を参照）と障害の対応は次のとおり。

| `cause` | ミスの原因 |
|---|---|
| `pit` | 穴に落ちた |
| `rock` | 低い岩・高い岩・台座の正面にぶつかった |
| `bird` | 鳥にぶつかった |
| `animal` | 犬・イノシシにぶつかった |

---

## 広告仕様

| 種別 | 配置 |
|------|------|
| バナー (320×50 適応型) | ハブ画面・各ゲーム画面の最下部 |
| リワード | ほぼ全ゲーム共通の「救済」導線（`RewardedRescue` 経由。下表） |

報酬を約束する広告（リワード）は**視聴完了したときだけ**報酬を渡す（`showRewardedAd()` が `true` を返した場合のみ）。
視聴中断・ロード失敗時は報酬を与えず、その旨をアラートで伝える。インタースティシャルは現在どこからも使っていない。

- `DEBUG` ビルドでは自動的に Google 公式テスト広告 ID に切り替わる
- ATT 許可ダイアログ → AdMob 初期化 の順序を保証 (`ATTPermission.swift`)
- 許可・拒否どちらでも広告表示（拒否時は非パーソナライズ広告）
- リワード広告は **1 本だけ先読み**して保持し、タップ時は読み込みを待たずに出す（v1.1.5 から・#658）。
  先読みするのは SDK 初期化の直後・広告を出し終えた後・ハブからゲームを開いたときで、表示はタップ起点の
  `showRewardedAd()` だけ。保持分が失効（読み込みから 55 分）していた・表示に失敗した回だけ、その場で読み込む。
  失効判定は `Core/PreloadedAdSlot`（`AdsTests` で検証）、実体は `App/AdMobAdService.swift`

### リワード救済（`RewardedRescue`・#526）

各ゲームの View に同じ形で散っていた「連打ガード → 広告視聴 → 局ガード照合 → 適用 → 失敗アラート」の
5点セットを `Core/RewardedRescue.swift` の1か所に集約したもの（この設計により、新しい救済を足しても
連打ガードや局ガードの実装漏れが起きない）。ほぼ全ゲーム（2048・将棋・五目並べ・麻雀・麻雀ソリティア・
ソリティア・フリーセル・スパイダーソリティア・ポーカー・ブラックジャック・マインスイーパー・ナンプレ・オセロ・囲碁・
チェス・神経衰弱・ブロック崩し・ブロックならべ・チャリンコおじさん、`release/v1.1.5` の 2026-09-15 時点）が採用している。
救済の種類（`RewardPurpose`）は次の7つに閉じる:

| purpose | 内容 |
|---|---|
| `undo` | 「戻す」「待った」の補充 |
| `continue` | ゲームオーバーからそのまま続ける（盤面を保ったまま再開） |
| `revival` | 失った残機・持ち駒などを回復して復活 |
| `hint` | ヒントの表示・補充 |
| `joker` | ジョーカー（万能札）の付与 |
| `checkpoint` | チェックポイントからのやり直し |
| `shuffle` | 手詰まりの盤面を、取り切れる配置へ並べ替える（麻雀ソリティア） |

---

## 解析仕様（Analytics・#158 / #500 / #659 / #780）

`CoreEngine/Analytics.swift` に**送信するイベントを6種だけに閉じた** `AnalyticsEvent` enum がある
（`reward_request` / `game_open` の2種は #659 で `release/v1.1.5` に、`reward_offer` は #780 で `release/v1.1.7` に追加。
v1.1.4 までの公開版は3種）。
呼び出し側（各ゲーム）は任意のキー・値を足せず、イベントを増やすには enum にケースを足す必要がある
（＝意図しないイベント発生や、ドキュメントと実装が知らないうちに乖離することを型で防ぐ設計）。

| イベント名 | 発火タイミング | パラメータ |
|---|---|---|
| `game_start` | 1プレイの開始（冪等。中断からの復元では送らない） | `game_id`、難易度を持つゲームのみ `level`、遊び方を選べるゲームのみ `mode`（#783・#820） |
| `game_end` | 1プレイの終わり（決着 win/loss/draw、または途中離脱 quit） | `game_id` / `result`(win\|loss\|draw\|quit) / `duration_sec`、開始に `mode` を付けたプレイのみ `mode`、そのプレイで 1 度でもミスしたゲームのみ `cause`(pit\|rock\|bird\|animal・最後のミスの原因。#796) |
| `reward_ad` | リワード広告の**視聴完了**（`RewardedRescue` 経由） | `game_id` / `purpose`（上表の7値） |
| `reward_request` | リワード広告の**要求**（タップ。視聴の成否を待たずに送る） | `game_id` / `purpose` |
| `game_open` | ハブからゲーム画面を開いた（`HubView` の `onChange(of: path)` で path が空 → 非空になった1か所） | `game_id` / `source`(hub\|recent\|recommendation\|notification\|first_pick) / `resume`(0\|1)、`hub`・`recent` のみ `position`（1 始まり） |
| `reward_offer` | リワード広告の**提示**が終わった（1 回の提示につき 1 回。下の定義） | `game_id` / `purpose`（上表の7値） / `result`(accepted\|declined\|not_ready) |

- `game_id` の全量は**コード上の一覧を文書側で持たない**（`App/AppGameServices.swift` の
  `registry.modules.map(\.id)` から実行時に作られる）。新ゲームを `registry` に登録するだけで
  自動的に対象へ入るため、**このドキュメントに `game_id` の値そのものを列挙しない**
  （列挙すると新ゲーム追加のたびに手動同期が要り、漏れの温床になる。実際の値は各ゲームの
  `GameModule.id` を参照すること）
- `mode`（`AnalyticsMode`）は遊び方の区分（v1.1.5）。四人打ち麻雀は `tonpuu`（東風戦）/ `single_hand`（一局戦）、
  チャリンコおじさんは `stage`（ステージ制。面番号は `level` の `stage-N`）/ `endless`（エンドレス。`level` を送らない）。
  写像は各ゲームの `analyticsMode`（`MahjongGameLength` / `RunnerMode`）に置く。一局戦は 1 対局が 1 局なので
  `game_start` が機械的に増える。回数を比べるときは `mode` で分け、時間で比べるときは `duration_sec` を使う。
  `game_end` の `mode` は開始時に焼き込んだ値で、途中で遊び方を替えて始め直したときも捨てたプレイの側の値が載る（#783・#785・#820）
- `cause`（`AnalyticsEndCause`・#796・`release/v1.1.5` から）は**そのプレイで最後にミスした原因**。
  ミスのたびにイベントは出さず（イベントの種類は増やさない）、各ゲームが `gameDidMiss` で原因を
  伝えると `GameAnalytics` が覚えておき、そのプレイの `game_end` に載せる。ミスの無いプレイ・ミスの
  概念が無いゲームは鍵ごと送らない。語彙は `pit`（穴）/ `rock`（岩・台座の正面）/ `bird`（鳥）/
  `animal`（犬・イノシシ）の4値に閉じ、障害の種類を足しても enum を増やさない限り値は増えない。
  いまはチャリンコおじさんだけが送る。ステージ制ではミスは決着ではなく `game_end` はクリア（win）か
  途中離脱（quit）でしか出ないので、「何にやられて諦めたか」＝離脱直前の死因として読む。
  GA4 のカスタムディメンション登録が要る（会長操作）
- パラメータの値（`result` / `level` / `purpose` / `source` / `mode` / `cause`）は `CaseIterable` な enum で定義し、
  `AnalyticsTests` に全量のテストを置く。文字列の引数で値を足せる口を作らない（#820。`mode` だけ `String?` だったため、
  文書に無い値が 23 分後に流れ込んだ）
- `level`（`AnalyticsLevel`）はゲームごとの難易度呼称をゲーム横断で読める4段階
  （`beginner`/`normal`/`hard`/`expert`）か、面を進めるゲームは `stage-N` に正規化して送る。
  写像は各ゲームの `analyticsLevel` に置く
- 送信は `GameAnalytics`（`Core/Analytics.swift`）が一括管理し、二重発火の抑制・経過秒の計測・
  離脱と休憩の切り分けをここ1か所に閉じ込める。個々のゲームは
  「開始した」「1手指した」「やり直した」「終局した」「画面を離れた」を伝えるだけでよい
- 設定でオン/オフした境界をまたいだプレイは `game_start`/`game_end` の対応を保証しないため、
  トグル時点で計測中の状態を丸ごと捨てる（`discardPlayState()`。#212）
- `reward_request` と `game_open` はプレイの数え方（`game_start`/`game_end` の対応）に影響しない。
  `reward_ad ÷ reward_request` が完了率、`game_open` の `resume = 1` が「続きから」の再開プレイ
  （`game_start` は再開では送られないため、再開を数える唯一の手段）
- `game_open` の導線は遷移の値そのもの（`HubRoute`）に持たせる。タップの横で別の状態に書き留めると
  タップと path の変化の順序が保証されないため。`resume` も**タップした時点**の「続きから」の判定（ハブのバッジと同じ `GameModule.hasResumableSnapshot`・#809）で決める。
  `notification` は #663 のローカル通知のタップで開いたとき（`release/v1.1.5` から。上の「中断したゲームのお知らせ」を参照）
  `first_pick` はハブ最上部の「はじめの1本」（#721。記録ゼロの初回だけ出る1枚）から開いたとき（`release/v1.1.5` から）
- `source` / `position` / `resume` は GA4 のカスタムディメンション登録が要る（会長操作依頼 #694）
- `reward_offer`（`RewardOfferResult`・#780・`release/v1.1.7` から）の**提示**は、広告を見るかどうかを選ばせる画面
  （確認アラート・コンティニューの幕・リザルトの復活ボタン）が出たこと。無料で済む確認（無料の待った）は含めない。
  各画面は `rewardOffer(_:for:isPresented:services:gameID:)` 修飾子で「出ているか」だけを渡し、押したかどうかは
  `RewardedRescue` の要求が知っている。`result` は、広告ボタンを押して先読み済みの広告があれば `accepted`、
  無ければ `not_ready`（その場で読み込む。#658 の先読みで減る値）、押さずに閉じた・画面を離れたら `declined`。
  見なかった後に同じ画面でもう一度押しても提示は 1 回のまま（タップの数は `reward_request` が持つ）
  - **提示の瞬間が無い面は数えない**: ナンプレのヒント（常設のボタンで、確認を挟まずに広告へ進む）。
    この面は `reward_request ÷ game_start` で読む。対象の一覧は `AnalyticsTests` の `RewardOfferWiringTests` が固定する
  - 読み方（週次会議）: **受諾率** = (`accepted` + `not_ready`) ÷ `reward_offer`、**先読み不足率** = `not_ready` ÷
    (`accepted` + `not_ready`)、**提示率** = `reward_offer` ÷ 該当場面の発生（コンティニュー・復活は `game_end` の `loss`、
    待った・戻す・並べ替えは `game_start`）。いずれも `purpose` × `game_id` で分けて読む。`reward_ad ÷ reward_request` の完了率と合わせると、
    提示 → 受諾 → 視聴完了の漏斗になる
  - `result` は `game_end` と同じパラメータ名で、値の集合が別（イベント名で分けて読む）。GA4 の登録は #1002（会長操作）

---

## テーマ / デザイン

`Theme.swift` で一元管理:
- メインカラー: `Theme.coral` (オレンジ系)
- アクセント: `Theme.teal` (青緑) / `Theme.yellow` / `Theme.ink`
- カードスタイル: `.popCard()` modifier (白背景 + 影)
- 背景: `.popBackground()` modifier
- フォント: `.rounded` デザイン

ゲームカードのアクセントカラーは `Theme.palette` からインデックス順に自動割り当て。

---

## アクセシビリティ

### アニメーション（Reduce Motion 追従・#210）

**新規のアニメーションは必ず `Core` の `Motion` ヘルパー経由で書く**（素の `withAnimation` /
`.animation(_:value:)` を直接使わない）。

| 用途 | 使うもの |
|---|---|
| 宣言的な指定 | `.gameAnimation(_:value:)`（`.animation(_:value:)` の代わり） |
| 命令的な指定 | `withGameAnimation(_:_:)`（`withAnimation(_:_:)` の代わり） |

OS の「視差効果を減らす」が ON のときはアニメーションを `nil`（＝即時反映）に落とし、
**状態変更そのものは必ず実行する**。OFF のときは要求どおりのアニメーションを通すので、
既定の見た目は変わらない。

理由は2つ。①盤面の駒・カード・牌が動く演出は前庭障害・動揺病のあるユーザーに直接影響する。
②App Store の Accessibility Nutrition Labels に **Reduced Motion** の宣言項目があり、
基準は「アニメーションを減らした状態でもすべての一般的なタスクを完了できること」。
1箇所でも追従しないと申告が成立しない。

この規約は `AccessibilityTests` の「アニメーションは Core のヘルパー経由でのみ書かれている」で
機械的に担保している（`Sources/Core` 以外に素の呼び出しが混じるとテストが落ちる）。
