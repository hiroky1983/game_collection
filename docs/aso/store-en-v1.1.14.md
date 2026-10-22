# App Store 商品ページ 入稿パック（v1.1.14 / en-US）

v1.1.14 の en-US の入稿文言（会長決裁 2026-10-23・#2053）。ja と同じ考え方で、**トランプを前に出しつつ将棋を残す**。
ja は `docs/aso/metadata-v1.1.14.md`。形式・使わない語は `docs/aso/store-en-v1.1.13.md` §0 を引き継ぐ。
**入稿は v1.1.14 の提出前に社長が ASC API で入れる**（ASC にはまだ入っていない）。

## 0. 決まっていること

- 英語名は**アプリ内の英語名と同じ**（String Catalog の `en`）: おじさんちのねこさがし = **Ojisan's Hidden Cats**、スピード = **Speed**、
  ババ抜き = **Old Maid**、ハーツ = **Hearts**。
- 本数は **32本**（ja も 32本）。賭けを連想させる語・他社の商品名・倉庫のゲームは書かない。
- 名前（appInfo）から `Mahjong` を外して `Cards` を入れ、`Mahjong` はキーワードへ移した（ja と同じ入れ替え）。

## 1. 変更点（v1.1.13 → v1.1.14）

| 項目 | 上限 | v1.1.13 | v1.1.14 |
|---|---|---|---|
| 名前（appInfo） | 30 | `Asobiba: Mahjong, Shogi, Poker` | `Asobiba: Cards, Shogi, Poker`（28字） |
| サブタイトル | 30 | `28 Offline Games, No Pop-ups` | `32 Offline Games, No Pop-ups`（28字） |
| プロモーションテキスト | 170 | 28 本の文 | §3（162字） |
| キーワード | 100 | 99字 | §4（98字） |
| 説明文 | 4000 | 28本 | §5（3784字・32本） |
| このバージョンの新機能 | 4000 | 空欄 | §6 |

## 2. サブタイトル（30字）

```
32 Offline Games, No Pop-ups
```

## 3. プロモーションテキスト（170字）

```
32 classic games in one free app: Daifugo, Hearts, Old Maid, Shogi, Poker, Solitaire. Play offline with no sign-up, and no full-screen ads cutting into your game.
```

## 4. キーワード（100字）

```
mahjong,chess,hanafuda,koikoi,blackjack,minesweeper,2048,freecell,spider,gomoku,hearts,speed,board
```

名前に入った `card`、説明文で足りる `solitaire` `riichi` は外し、`mahjong` `hearts` `speed` を足した（`dice` などは入れていない）。

## 5. 説明文

