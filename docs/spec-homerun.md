# 柵越えおじさん 仕様

`docs/spec-app.md` から分離した（#2194。内容の変更なし）。ゲームは `Packages/GameKit/Sources/GameHomerun/`。ハブでは先頭の特別枠（→ `docs/spec-app.md`「ハブ画面」）。

#### 柵越えおじさん: 公開状態と動作確認用の強制

- **公開状態**: v1.1.9 でハブに公開済み（`AppGameServices.registry` に登録済み・#1348。v1.1.8 では会長指示 2026-10-02 で非公開にしていた）。
  ハブでは先頭の特別枠として出る（→「ハブ画面」）
- **動作確認用の強制**（`-homerunUnlimited`・`-homerunForceMoon`・`-homerunForcePole`・`-homerunForceWhiffGag`）は
  DEBUG ビルドだけで効く。鍵の宣言と読み取りは `HomerunModel+Debug.swift`（`HomerunDebugOverrides`）の `#if DEBUG` の中だけで、
  出荷ビルドでは端末に同じ鍵が残っていても読まない

#### 柵越えおじさん: 空振りで回って倒れて目を回す演出（#1681・v1.1.8）

振った空振り（見送りは除く）で、打者がそのまま約 1.8 回転して後ろへ尻もちをつき、座って頭をぐるぐる回す（ぐるぐる目・頭上の星 3 つ）。

- **発生**: 1 挑戦の中で 2 回目の空振りは必ず、それ以外の空振りは 1/3 の確率（`HomerunWhiffGag.shows`・`HomerunModel.showsWhiffGag`）
- **間合い**: 演出の空振りは結果の時間を離してから約 4.2 秒に延ばし（`HomerunWhiffGag.resultDuration`・`HomerunModel.resultEnd`）、
  座りきるまで次の球を投げない。結果のカードは座り込んでから（離して 2.4 秒）。演出の間は素振りを受け付けない。次の球で構えに戻る
- **素材**: 骨の動きは `HomerunBatter.usdz` のスイング（1〜44 コマ）の続き（45〜133 コマ）として焼き込み（モデルは 1 つ）。
  体全体の回転・後ろへの傾きは親の実体のヨーで足し、回転の量は座ったとき顔が打席のカメラ（センターカメラ・#1770 で前のカメラだけになった）を向く量。
  ぐるぐる目・星・バットと体の影は表（`HomerunWhiffGag+Samples.swift`・生成物）から毎コマ置く
- **動作確認**: DEBUG ビルドの起動引数 `-homerunForceWhiffGag` で、振った空振りに必ず演出を出す（`HomerunModel.debugForceWhiffGagKey`）

#### 柵越えおじさん: 日次台帳と「広告を見てプレイ」（#1694・v1.1.9）

1 日の挑戦回数は `HomerunLedger`（保存キー `homerun_ledger_v1`・「プレイ記録を消去」の対象外・0:00 に作り直す）。

- **回数（`allowance`）**: 無料 3 ＋ 月が割れたご褒美 +1（#1680・会長決裁 2026-10-04 で +2→+1・上限なし）。打席に立った時点で 1 減る。
  アンケート（回答で +1）は #1956（会長指示 2026-10-08）で機能ごと削除した。旧版が保存した台帳の `surveyDone` は読み込み時に無視する（回数には足さない）
- **広告を見てプレイ**: 回数が 0 のときだけ、打席前と結果に「広告を見てプレイ」を出す（必ずユーザーのタップ・自動再生しない）。
  **見終えたら確認を挟まずにその場で 1 挑戦を始めて打席へ入る**（`HomerunModel.startWithAd`）。回数は増やさない・貯められない
  （v1.1.7 までの「広告を見て挑戦 +1 回」は廃止）。見なかった・読み込めなかった・視聴中に 0:00 をまたいだときは始めず、
  `RewardedRescue` の失敗の知らせを出す。計測は従来どおり `reward_request` / `reward_ad`（purpose `challenge`）
