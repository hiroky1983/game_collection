# App Store 商品ページ 入稿パック（v1.1.14 / en-US）

v1.1.14 の en-US の入稿文言（会長決裁 2026-10-23・#2053）。ja と同じ考え方で、**トランプを前に出しつつ将棋を残す**。
ja は `docs/aso/metadata-v1.1.14.md`。形式・使わない語は `docs/aso/store-en-v1.1.13.md` §0 を引き継ぐ。
**入稿は v1.1.14 の提出前に社長が ASC API で入れる**。
**2026-10-24 に ASC API で v1.1.14 の en-US に §1〜§5 の値を入れた**（GET で読み直して一致を確認）。新機能は空欄のまま（§6）。

## 0. 決まっていること

- 英語名は**アプリ内の英語名と同じ**（String Catalog の `en`）: おじさんちのねこさがし = **Ojisan's Hidden Cats**、スピード = **Speed**、
  ババ抜き = **Old Maid**、ハーツ = **Hearts**。
- 本数は **32本**（ja も 32本）。賭けを連想させる語・他社の商品名・倉庫のゲームは書かない。
- 名前（appInfo）から `Mahjong` を外して `Cards` を入れ、`Mahjong` はキーワードへ移した（ja と同じ入れ替え）。

## 1. 変更点（v1.1.13 → v1.1.14）

| 項目 | 上限 | ASC の今の値（v1.1.13・2026-10-24 に GET） | v1.1.14 |
|---|---|---|---|
| 名前（appInfo） | 30 | `Asobiba: Mahjong, Shogi, Poker` | `Asobiba: Cards, Shogi, Poker`（28字） |
| サブタイトル | 30 | `28 Offline Games, No Pop-ups` | `32 Offline Games, No Pop-ups`（28字） |
| プロモーションテキスト | 170 | 28 本の文（167字） | §3（162字） |
| キーワード | 100 | `solitaire,chess,hanafuda,koikoi,riichi,blackjack,minesweeper,2048,freecell,spider,gomoku,card,board`（99字） | §4（100字） |
| 説明文 | 4000 | 28本（3589字） | §5（32本） |
| このバージョンの新機能 | 4000 | v1.1.13 の文（1220字） | **空欄**（未定・§6） |

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
ナンプレ,囲碁,チェス,マインスイーパー,暇つぶし,ブロック崩し,麻雀ソリティア,2048,mahjong,chess,solitaire,blackjack,hanafuda,hearts,cats
```

100/100 字（2026-10-24 入稿時に数えた）。en-US の欄は日本のストアでも検索対象になる **2 枠目**（`keywords-cross-localization-v1.1.1.md`）なので、
ja の欄から外した語（ナンプレ・囲碁・チェス・マインスイーパー・暇つぶし・ブロック崩し・麻雀ソリティア・2048）をここへ回した（#2053「キーワードの組み直し」）。
ソリティアは ja のサブタイトルに入ったので日本語では入れず、英語の `solitaire` だけ残した。
残りは英語の語（米国のストア向け）: 名前に `Cards` が入ったので旧キーワードの `card` は外し（App Store は単数・複数を同じ語として扱う前提）、`mahjong` `hearts` と新作の `cats`（Ojisan's Hidden Cats）を足した。
字数のため `koikoi` `freecell` `spider` `gomoku` `minesweeper` `speed` `board` `riichi` は外した（freecell・spider・gomoku は説明文にある）。
`Sudoku`（他社の商標）・`dice` など賭けを連想させうる語は入れていない。

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
- Hearts: four-player trick-taking against three CPUs. Avoid hearts (1 point each) and the queen of spades (13). Lowest total wins.
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

未定（提出前に会長と決める）。ASC の欄は空欄のまま（ja §5 と同じ・2026-10-24 会長指示）。

## 7. スクリーンショット

ja と同じ並び（トランプを先頭、4 枚目に将棋）で英語表示で撮る。`docs/aso/screenshots-v1.1.14.md` に記録する。