```
32 classic games in one free app, made in Japan. Cards, Shogi, Poker, Solitaire, Mahjong and many more, all playable offline.
No full-screen ad will ever pop up in the middle of your game.

[WHY ASOBIBA]
- Play offline: on a plane or in the subway, all 32 games play start to finish.
- Free, no account: no sign-up, no login. Full-screen video ads only play when you choose to watch one, for example to get an extra undo.
- Continue anytime: close the app mid-game and pick up from the same spot next time.
- Records: personal bests, wins and streaks for every game on one screen.
- Play the CPU: one-on-one board and card games, plus four-player Mahjong, Daifugo, Old Maid, Hearts and Color Relay against three CPU opponents.
- Game Center: global leaderboards and achievements.
- Make it yours: move favorites to the top and hide the rest.
- English and Japanese: switch the language anytime in Settings.

[THE GAMES]
- Daifugo: a Japanese climbing card game with revolutions and card swaps.
- Old Maid: four players, three CPUs. Pair up and discard, draw from your neighbor, and don't get stuck with the Joker. A CPU holding it may give it away.
- Hearts: four-player trick-taking against three CPUs. avoid hearts (1 point each) and the queen of spades (13). Lowest total wins.
- Speed: play cards one up or down on the two center piles before the CPU does. No turns, and three CPU paces.
- Blackjack: beat the dealer without going over 21.
- Poker: five-card draw against the CPU. Play a 10-round match and score points for the hands you make.
- Memory Match: find the pairs before the CPU does.
- Hanafuda Koi-Koi: match cards by month and build scoring sets. Call "koi-koi" to double your points, if you dare.
- Card Shiritori: grab picture cards whose words chain together, against the CPU and the clock. (The words are in Japanese.)
- Solitaire: the classic, with draw-one or draw-three.
- FreeCell: every deal is checked to be solvable.
- Spider Solitaire: one, two or four suits.
- Shogi: Japanese chess against a capable CPU, with even and handicap games.
- Mahjong (4-player): full riichi rules with pon, chi, kan and complete scoring.
- Go: 9x9 board against the CPU, with area scoring and handicap stones.
- Chess: full rules including castling, en passant and promotion.
- Osero: sandwich your opponent's discs to flip them to your color, and fight the CPU for the corners.
- Gomoku: five in a row on a 15x15 board, with or without forbidden moves.
- Mahjong Solitaire: clear matching tiles in pairs, with hints and reshuffles.
- Number Place: 9x9 logic puzzles in three levels, each with exactly one solution.
- 2048: swipe and merge tiles to reach 2048.
- Minesweeper: three board sizes, with flags.
- 15 Puzzle: slide the tiles into order in the fewest moves.
- Block Breaker: clear every block, with power-ups.
- Charinko Ojisan: a tap-to-jump runner across 42 stages in seven worlds. Endless mode too.
- Sakugoe Ojisan: a home run derby. Hit the machine's pitches over the fence. Three free rounds a day.
- Ojisan's Box Puzzle: stack falling pairs of boxes and clear four or more in a row. Every box strains Ojisan's back.
- Quick Mental Math: numbers appear one at a time; add them in your head and enter the total.
- Color Relay: match the top card by color or number and be the first to empty your hand, against three CPUs.
- Ojisan no Bonsai: drop bonsai into the garden; two of the same kind merge into a grander one.
- Dice Combos: roll five dice up to three times a turn and fill 12 scoring categories.
- Ojisan's Hidden Cats: a solo logic puzzle. Find the cats hiding in the house, one per room, row and column, never touching.

[GREAT FOR]
- Commutes and flights with no signal
- A five-minute brain workout
- When you feel like a game of shogi or mahjong
```

v1.1.13 からの変更: 本数 28 → 32、冒頭の例に Cards を前へ、CPU 3人の対戦に Old Maid・Hearts を追加、[THE GAMES] はカード → Shogi → その他の順にして新作 4 本を追加。

## 6. このバージョンの新機能

```
Four new games!
- Speed: play cards one up or down on the center piles before the CPU does. No turns, and three CPU paces.
- Old Maid: four players with three CPUs. A CPU holding the Joker may give it away with its face.
- Hearts: avoid the hearts and the queen of spades in a four-player game against three CPUs.
- Ojisan's Hidden Cats: find the cats hiding in the house, one in every room. A solo logic puzzle.
The new games are marked NEW near the top of the home screen.

Improvements
- Daifugo and Color Relay: choose how strong the CPUs are. Daifugo also has an optional suit-lock rule.
- Solitaire and FreeCell: double-tap a card to send it to the foundation.
- Solitaire, Spider and FreeCell: replay the same deal after a dead end or a win.
- Hanafuda Koi-Koi: change the settings and start again right after a match.
- Chess, Go, Gomoku and Osero: win/loss records are kept separately for each CPU level.
- Number Place: the clear screen shows how many hints you used.
- Better VoiceOver support, plus many small fixes.

32 games, all playable offline with no sign-up.
```

根拠は ja（`metadata-v1.1.14.md` §5）と同じ。

## 7. スクリーンショット

ja と同じ並び（トランプを先頭、4 枚目に将棋）で英語表示で撮る。`docs/aso/screenshots-v1.1.14.md` に記録する。