- **1 日の上限**: `HomerunLedger.adLimitPerDay`（定数 1 つ・**5 本**・nil で無制限。会長決裁 2026-10-02・10 本→2026-10-04 に 5 本へ変更）。画面には上限の本数を出さず、
  達したときだけ「今日はここまで。0:00 に 3 回に戻ります」
- **台帳での見分け**: 広告で始めた挑戦は `adPlays`（保存キー `adPlays`・0 のときは書かない）に数え、回数の `used` には数えない。
  挑戦中は `HomerunModel.startedWithAd` が true（#1685 の計測で枠を見分ける材料）
- **保存の互換**: 以前の保存キー `adsWatched`（v1.1.7 までに広告で回数に足した本数）は `legacyAdGrants` として読み、その日のうちは
  回数として使える（0:00 で消える）。1 日の上限にも数える
- **回数の表示**: 今日の残り回数は打席前の「打席に立つ」・結果の「もう一回」ボタンの中に出す（同じ部品 `HomerunStartButton`・文言だけ違う）（「今日の挑戦」のカードは廃止・会長指示 2026-10-04）。
  回数が 5 以下なら点（ボール・残りだけ白）を並べ、6 以上は「⚾ ×残り」の数字（`HomerunCountDisplay`）。
  回数ぶん点を並べると固有幅が伸び、横にはみ出していた（#1694 の不具合）
- **ボタン欄の置き方**: 打席前（打席に立つ／回数 0 なら残り時間と広告を見てプレイ）と結果（もう一回／回数 0 なら残り時間と
  広告を見てプレイ／打席前へ）のボタンは主ボタンが上の縦並び。置き方は画面ごとに `HomerunActionLayout`（`HomerunView.swift`）の
  1 つの値で選ぶ: `.pinned`（バナーの上に固定）・`.inline`（中身のすぐ下）・`.auto`（スクロールするほど長ければ固定、収まればすぐ下）。
  初期値は結果・打席前とも `.inline`（中身 → ボタン → 300×250 を 1 本のスクロールに並べ、下に固定しない。会長決裁 2026-10-06・#1819。
  間隔は両画面とも `HomerunBannerGap.belowResultActions`）。どの置き方でも欄の中でボタンとバナーの間を `Theme.pad` + 間隔
  空ける（#1749 の誤タップ対策）。共通にするのはボタンの部品（`HomerunStartButton`）だけ。会長指示 2026-10-04

#### 柵越えおじさん: 戻る時刻と「戻ったら知らせる」（#1576）

挑戦回数が 0 のとき、打席前の「打席に立つ」を押せない灰色にし（使い切りのシートは廃止・会長決裁 2026-10-04）、
そのすぐ下に端末の 0:00 までの残り（「あと約◯時間◯分で戻ります」・1 分ごとに更新・VoiceOver はボタンの読み上げに含める）、
スクロールの中（説明カードのすぐ下）に「戻ったら知らせる」トグル（既定オフ）を出す。画面を開いたまま 0:00 を越えたら回数を戻す。

- **予約**: トグルをオンにした 1 回だけ、翌 0:00 の 1 分後にローカル通知を 1 件（識別子 `challenge-return.homerun` 固定なので置き換わり、増えない）。音なし・繰り返しなし
- **許可**: 設定の「通知」（#1508 の共有トグル）に従う。オフなら予約せずトグルを無効にする。OS の許諾が未決定なら標準ダイアログで求める（`.provisional` は使わない）
- **保存先**: アプリ側の保存は無い（予約の有無は OS の予約一覧から読み直す）。トグルオフ・設定の「通知」オフで取り消す
- **タップ**: `AppDelegate` が識別子（`challenge-return.homerun`。`userInfo` は持たない）から柵越えおじさんへの着地を決め（`NotificationTapTarget.resolve`・純関数）、ハブが `game_open{source: "challenge_return"}` で開く。設定で非表示にしたゲームは開かない（#1950）
- **実装**: 規則は `HomerunReturnPolicy`（純関数）、予約は `ChallengeReturnReminderService`（`GameServices.returnReminder`）

#### 柵越えおじさん: 月まで飛ぶ隠し演出（#1680・v1.1.8）

