#!/usr/bin/env python3
"""
将棋評価関数 NN の学習 + CoreML 変換スクリプト。

事前準備:
  pip install -r Scripts/requirements.txt

訓練データ生成:
  swift run --package-path Packages/GameKit ShogiDataGen 80000 shogi_train.csv

実行:
  python Scripts/train_eval.py shogi_train.csv
"""
import sys
import os
import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset
import coremltools as ct

CSV_PATH = sys.argv[1] if len(sys.argv) > 1 else "shogi_train.csv"
OUT_PATH = "Packages/GameKit/Sources/GameShogi/Resources/ShogiEvalNet.mlpackage"

INPUT_SIZE = 95   # PositionFeatures.size と一致させること

# ============================================================
# モデル定義
# ============================================================

class ShogiEvalNet(nn.Module):
    def __init__(self):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(INPUT_SIZE, 128),
            nn.ReLU(),
            nn.Linear(128, 32),
            nn.ReLU(),
            nn.Linear(32, 1),
        )

    def forward(self, x):
        return self.net(x).squeeze(-1)

# ============================================================
# 学習
# ============================================================

def load_data(path: str):
    print(f"Loading {path} ...")
    import pandas as pd
    df = pd.read_csv(path)
    X = df.iloc[:, :-1].values.astype(np.float32)
    y = df.iloc[:, -1].values.astype(np.float32)
    print(f"  {len(X)} samples, input dim={X.shape[1]}")
    return X, y

def train(X, y, epochs=30, batch_size=2048, lr=1e-3):
    model = ShogiEvalNet()
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    criterion = nn.MSELoss()

    X_t = torch.tensor(X)
    y_t = torch.tensor(y)
    ds = TensorDataset(X_t, y_t)
    loader = DataLoader(ds, batch_size=batch_size, shuffle=True)

    for epoch in range(1, epochs + 1):
        model.train()
        total = 0.0
        for xb, yb in loader:
            pred = model(xb)
            loss = criterion(pred, yb)
            opt.zero_grad()
            loss.backward()
            opt.step()
            total += loss.item()
        if epoch % 5 == 0 or epoch == 1:
            print(f"  Epoch {epoch:3d}/{epochs}  loss={total/len(loader):.5f}")

    return model

# ============================================================
# CoreML 変換
# ============================================================

def export(model: nn.Module, out_path: str):
    model.eval()
    trace_input = torch.zeros(1, INPUT_SIZE)
    traced = torch.jit.trace(model, trace_input)

    ml = ct.convert(
        traced,
        inputs=[ct.TensorType(name="features", shape=(1, INPUT_SIZE), dtype=np.float32)],
        outputs=[ct.TensorType(name="score", dtype=np.float32)],
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.CPU_AND_NE,  # Neural Engine 対応
    )

    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    ml.save(out_path)
    print(f"Saved: {out_path}")
    size_mb = sum(
        os.path.getsize(os.path.join(dp, f))
        for dp, _, files in os.walk(out_path)
        for f in files
    ) / 1024 / 1024
    print(f"Model size: {size_mb:.2f} MB")

# ============================================================
# main
# ============================================================

if __name__ == "__main__":
    X, y = load_data(CSV_PATH)

    print("Training...")
    model = train(X, y)

    print("Exporting to CoreML...")
    export(model, OUT_PATH)
    print("Done.")
    print()
    print("次のステップ:")
    print("  1. Xcode で Packages/GameKit/Sources/GameShogi/Resources/ に")
    print("     ShogiEvalNet.mlpackage が追加されていることを確認")
    print("  2. ビルドして動作確認")
