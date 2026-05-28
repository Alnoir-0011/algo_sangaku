#!/bin/bash
# PreToolUse hook: git commit 前にステージ済み .rb ファイルへ rubocop -a を実行する

CMD=$(jq -r '.tool_input.command // empty')
echo "$CMD" | grep -q 'git commit' || exit 0

BACK=/Users/taiki/workspace/runteq/algo_sangaku/back

STAGED_RB=$(git -C "$BACK" diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep '\.rb$')
[ -z "$STAGED_RB" ] && exit 0

echo "Running rubocop -a on staged Ruby files..."
echo "$STAGED_RB" | tr '\n' '\0' | xargs -0 docker-compose -f "$BACK/compose.yaml" exec -T web bundle exec rubocop -a 2>/dev/null || true

# auto-correct されたファイルを再ステージ
while IFS= read -r f; do
  git -C "$BACK" add "$f"
done <<< "$STAGED_RB"
