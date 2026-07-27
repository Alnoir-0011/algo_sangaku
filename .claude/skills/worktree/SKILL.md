---
name: worktree
description: algo_sangaku 専用の worktree 作業場を作成し、現在のセッションをそこに切り替える
when_to_use: back/ または front/ で新しい issue ブランチの作業場を作りたいとき
---

# Algo Sangaku — Worktree セットアップ

## 前提：正しい起動場所

**このスキルは `back/` または `front/` 内から Claude を起動したセッションで呼び出す。**

`EnterWorktree` は「現在の git リポジトリの worktree 一覧にあるパス」しか受け付けない。
親リポジトリ（`algo_sangaku/`）から起動すると、サブモジュールの worktree が一覧に出ないため切り替えができない
（issue #27201、公式に "not planned" としてクローズ済み）。

### 推奨する起動コマンド（tmux 新規ウィンドウで）

```bash
# back で作業する場合
cd /Users/taiki/workspace/runteq/algo_sangaku/back && claude

# front で作業する場合
cd /Users/taiki/workspace/runteq/algo_sangaku/front && claude
```

---

## 手順

### Step 1: 起動場所の確認

```bash
git rev-parse --show-toplevel
```

- `*/back` または `*/front` で終わる → **そのまま続行**
- `*/algo_sangaku` で終わる（親リポジトリ）→ **以下のエラーを表示して停止する**

```
⚠️  このスキルは back/ または front/ 内から起動した Claude セッションで使用してください。

このセッションを終了して、以下のように再起動してください：

  # back で作業する場合
  cd /Users/taiki/workspace/runteq/algo_sangaku/back && claude

  # front で作業する場合
  cd /Users/taiki/workspace/runteq/algo_sangaku/front && claude

再起動後に /worktree を再度実行してください。
```

### Step 2: ユーザーに確認

AskUserQuestion で以下を1回で確認する：

1. **Issue 番号**（数字のみ、例: `105`）
2. **ブランチ名の suffix**（スラッグ形式、例: `add-user-search`）
   → ブランチ名は `feature/issue-<番号>-<suffix>` になる

サブモジュールは Step 1 で特定済みなので聞かない。

### Step 3: Worktree の作成

```bash
# 現在のサブモジュールルートを取得
SUBMODULE_ROOT=$(git rev-parse --show-toplevel)
TARGET=$(basename "$SUBMODULE_ROOT")   # "back" または "front"

ISSUE_NUM="105"
SUFFIX="add-user-search"
BRANCH="feature/issue-${ISSUE_NUM}-${SUFFIX}"
WORKTREE_NAME="issue-${ISSUE_NUM}"
WORKTREE_PATH="${SUBMODULE_ROOT}/.worktrees/${WORKTREE_NAME}"

# .worktrees/ を .gitignore に追加（未追加なら）
grep -q "^\.worktrees" "${SUBMODULE_ROOT}/.gitignore" \
  || echo ".worktrees/" >> "${SUBMODULE_ROOT}/.gitignore"

# worktree を作成
git worktree add ".worktrees/${WORKTREE_NAME}" -b "${BRANCH}"
```

### Step 4: サブモジュール別の追加セットアップ

#### front の場合のみ

node_modules は worktree 間で共有されないため、pnpm install が必須：

```bash
cd "${WORKTREE_PATH}" && pnpm install
```

#### back の場合

追加セットアップは不要。
Docker コマンドは元の `back/` から実行するが、ファイルはコンテナ内の
`/algo_sangaku_back/.worktrees/<name>/` として参照できる：

```bash
# 例: worktree 内で rspec を実行する
docker-compose -f "${SUBMODULE_ROOT}/compose.yaml" exec web \
  bash -c "cd .worktrees/${WORKTREE_NAME} && bundle exec rspec"
```

### Step 5: セッションを worktree に切り替える

```bash
git worktree list  # WORKTREE_PATH がリストに出ることを確認
```

`EnterWorktree(path: "${WORKTREE_PATH}")` を呼んでセッションを worktree に切り替える。

切り替え後、ユーザーに伝える：

```
worktree に切り替えました。

  ブランチ : feature/issue-105-add-user-search
  パス     : /Users/taiki/workspace/runteq/algo_sangaku/back/.worktrees/issue-105

作業を開始してください。
```

---

## worktree の削除（作業完了後）

```bash
# back/ または front/ のルートから
git worktree remove .worktrees/issue-105
git branch -d feature/issue-105-add-user-search
```

---

## worktree の配置場所

| サブモジュール | 配置場所 | 理由 |
|---|---|---|
| `back/` | `back/.worktrees/<name>/` | `compose.yaml` の `- .:/algo_sangaku_back` マウント範囲内に置く必要があるため |
| `front/` | `front/.worktrees/<name>/` | `back/` との統一性のため |

## よくある問題

| 問題 | 原因 | 対処 |
|---|---|---|
| Step 1 で親リポジトリと判定される | `algo_sangaku/` から claude を起動している | `back/` または `front/` 内から再起動する |
| Docker でファイルが見えない | worktree が `back/` 外にある | `back/.worktrees/` 内に配置し直す |
| `pnpm install` を忘れた | front の worktree は node_modules を共有しない | worktree 内で `pnpm install` を実行 |
| worktree 内で main にコミットしてしまった | ブランチ確認を省略した | 作業前に `git branch` で確認する |