タイミングのずれ ±50ms 以内 かつ カーソルがフライの芯の基準点（ボールの中心の 4pt 下）から 0.5pt 以内で振ると、打球が月まで飛ぶ
（`HomerunJudge.isMoonShot`。場外より優先）。1 挑戦の中で回数を数える。

- **1 回目**: カメラが打球を追って真上へ見上げ、空が夜空になる（大気圏を抜けたところで球が燃えて火の玉になる）。月は遠くの点から加速しながら画面いっぱいまで迫り、火の玉が月面に突っ込んでヒビが入る。結果は「384,400 km」と表示
- **2 回目**: 月が半分に割れ、その挑戦は終了（残りの球は没収・それまでの球は記録に残す）。今日のプレイ回数を +1
- **記録**: 表示は 384,400 km だが、自己ベスト・合計・最長には 180m（`HomerunJudge.moonCountedDistance`）として数える。
  Game Center に送るのは週間ランキングだけで、そちらは 384,400 km で数える（下の「週間ランキング」。常設のリーダーボードは会長指示 2026-10-12 で取りやめ）
- **台帳のボーナス枠**: `HomerunLedger` に「月が割れたプレゼント」の回数を持つ（`grantMoonBonus`・+1 ずつ・会長決裁 2026-10-04 で +2→+1・上限なし・当日分として
  0:00 で消える）。保存は Optional のキーで、0 のときは書かない（以前の保存も以前の版も読める）
- **実績**: `HomerunRecords.moonShots`（月まで飛ばした回数）・`moonBreaks`（割れた回数）。保存の互換は台帳と同じ扱い。
  「記録と実績」のページで、1 回以上のときだけ「月まで飛ばした N 回」を出す（打席前には記録を並べない）
- **見せ方**: `HomerunMoonShot`（時刻だけで決まるカメラ・夜空・月）、月の 3D は `HomerunMoonRig`（クレーターの模様の球・ヒビ・
  割れた半球 2 つ・トゥーンの輪郭線。Meshy 不使用）
- **動作確認**: DEBUG ビルドの起動引数 `-homerunForceMoon` で、振れば必ず月まで飛ぶ（`HomerunModel.debugForceMoonKey`）

#### 柵越えおじさん: ファウルポール直撃（#1686・v1.1.8）

打球方向が ±45°（ポールの線）から `HomerunJudge.poleHalfAngle`（柵 100m の所でポールの半径 0.3m + 球の半径が見込む角度・約 0.19°）
以内で、柵（100m）を越える飛距離の打球はポールに当たり、45° の外側（本来のファウル）でも柵越えになる（`HomerunJudge.judge`）。

- **結果**: 種別は柵越え（本数・記録に数える・飛距離はふだんの式の値）。方向は ±45° ちょうどに置き、`isPoleHit`（柵越え かつ
  |方向| ≥ 45°）を保存（`HomerunShot`）の方向・種別から毎回求める（保存の形は変えない）。表示は「ポール直撃！」（結果カード・
  1 球ずつの記録・読み上げ）
- **優先順位**: 月 > ポール直撃 > 場外（`isOutOfPark` はポール直撃・月の打球では false）
- **見せ方**: 打球を追うカメラで、柵越えの放物線をポールの面で切って当て、本塁側へ少し跳ね上がって柵の手前に落ち、弾んで止まる
  （`HomerunBallChase.poleHit`・カードまでの上限は柵越えより長い `poleLimit`）。影は球の真下の地面に追従する
- **ポールの寸法**: 判定と球場の 3D は同じ定数（`HomerunJudge.poleRadius` / `poleHeight`）
- **動作確認**: DEBUG ビルドの起動引数 `-homerunForcePole` で、振れば必ずポールに当たる（向きは振った方向の側・
  `HomerunModel.debugForcePoleKey`）。月の強制が優先

#### 柵越えおじさん: 実績（#1794・v1.1.9）

打席前の「記録と実績」のページ（`HomerunRecordsPage`・`HomerunAchievementsCard`）に、実績 21 種を出す。**名前も条件も解除するまで一覧には出さず、
未解除はすべて「？？？」の枠**にする（解除後に `title` / `detail` を見せる）。

