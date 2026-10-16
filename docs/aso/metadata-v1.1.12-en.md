# App Store 商品ページ 入稿パック（v1.1.12 / en-US）— 下書き

#2170（多言語⑦）の en-US 欄。会長決定（2026-10-12・案A）で、ASC の英語（米国）の欄は日本のストアの
2つ目の日本語キーワード欄として使うのをやめ、**本当の英語ページ**にする。ja 欄は #2271 の担当で、このファイルでは扱わない。

> **状態: 下書き（2026-10-17）**。ASC への入稿・英語スクショ・Game Center の英語名の入稿は、
> アプリ側の英語名の変更（オセロ → Osero・おじさんシリーズのローマ字化）がマージされてから行う（スクショに名前が写るため）。
> 入稿したら、この注記を「入稿済み」と ASC の読み戻し結果に差し替える。

## 0. 決まっていること（会長 2026-10-17）

- 英語名は**アプリ内の英語名と同じ**にする。おじさんシリーズとオセロはローマ字:
  オセロ = **Osero**、柵越えおじさん = **Sakugoe Ojisan**、チャリンコおじさん = **Charinko Ojisan**、
  おじさんの荷物運びパズル = **Ojisan's Box Puzzle**（ローマ字はハブのタイルに収まらないため・2026-10-17）、大富豪 = **Daifugo**。
- 本数は **25本**（柵越えおじさんを含む。ja も 25本）。
- 「made in Japan」は残す（ja も「日本製」を戻した）。
- 使わない語（`docs/aso/metadata-v1.1.1.md` §3 の ⚠️ ブロック）: `Reversi` `Othello` `Sudoku` `Breakout` `Arkanoid`
  `Tetris` `Shanghai` `Lights Out` `Yahtzee` `Numberlink`。条件付きの `Klondike` も避ける。暗算の文脈で `flash` も使わない。
  倉庫のゲーム（ハブに出ていないもの）は書かない。

## 1. 変更点（ASC の現在値 → v1.1.12）

ASC の en-US 欄は v1.1.11 まで日本語のキーワード欄の代わりに使っていたため、**今の値はすべて日本語**
（名前「あそびば：麻雀 ポーカー 2048 将棋 マインスイーパー」、サブタイトル「オフラインで遊べる24種｜勝手に出る全画面広告なし」、
説明文は ja と同じ全文、キーワードには禁止語の `数独` を含む）。v1.1.12 で全項目を英語に置き換える。

| 項目 | 上限 | v1.1.12 |
|---|---|---|
| 名前（appInfo・en-US） | 30 | §2 |
| サブタイトル（appInfo・en-US） | 30 | §3 |
| プロモーションテキスト | 170 | §4 |
| キーワード | 100 | §5 |
| 説明文 | 4000 | §6 |
| このバージョンの新機能 | 4000 | §7 |
| マーケティング URL / サポート URL | — | `https://web-murex-sigma-62.vercel.app/en` |
| プライバシーポリシー URL（appInfo・en-US） | — | `https://web-murex-sigma-62.vercel.app/en/privacy` |

## 2. 名前（30字）

```
Asobiba: Mahjong, Shogi, Poker
```

30/30 字。ホーム画面のアプリ名（英語）は「Asobiba」。

## 3. サブタイトル（30字）

```
25 Offline Games, No Pop-ups
```

28/30 字。ja の「勝手に出る全画面広告なし」を短く言ったもの。

## 4. プロモーションテキスト（170字）

```
25 classic games in one free app: Mahjong, Shogi, Poker, Solitaire, Number Place and more. Play offline with no sign-up, and no full-screen ads cutting into your game.
```

167/170 字。

## 5. キーワード（100字）

```
solitaire,chess,hanafuda,koikoi,riichi,blackjack,minesweeper,2048,freecell,spider,gomoku,card,board
```

99/100 字。名前・サブタイトルにある語（Mahjong・Shogi・Poker・games・offline）は重ねない。

## 6. 説明文

