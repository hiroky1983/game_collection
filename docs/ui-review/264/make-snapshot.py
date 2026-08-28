import json,sys
def m(n): return {"characters":{"_0":n}}
def p(n): return {"circles":{"_0":n}}
def s(n): return {"bamboos":{"_0":n}}
def w(n): return {"wind":{"_0":n}}
def d(n): return {"dragon":{"_0":n}}
allt=[m(i) for i in range(1,10)]+[p(i) for i in range(1,10)]+[s(i) for i in range(1,10)]+[w(i) for i in range(4)]+[d(i) for i in range(3)]
def counts(idxs):
    c=[0]*34
    for i in idxs: c[i]+=1
    return {"counts":c}
nmeld=int(sys.argv[1]); riichi=sys.argv[2]=="1"
def river(seed): return [allt[(seed*7+i*3)%34] for i in range(20)]
def melds_for(seed,n):
    ks=[(seed*5+j*6)%34 for j in range(n)]
    return [{"kind":"closedKan","tile":allt[k],"from":None,"claimedTile":None} for k in ks]
hands=[]
for pl in range(4):
    ks=[(pl*5+j*6)%34 for j in range(nmeld)]
    rest=[i for i in range(34) if i not in ks]
    hands.append(counts(rest[:13-3*nmeld]))
# 人間(0)は非立直にして手番で止め、状態を固定する（立直中は自摸切りで進んでしまうため）
print(json.dumps({
 "wall":allt[:20],"wallIndex":0,"deadWall":allt[:14],"hands":hands,"drawnTile":m(5),
 "discards":[river(i) for i in range(4)],
 "riichi":[False,riichi,riichi,riichi],"riichiFuriten":[False]*4,
 "scores":[-1200,132800,24000,17200],"dealer":0,"roundNumber":4,"honba":3,"riichiSticks":4,
 "currentPlayer":0,"turnCount":18,"melds":[melds_for(i,nmeld) for i in range(4)],
 "discardedKinds":[[(i*7+j*3)%34 for j in range(20)] for i in range(4)],
 "revealedDoraCount":5,"deadWallDraws":nmeld}))