- **種類**（`HomerunAchievement`・`HomerunCore`）: 1 球の結果（はじめての柵越え・場外・ポール直撃・月まで飛ばした・ジャストミート・
  空振りで回って倒れた・たんこぶ「ゴツン！」）／終えた挑戦（10 球すべて柵越え・月を割った・1 挑戦の合計 1,000m 超と 1,500m 超）／
  通算（飛距離 3,000・5,000・8,000・10,000・50,000・100,000m に届く・柵越え 10・30・50・100 本に届く）。
  判定は打球・挑戦・蓄積（`HomerunRecords`）だけから決まる純関数（`earned(byBall:…)` ほか）。通算の実績は挑戦を記録に取り込んだあとに判定するので、
  この版より前から累計が超えていた人も次に挑戦を終えたときにまとめて解除される
- **保存**: `HomerunAchievementLog`（実績の `rawValue` の配列）を `UserDefaults` のキー `homerun_achievements_v1`（`HomerunStorage.achievementsKey`）に持つ。
  知らない値（将来の版が足したもの）は読み捨てずに持ち続け、一覧・件数には出さない。
  **`PlayLog.homerunKeys` に入っており「プレイ記録を消去」の対象**（`homerun_records_v1` と同じ。日次台帳 `homerun_ledger_v1` は対象外）。
  Game Center に連携している人は、次にロビーを開いたとき Game Center 側の解除済みが端末へ戻る
- **解除の表示**: 1 球の結果の演出が終わったところで打席に「実績解禁」を出す（`HomerunModel.unlockBannerDuration`・2.6 秒）。
  挑戦の結果には、その挑戦で解除したもの（`unlockedThisChallenge`）を並べる
- **Game Center**: 実績 ID は `asobiba.homerun.achievement.<rawValue の小文字>`（`HomerunAchievement.gameCenterID`）。全量は
  `GameCenterAchievements.homerunIDs`（Core）で、`GameHomerunTests` が両者の一致を縛る。ハブの「記録」画面の道しるべ（`allIDs`）には**入れない**。
  解除した瞬間に `GameCenterReporter.reportUnlocked`（未サインインなら何もしない）で送る
- **ロビーを開くたびの同期**: `HomerunModel.syncGameCenterAchievements`（`HomerunView` の `.task`）が `fetchUnlockedAchievementIDs`
  （`GameCenterService.unlockedAchievementIDs()`・プロトコルに追加）で Game Center 側の解除済みを読み、端末の記録と**和集合**に合わせ、
  端末にだけあるぶん（あとから連携した人のそれまでの分）を送る。未連携・読めなかったとき（オフライン等）は何もしない
- **前提**: App Store Connect への実績の登録は、柵越えおじさんをハブに載せる版が決まった時点の**会長操作**で、それまで未登録。
  ハブ非公開の間は Game Center に出ない（端末内の記録・一覧は動く）

#### 柵越えおじさん: 週間ランキング（#1792・v1.1.11）

Game Center の**定期リーダーボード**（毎週月曜 0:00 JST 開始・7 日・7 日ごとに繰り返し・ベストスコア型・High to Low）に 1 挑戦の総飛距離を送り、アプリ内にランキングページを出す。柵越えおじさんの Game Center の順位表はこの週間ランキングだけ（常設の `asobiba.homerun.distance`（#2060）は会長指示 2026-10-12 で取りやめ・ASC から削除・アプリからも送らない）。