```
25 classic games in one free app, made in Japan. Mahjong, Shogi, Poker, Solitaire, Number Place and many more, all playable offline.
No full-screen ad will ever pop up in the middle of your game.

[WHY ASOBIBA]
- Play offline: on a plane or in the subway, all 25 games play start to finish.
- Free, no account: no sign-up, no login. Full-screen video ads only play when you choose to watch one, for example to get an extra undo.
- Continue anytime: close the app mid-game and pick up from the same spot next time.
- Records: personal bests, wins and streaks for every game on one screen.
- Play the CPU: one-on-one board and card games, plus four-player Mahjong and Daifugo against three CPU opponents.
- Game Center: global leaderboards and achievements.
- Make it yours: move favorites to the top and hide the rest.
- English and Japanese: switch the language anytime in Settings.

[THE GAMES]
- Mahjong (4-player): full riichi rules with pon, chi, kan and complete scoring. East-only match or a quick single hand.
- Shogi: Japanese chess against a capable CPU, with even and handicap games. Pieces keep their kanji, with an English guide in the rules.
- Go: 9x9 board against the CPU, with area scoring and handicap stones.
- Chess: full rules including castling, en passant and promotion.
- Osero: sandwich your opponent's discs to flip them to your color, and fight the CPU for the corners.
- Gomoku: five in a row on a 15x15 board, with or without forbidden moves.
- Hanafuda Koi-Koi: match cards by month and build scoring sets. Call "koi-koi" to double your points, if you dare.
- Poker: five-card draw against the CPU, with optional hand bonuses and a double-up round.
- Blackjack: beat the dealer without going over 21.
- Daifugo: a Japanese climbing card game with revolutions and card swaps.
- Memory Match: find the pairs before the CPU does.
- Card Shiritori: grab picture cards whose words chain together, against the CPU and the clock. (The words are in Japanese.)
- Solitaire: the classic, with draw-one or draw-three.
- FreeCell: every deal is checked to be solvable.
- Spider Solitaire: one, two or four suits.
- Mahjong Solitaire: clear matching tiles in pairs, with hints and reshuffles.
- Number Place: 9x9 logic puzzles in three levels, each with exactly one solution.
- 2048: swipe and merge tiles to reach 2048.
- Minesweeper: three board sizes, with flags.
- 15 Puzzle: slide the tiles into order in the fewest moves.
- Block Breaker: clear every block, with power-ups.
- Charinko Ojisan: a tap-to-jump runner across 42 stages in seven worlds, chasing a lottery ticket blown away by the wind. Endless mode too.
- Sakugoe Ojisan: a home run derby. Hit the machine's pitches over the fence. Three free rounds a day, plus a weekly Game Center leaderboard.
- Ojisan's Box Puzzle: stack falling pairs of boxes and clear four or more in a row. Every box strains Ojisan's back.
- Quick Mental Math: numbers appear one at a time; add them in your head and enter the total.

[GREAT FOR]
- Commutes and flights with no signal
- A five-minute brain workout
- When you feel like a game of shogi or mahjong
```

- 約 3,100 字。
- ゲーム名はアプリ内の英語名と同じ（`Daifugo` `Memory Match` `Number Place` `Block Breaker` など）。

## 7. このバージョンの新機能

```
Asobiba is now available in English!
- Switch between English and Japanese anytime in Settings.
- Shogi: new handicap games (Rook or Bishop handicap, for you or the CPU).
- Refreshed home screen, new app icon and redrawn Hanafuda cards.
- Better VoiceOver support, plus many fixes and improvements.
```

根拠: v1.1.12 マイルストーンの #2109〜#2169（英語化）・#2179（将棋の駒落ち）・#1831/#2175（ハブ刷新）・#2189（アイコン）・
#2188（花札の札）・#2232/#2280 ほか（VoiceOver）。

## 8. スクリーンショット（iPhone 6.9 インチ）

- アプリを英語表示（`-appLanguage en`）にして撮る。撮影は `Scripts/capture-aso-screenshots.sh`（main）＋ `release/v1.1.12` のアプリ。
- 並びは ja（#2271）と同じ考え方: 1〜3 枚目でいろいろなゲームが入っていると分かる並びにし、柵越えおじさんは 1 枚。
- アプリ側の英語名の変更（Osero ほか）がマージされてから撮る。

## 9. Game Center の英語名（en-US）

リーダーボード 20 本・実績 21 件（アーカイブ 4 件を除く）。今は ja のみ。英語の追加は v1.1.12 と同じ提出で審査に出す。

### リーダーボード

