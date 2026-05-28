#!/bin/bash
# PostToolUse hook: Write|Edit のたびに対象ファイルを lint する
# - front/ の .ts/.tsx/.js/.jsx → pnpm exec next lint <file>
# - back/ の .rb               → docker-compose exec -T web bundle exec rubocop <file>

FILE=$(jq -r '.tool_input.file_path // empty')
[ -z "$FILE" ] && exit 0

FRONT=/Users/taiki/workspace/runteq/algo_sangaku/front
BACK=/Users/taiki/workspace/runteq/algo_sangaku/back

if echo "$FILE" | grep -q "^$FRONT/" && echo "$FILE" | grep -qE '\.(ts|tsx|js|jsx)$'; then
  REL=$(echo "$FILE" | sed "s|$FRONT/||")
  cd "$FRONT" && pnpm exec next lint "$REL" || true

elif echo "$FILE" | grep -q "^$BACK/" && echo "$FILE" | grep -q '\.rb$'; then
  cd "$BACK" && docker-compose exec -T web bundle exec rubocop "$FILE" || true
fi