- **送る値**: 総飛距離 m（`HomerunWeekly.score(for:)`）。**月まで飛んだ打球は 384,400,000 m（画面表示どおり 384,400 km）で数える**（常設の記録・通算は 180 m のまま）。上限は 768,801,440 m（月 2 回＋ 180 m × 8 球）で、超える値は送らない。
- **送り先 ID は `GameCenterLeaderboard.homerunWeekly`（`String?`）**。App Store Connect に作成する（会長操作・`docs/game-center-setup.md`）まで nil だった。#2058（`release/v1.1.11`）で `"asobiba.homerun.weekly"` を設定済み。nil に戻せば送信もランキングページへの遷移もしない（`HomerunModel.weekly == .off`）。
- **流れ**: 決着（`record`）で、送る前の順位表を読む → 送信を待つ → 送った後の順位表を読む（`HomerunModel+Weekly`）。サインイン済みなら「10 球の結果の演出 → ランキングページ → 結果ページ」。ページは読み込み中・失敗でも「結果を見る」で先へ進める（待たされない）。未サインインはページを挟まず、結果ページの「今週のランキング」の行から「Game Center に登録すると見られます」の案内ページを開く。
- **ランキングページ**: 参加人数チップ・今週の自分（順位・距離・先週の順位・あと ◯ で ◯位）・上位 20 件（上位の外なら末尾に自分）。月まで飛んだ行は km 表記と補足。注記に「予告なく終了する場合があります」。順位が上がったときは入れ替えアニメ（B 案「一気に飛び上がる」）。Reduce Motion では最終の並びをそのまま出す。表の設計は `docs/design/homerun-ranking/`。
- **結果ページ**: 「今週のランキング　◯位にランクイン」の 1 行だけ（表は出さない）。押すとランキングページを静止で開く。
- **打席前の「今週のランキング」の行（#2216・#2217・v1.1.12）**: 打席前の画面（`HomerunLobbyView`）に、上の段が見出し・下の段が「◯位 / ◯人」か状態の文言の 1 行を出す（`HomerunLobbyRankRow`。どの状態でも高さは変わらない）。押すと結果のあとと同じランキングページを静止で開く（「打席前に戻る」）。送り先が未作成（`.off`）のときは行を出さない。状態の文言は 未サインイン「Game Center に登録すると見られます」・読み込み中・失敗「ランキングを取得できませんでした」・記録なし「今週はまだ記録がありません」。
  - **読み直し**: 打席前に出るたび・アプリに戻る（`scenePhase == .active`）たび・失敗の行（ページ）を開いたときに `HomerunModel.refreshLobbyWeekly` が読む（状態は決着後の `weekly` とは別の `lobbyWeekly`）。前に読めた今週の順位があれば、読み直しの間も失敗したときも出し続ける（一時的なオフラインで消さない）。
  - **週の切り替わり**: 読んだ順位表の回の終わり（`board.end`）まで待って読み直す（`HomerunWeekEndRefresh`）。表が前週のもの（`HomerunWeekly.isPastWeek`）なら前週の順位は出さず、「今週はまだ記録がありません」の空の表にする（`lobbyWeeklyState(now:)`・1 分ごとに今の時刻で引き直す）。
- **Game Center のプロトコル**: `GameCenterService` に `submitAndWait`・`loadBoard`（既定は何もしない）、`GameCenterReporter` に `submitWeeklyAndWait`・`loadWeeklyBoard`（未サインインでは呼ばない）を追加。

#### 柵越えおじさん: たんこぶ（#1793・v1.1.9）

打ち上げた球が自分の頭に落ちて、ヘルメットの上にたんこぶができるギャグ演出（`HomerunCore/HomerunTankobu`・見た目は `GameHomerun/HomerunTankobuGag`）。

- **発生**: ポップフライになる当たり（`HomerunLaunch.pop`）のうち、球の結構下を擦って当てたもの（カーソルの縦のずれが
  `HomerunTankobu.scrapeFloor` 以上＝ポップの帯の芯の基準点より下）で、フェアに落ちるもの（ファウル・空振りは除く）。
  条件を満たした当たり 1 回あたりの確率は `HomerunTankobu.chance`（1/5）、**1 挑戦に 1 回まで**（`perChallenge`）。
  乱数は `HomerunModel.tankobuRoll`（テストで差し替える）。値は初期値で、会長 QA で調整する前提のため `HomerunTankobu` の定数に集めてある
- **結果**: 打球を置き換え（`HomerunTankobu.apply`）、**飛距離 0・方向 0**（真上に上がって落ちてくる）。種別・タイミングは元のまま。
  1 球として記録には数える（飛距離 0 として合計・集計に入る）。`isTankobu` の打球にはキラキラ目などの結果の記号を付けない