| ID | ja | en（案） |
|---|---|---|
| asobiba.blocks.score | ブロック崩し ハイスコア | Block Breaker High Score |
| asobiba.solitaire.time | ソリティア 最短タイム | Solitaire Best Time |
| asobiba.2048.score | 2048 ハイスコア | 2048 High Score |
| asobiba.poker.chips | ポーカー 最高チップ | Poker Most Chips |
| asobiba.blackjack.chips | ブラックジャック 最高チップ | Blackjack Most Chips |
| asobiba.minesweeper.time.beginner | マインスイーパー 初級 最短タイム | Minesweeper Beginner Best Time |
| asobiba.minesweeper.time.intermediate | マインスイーパー 中級 最短タイム | Minesweeper Intermediate Best Time |
| asobiba.minesweeper.time.expert | マインスイーパー 上級 最短タイム | Minesweeper Expert Best Time |
| asobiba.sudoku.time.easy | ナンプレ かんたん 最短タイム | Number Place Easy Best Time |
| asobiba.sudoku.time.normal | ナンプレ ふつう 最短タイム | Number Place Normal Best Time |
| asobiba.sudoku.time.hard | ナンプレ むずかしい 最短タイム | Number Place Hard Best Time |
| asobiba.mahjongsolitaire.time | 麻雀ソリティア 最短タイム | Mahjong Solitaire Best Time |
| asobiba.runner.stage | チャリンコおじさん 到達ステージ | Charinko Ojisan Stage Reached |
| asobiba.freecell.time | フリーセル 最短タイム | FreeCell Best Time |
| asobiba.runner.distance | チャリンコおじさん エンドレス 走行距離 | Charinko Ojisan Endless Distance |
| asobiba.spider.time.1suit | スパイダーソリティア 最短タイム（1スート） | Spider Solitaire Best Time (1 Suit) |
| asobiba.spider.time.2suit | スパイダーソリティア 最短タイム（2スート） | Spider Solitaire Best Time (2 Suits) |
| asobiba.spider.time.4suit | スパイダーソリティア 最短タイム（4スート） | Spider Solitaire Best Time (4 Suits) |
| asobiba.hanafuda.points | 花札こいこい 最高得点 | Hanafuda Koi-Koi High Score |
| asobiba.homerun.weekly | 柵越えおじさん 週間ランキング | Sakugoe Ojisan Weekly Ranking（単位 `m` は ja と同じ） |

名前の文字数の上限は入稿時に API の応答で確かめ、超えたら `Best Time` → `Best` 等で詰める。

### 実績

名前・獲得後の説明はアプリ内の英語の実績一覧（`HomerunCore` の String Catalog）と同じ文。獲得前の説明（ヒント）はアプリに無いので新しく訳した。
画像は ja と同じものを en にも上げる（言語ごとに必須）。

| ID（`asobiba.homerun.achievement.`） | 名前 | 獲得前 | 獲得後 |
|---|---|---|---|
| firsthomer | First Homer | Hit a ball over the fence | Hit your first ball over the fence |
| outofpark | Out of the Park | Maybe you can hit it even farther | Cleared the very last row and left the ballpark |
| polehit | Ping Off the Pole | Keep an eye on where the ball flies | Clanged it off the foul pole for a homer |
| moon | Fly Me to the Moon | Maybe you can hit it somewhere unbelievable | Hit a ball all the way to the moon |
| moonbroken | Moon Breaker | Try again in the same round; something might happen | Hit the moon twice in one round and cracked it in half |
| alltenhomers | Ten for Ten | Stay sharp until the last pitch of a round | Sent all 10 pitches of a round over the fence |
| justmeet | Sweet Spot | Look for the perfect timing | Perfect timing, dead on the sweet spot |
| whiffspin | Spin Cycle | A big swing might have a surprise ending | Whiffed so hard you spun around and fell over |
| tankobu | Bonk! | Watch where your pop-ups come down | Popped one straight up and it came down on your own head |
| fartotal1000 | 1,000 m in One Round | Push your total distance in one round | Topped 1,000 m of total distance in one round |
| fartotal | 1,500 m in One Round | Your round total can go even farther | Topped 1,500 m of total distance in one round |
| career3000 | 3,000 m Career | Keep adding up your distance | Reached 3,000 m of total career distance |
| career5000 | 5,000 m Career | Keep adding up your distance | Reached 5,000 m of total career distance |
| career8000 | 8,000 m Career | There's still more distance to go | Reached 8,000 m of total career distance |
| career10000 | 10,000 m Career | A milestone may be close | Reached 10,000 m of total career distance |
| career50000 | 50,000 m Career | Play long enough and you might find out | Reached 50,000 m of total career distance |
| career100000 | 100,000 m Career | Play all the way and see what appears | Reached 100,000 m of total career distance |
| careerhomers10 | 10 Career Homers | Keep stacking up homers | Hit 10 career homers |
| careerhomers30 | 30 Career Homers | Stack up even more homers | Hit 30 career homers |
| careerhomers50 | 50 Career Homers | You might be halfway there | Hit 50 career homers |
| careerhomers100 | 100 Career Homers | Clear the fence more times than you can count | Hit 100 career homers |

## 10. 入稿の手順（アプリ側のマージ後）

1. §2〜§7 の字数と使用禁止語を再確認する。
2. ASC API で v1.1.12 の en-US の appStoreVersionLocalization（説明文・キーワード・プロモーション・新機能・URL）と
   appInfoLocalization（名前・サブタイトル・プライバシー URL）を更新し、GET で読み戻して全文一致を確かめる。ja 欄には触らない。
3. 英語スクショを撮って en-US の 6.9 インチに入れる（§8）。
4. Game Center の en-US を v2 API（version → localizations）で作る。実績は画像も上げる（§9）。
5. このファイルの「下書き」の注記を「入稿済み」と読み戻し結果に差し替える。
