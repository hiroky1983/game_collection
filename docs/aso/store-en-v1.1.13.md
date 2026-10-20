# App Store 商品ページ 入稿パック（v1.1.13 / en-US）

v1.1.13 の en-US の入稿文言。PR #2464 で ASC に入れた値を、2026-10-19 の審査却下（ルーレットが疑似ギャンブルに当たり、
個人アカウントでは配信不可）を受けて **28本**（ルーレットを倉庫へ戻した構成）に直した。ASC にも同じ値を入れ直してある（2026-10-20）。
「ASC の今の値」の列は 2026-10-18 に ASC API（GET のみ）で v1.1.13（PREPARE_FOR_SUBMISSION）の値を読んだもの。
ja は `docs/aso/metadata-v1.1.13.md`。形式・決まりごとは `docs/aso/store-en-v1.1.12.md` を引き継ぐ。

## 0. 決まっていること

- 英語名は**アプリ内の英語名と同じ**（String Catalog の `en`）。v1.1.13 の 3 本:
  いろリレー = **Color Relay**、おじさんの盆栽 = **Ojisan no Bonsai**、サイコロ役づくり = **Dice Combos**。
  ルーレットは審査で疑似ギャンブルとして却下され（2026-10-19）倉庫へ戻したので書かない（PR #2546）。
- 本数は **28本**（ja も 28本）。
- 賭けを連想させる語（`roulette` `casino` `bet` `wager` `gamble` 等）は書かない。
- 使わない語（`store-en-v1.1.12.md` §0 と同じ）: `Reversi` `Othello` `Sudoku` `Breakout` `Arkanoid` `Tetris` `Shanghai`
  `Lights Out` `Yahtzee` `Numberlink`、条件付きの `Klondike`、暗算の文脈の `flash`。v1.1.13 の 3 本の元になった他社の商品名も書かない。
  倉庫のゲームは書かない。

## 1. 変更点（ASC の今の値 → v1.1.13）

| 項目 | 上限 | ASC の今の値（v1.1.13） | v1.1.13 で入れる値 |
|---|---|---|---|
| 名前（appInfo） | 30 | `Asobiba: Mahjong, Shogi, Poker` | 変えない |
| サブタイトル（appInfo） | 30 | `25 Offline Games, No Pop-ups`（28字） | `28 Offline Games, No Pop-ups`（28字） |
| プロモーションテキスト | 170 | **空欄**（v1.1.12 の値は v1.1.13 に引き継がれていない） | §3（167字） |
| キーワード | 100 | v1.1.12 の値（99字） | 変えない（§4） |
| 説明文 | 4000 | v1.1.12 の §6 と同じ（3119字・25本） | §5（28本） |
| このバージョンの新機能 | 4000 | 空欄 | §6（1009字） |
| マーケティング URL / サポート URL / プライバシー URL | — | v1.1.12 と同じ | 変えない |

## 2. サブタイトル（30字）

```
28 Offline Games, No Pop-ups
```

28/30 字。

## 3. プロモーションテキスト（170字）

```
28 classic games in one free app: Mahjong, Shogi, Poker, Solitaire, Number Place and more. Play offline with no sign-up, and no full-screen ads cutting into your game.
```

167/170 字。v1.1.12 の文の本数だけ 25 → 28。

## 4. キーワード（100字）

```
solitaire,chess,hanafuda,koikoi,riichi,blackjack,minesweeper,2048,freecell,spider,gomoku,card,board
```

99/100 字。v1.1.12 のまま（空きが 1 字で、`dice` を足すには既存の語を外す必要がある。外すかは会長判断）。

## 5. 説明文

```
28 classic games in one free app, made in Japan. Mahjong, Shogi, Poker, Solitaire, Number Place and many more, all playable offline.
No full-screen ad will ever pop up in the middle of your game.

[WHY ASOBIBA]
- Play offline: on a plane or in the subway, all 28 games play start to finish.
- Free, no account: no sign-up, no login. Full-screen video ads only play when you choose to watch one, for example to get an extra undo.
- Continue anytime: close the app mid-game and pick up from the same spot next time.
- Records: personal bests, wins and streaks for every game on one screen.
- Play the CPU: one-on-one board and card games, plus four-player Mahjong, Daifugo and Color Relay against three CPU opponents.
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
- Color Relay: match the top card by color or by number and be the first to empty your hand, against three CPU players. Skip, Reverse, +2 and Color Change cards turn the game around.
- Ojisan no Bonsai: drop bonsai into the garden; two of the same kind merge into a grander one, from Cherry Blossom all the way up to the Golden Pine.
- Dice Combos: roll five dice up to three times a turn and fill 12 scoring categories. The dice tumble in 3D.

[GREAT FOR]
- Commutes and flights with no signal
- A five-minute brain workout
- When you feel like a game of shogi or mahjong
```

v1.1.12 からの変更: 冒頭と [WHY ASOBIBA] の本数（25 → 28）、CPU 3人の対戦に Color Relay を追加、[THE GAMES] の末尾に 3 本を追加。

## 6. このバージョンの新機能

```
Three new games!
- Color Relay: match the color or number and be the first to empty your hand. A card game for you and three CPU players.
- Ojisan no Bonsai: a drop-and-merge puzzle. Match bonsai to grow them, from Cherry Blossom up to the Golden Pine.
- Dice Combos: roll five dice up to three times and fill 12 scoring categories. The dice tumble in 3D.
The new games are marked NEW near the top of the home screen.

Improvements
- Hanafuda Koi-Koi: bigger cards, and captured cards are grouped by type.
- Ojisan's Box Puzzle: when you lose, watch an ad to keep playing, once per game.
- Minesweeper: Zoom and Flag Mode are available before your first tap.
- Sakugoe Ojisan: weekly ranking distances are shown in km and m.
- Number Place: with Differentiate Without Color on, mistakes are marked with an ×.
- Better VoiceOver support, plus many small fixes.

28 games, all playable offline with no sign-up.
```

根拠は ja（`metadata-v1.1.13.md` §5）と同じ。`Differentiate Without Color` は iOS の設定名（ja の「色なしで区別」）。

## 7. スクリーンショット

ja と同じく 1 枚目のハブを英語表示の v1.1.13 で撮り直す（NEW の印が 3 本に替わったため）。iPhone・iPad とも。