- **見せ方**: 球が頭に落ちて座り込み、次の球の構えでヘルメットの上にたんこぶを残す（`HomerunFaceMark.waitingLump`）。
  結果の間は `HomerunTankobuGag.resultDuration`。音は `HomerunSound.tankobu`
- **実績**: 「ゴツン！」（`HomerunAchievement.tankobu`）

#### 柵越えおじさん: 怒りマークと怒りゲージ（#1769・#1797・v1.1.9）

振った空振り（見送りは除く）の次の球の構えで、頭の横に白い吹き出しに入れた赤い 💢 を出す（`HomerunFaceMark.waitingAngry`・弾ませてプンプンさせる）。
判定・飛距離は変えない。

- **怒りゲージ**（裏パラメータ・画面には出さない・`HomerunModel.angerGauge`）: 振った空振りで `angerWhiffGain`（1）増え、
  当たり（ファウル含む）で `angerHitRelief`（1）減る（0 未満にしない）。見送りは変えない。挑戦の開始で 0。数値は `HomerunFaceMark` の定数に集めてある
- **段階②**: ゲージが `angerStageThreshold`（3）以上のとき、💢 に加えて**頭から湯気**を出す（`waitingAngryHot`。会長確定 2026-10-04。**顔の赤みは入れない**）
- **他の構え記号との優先**: たんこぶ > 柵越えの次のキラキラ目（`waitingSparkle`）> 怒りマーク。挑戦が終わる球（10 球目・月が割れた球）の次は出さない

#### 柵越えおじさん: 場面の効果音（会長指示 2026-10-04・v1.1.9）

打ち出し・風切り・当たり（芯 / 普通 / 詰まり / ジャストミートの止め）・柵越え / 場外の歓声（合成の代用）・ポール直撃・ミット・
月への上昇 / 月が割れる・たんこぶ・回って倒れる・怒りマーク・実績解禁の 16 場面。音源ファイルは同梱せず、`SoundSynth`
（ノイズ + 帯域フィルタ・周波数の滑らかな変化・減衰の違う正弦波の重ね合わせ）で起動後に合成する（`HomerunSound`）。

- **入口**: `GameServices.homerunSound`（`HomerunSoundService`）。触覚と 1 対 1 の `feedback` とは別（触覚の無い瞬間にも鳴り、
  場面の音どうしは止め合わずに重ねる）。App の実体は `SoundFeedbackService` を共有し、`.ambient` の音声セッションと
  設定の「効果音」のオン / オフ（`GatedHomerunSoundService`）に従う
- **触覚**（#1949）: 音と同じ発火点（`HomerunSoundPlayer`）に相乗りして場面ごとに鳴らす。対応は `HomerunFeedbackCue`
  （空振り・詰まり=light / 芯=medium / ジャストミート・フェンス直撃=rigid / 柵越え・場外・月が割れる=success /
  ファウルポール=warning / たんこぶ=error。打ち出し・素振りなどは無し）。`feedback` は `SoundEffect` にも相乗りして
  場面の音と二重に鳴るため使わず、触覚だけの入口 `GameServices.haptics`（設定の「触覚」のオン / オフに従う）へ渡す
- **鳴らす時刻**: `HomerunSoundCues`（純粋な関数）が演出と同じ式（打点・打球の道・月・たんこぶ・空振りの演出の時刻）から出し、
  `HomerunSoundPlayer`（View の `.task(id: step)`）が待って鳴らす。止めている間は鳴らさない
- **差し替え**: 場面 → 合成の式の対応は `HomerunSound.samples` の 1 か所（いまは試作の A 案）
- **長さ**: 操作に直結する音は 0.3 秒未満、見せ場の余韻・歓声・上昇音（`HomerunSound.longSounds`）だけ 3.5 秒未満まで
- **動作確認**: DEBUG ビルドは鳴らした音を `[HomerunSFX] <壁時計の秒> <音>` で標準出力へ書く（録画に音を重ねる用）
