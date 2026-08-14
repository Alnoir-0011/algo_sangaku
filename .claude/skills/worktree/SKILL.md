---
name: worktree
description: algo_sangaku 専用の worktree 作業場を作成し、現在のセッションをそこに切り替える
when_to_use: back/ または front/ で新しい issue ブランチの作業場を作りたいとき
---

# Algo Sangaku — Worktree セットアップ

## 前提：親リポジトリから起動したセッションで使う

**このスキルは親リポジトリ（`algo_sangaku/`）から起動した Claude セッションで呼び出す。**

スキル定義が親リポの `.claude/skills/` にあるため、`back/`・`front/` から起動したセッションには
読み込まれず、`/worktree` 自体が存在しない。

`EnterWorktree` は submodule（nested repository）に登録された worktree パスも受け付けるため、
親リポセッションのまま back/front の worktree に切り替えられる。
親リポの `git worktree list` に submodule の worktree が出ないことは正常で、それでも受理される。

### 制約

すでに別の worktree に入っているセッションからは使えない。
`EnterWorktree` が nested repository のパスを受理するのは、起動ディレクトリからの**初回入場時のみ**。
その場合はセッションを開き直してから実行する。

---

## 手順

### Step 1: ユーザーに確認

AskUserQuestion で以下を1回で確認する：

1. **対象サブモジュール**（`back` / `front`）
2. **Issue 番号**（数字のみ、例: `105`）
3. **ブランチ名の suffix**（スラッグ形式、例: `add-user-search`）
   → ブランチ名は `feature/issue-<番号>-<suffix>` になる

### Step 2: Worktree の作成

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)   # 親リポ algo_sangaku/
TARGET="back"                                # Step 1 で選ばれた back または front
SUBMODULE_ROOT="${REPO_ROOT}/${TARGET}"

ISSUE_NUM="105"
SUFFIX="add-user-search"
BRANCH="feature/issue-${ISSUE_NUM}-${SUFFIX}"
WORKTREE_NAME="issue-${ISSUE_NUM}"
WORKTREE_PATH="${SUBMODULE_ROOT}/.worktrees/${WORKTREE_NAME}"

# .worktrees/ を .gitignore に追加（未追加なら）
grep -q "^\.worktrees" "${SUBMODULE_ROOT}/.gitignore" \
  || echo ".worktrees/" >> "${SUBMODULE_ROOT}/.gitignore"

# worktree を作成する。git worktree add は必ずサブモジュール内で実行する
# （親リポで実行すると親リポの worktree になってしまう）
cd "${SUBMODULE_ROOT}" && git worktree add ".worktrees/${WORKTREE_NAME}" -b "${BRANCH}"
```

### Step 3: サブモジュール別の追加セットアップ

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

### Step 4: セッションを worktree に切り替える

```bash
# 確認はサブモジュール内で行う（親リポの一覧には出ない）
cd "${SUBMODULE_ROOT}" && git worktree list
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
| `/worktree` が一覧に出ない | `back/` または `front/` から claude を起動している（スキル定義は親リポにある） | 親リポ `algo_sangaku/` から起動し直す |
| `EnterWorktree` がパスを拒否する | すでに別の worktree に入っているセッションから呼んでいる | セッションを開き直してから実行する |
| 親リポの `git worktree list` に出ない | submodule の worktree は親リポの一覧には出ない（正常な挙動） | 確認は `back/`・`front/` 内で行う |
| Docker でファイルが見えない | worktree が `back/` 外にある | `back/.worktrees/` 内に配置し直す |
| `pnpm install` を忘れた | front の worktree は node_modules を共有しない | worktree 内で `pnpm install` を実行 |
| worktree 内で main にコミットしてしまった | ブランチ確認を省略した | 作業前に `git branch` で確認する |
