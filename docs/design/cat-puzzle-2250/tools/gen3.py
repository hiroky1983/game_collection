#!/usr/bin/env python3
"""Queens 型 N×N の問題を山登りで作る。

1. 隣接禁止を満たす答え（行ごとの列）を 1 つ決め、そこを種に区画を育てる。
2. 解の数（上限 60 で打ち切り）を数え、2 以上なら「答えのマス以外の 1 マスを隣の区画へ付け替える」
   手をランダムに試し、区画の連結を保ちつつ解の数が増えない手を採用する。解が 1 つになったら終了。
"""
import random, sys
N = int(sys.argv[1]) if len(sys.argv) > 1 else 7
random.seed(int(sys.argv[2]) if len(sys.argv) > 2 else 0)
MIN_SIZE = 3

def count_solutions(regions, limit=60):
    cnt = 0; used_c = [False]*N; used_r = [False]*N; cols = [-1]*N
    def rec(r):
        nonlocal cnt
        if cnt >= limit: return
        if r == N: cnt += 1; return
        for c in range(N):
            if used_c[c] or used_r[regions[r][c]]: continue
            if r > 0 and abs(cols[r-1]-c) <= 1: continue
            used_c[c] = used_r[regions[r][c]] = True; cols[r] = c
            rec(r+1)
            used_c[c] = used_r[regions[r][c]] = False; cols[r] = -1
    rec(0); return cnt

def neighbors(r, c):
    for dr, dc in ((1,0),(-1,0),(0,1),(0,-1)):
        rr, cc = r+dr, c+dc
        if 0 <= rr < N and 0 <= cc < N:
            yield rr, cc

def grow(sol):
    regions = [[-1]*N for _ in range(N)]
    for k in range(N): regions[k][sol[k]] = k
    remaining = N*N - N
    while remaining:
        empties = [(r, c) for r in range(N) for c in range(N) if regions[r][c] == -1]
        r, c = random.choice(empties)
        nb = [regions[rr][cc] for rr, cc in neighbors(r, c) if regions[rr][cc] != -1]
        if not nb: continue
        regions[r][c] = random.choice(nb); remaining -= 1
    return regions

def connected(regions, k):
    cells = [(r, c) for r in range(N) for c in range(N) if regions[r][c] == k]
    if not cells: return False
    seen = {cells[0]}; stack = [cells[0]]
    while stack:
        r, c = stack.pop()
        for rr, cc in neighbors(r, c):
            if regions[rr][cc] == k and (rr, cc) not in seen:
                seen.add((rr, cc)); stack.append((rr, cc))
    return len(seen) == len(cells)

def solve_one(sol_seed):
    regions = grow(sol_seed)
    cur = count_solutions(regions)
    for step in range(4000):
        if cur == 1: return regions
        r, c = random.randrange(N), random.randrange(N)
        if sol_seed[r] == c: continue  # 答えのマスは動かさない
        a = regions[r][c]
        nbk = {regions[rr][cc] for rr, cc in neighbors(r, c)} - {a}
        if not nbk: continue
        b = random.choice(sorted(nbk))
        size_a = sum(row.count(a) for row in regions)
        if size_a - 1 < MIN_SIZE: continue
        regions[r][c] = b
        if not connected(regions, a):
            regions[r][c] = a; continue
        new = count_solutions(regions)
        if new <= cur:
            cur = new
        else:
            regions[r][c] = a
    return None

for attempt in range(200):
    p = list(range(N)); random.shuffle(p)
    if any(abs(p[r]-p[r-1]) <= 1 for r in range(1, N)): continue
    reg = solve_one(p)
    if reg is None: continue
    sizes = [sum(row.count(k) for row in reg) for k in range(N)]
    assert count_solutions(reg, limit=5) == 1
    print("--- attempt", attempt, "sizes", sizes, "sol(row->col)", p)
    for row in reg: print("".join(map(str, row)))
    break
