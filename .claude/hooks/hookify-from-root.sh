#!/bin/bash
# hookify 標準の hook は .claude/hookify.*.local.md を cwd 相対で探すため、
# worktree やサブモジュール配下では untracked のルールが見つからず無効になる。
# そのため親リポ(CLAUDE_PROJECT_DIR)へ cd して pretooluse.py を呼び直す。

warn() {
  printf '{"systemMessage": "hookify-from-root: %s"}\n' "$1"
  exit 0
}

INPUT=$(cat)

# cwd にルールがあるときは標準の hook が処理済みで、ここでも評価すると同じメッセージが二重に出る。
compgen -G '.claude/hookify.*.local.md' >/dev/null && exit 0

ROOT="${CLAUDE_PROJECT_DIR:-}"
[ -d "$ROOT/.claude" ] || warn "CLAUDE_PROJECT_DIR を解決できないためルールを適用できません"

# バージョンのハッシュ値をパスに埋め込むと、プラグイン更新で壊れるため最新のディレクトリを探す。
PLUGIN=$(ls -dt "$HOME"/.claude/plugins/cache/*/hookify/*/ 2>/dev/null | head -1)
PLUGIN="${PLUGIN%/}"
[ -f "$PLUGIN/hooks/pretooluse.py" ] || warn "hookify プラグインが見つからないためルールを適用できません"

cd "$ROOT" || warn "親リポへ移動できないためルールを適用できません"
printf '%s' "$INPUT" | CLAUDE_PLUGIN_ROOT="$PLUGIN" python3 "$PLUGIN/hooks/pretooluse.py"
