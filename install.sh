#!/bin/sh
# Install awb and its agent skill (Claude Code: ~/.claude/skills/awb-workbench).
# From a clone: symlinks, so edits take effect. Otherwise: latest GitHub release.
#   curl -fsSL https://raw.githubusercontent.com/cklxx/awb/main/install.sh | sh
set -eu
bin=${AWB_BIN_DIR:-$HOME/.local/bin}
skill=${AWB_SKILL_DIR:-$HOME/.claude/skills}/awb-workbench
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$bin" "$skill"
if [ -f "$here/awb" ] && [ -f "$here/skills/awb-workbench/SKILL.md" ]; then
  ln -sf "$here/awb" "$bin/awb"
  ln -sf "$here/awb-lark" "$bin/awb-lark"
  ln -sf "$here/skills/awb-workbench/SKILL.md" "$skill/SKILL.md"
else
  url=https://github.com/cklxx/awb/releases/latest/download
  stage=$(mktemp -d "$bin/.awb-install.XXXXXX")
  skill_tmp=
  trap 'rm -rf "$stage"; [ -z "$skill_tmp" ] || rm -f "$skill_tmp"' EXIT
  trap 'exit 130' INT TERM
  for f in awb awb-lark; do
    curl -fsSL "$url/$f" -o "$stage/$f"
    chmod +x "$stage/$f"
  done
  skill_tmp=$(mktemp "$skill/.SKILL.md.XXXXXX")
  curl -fsSL "$url/SKILL.md" -o "$skill_tmp"
  # A failed download must leave the existing installation intact. Each replacement
  # is renamed from its destination filesystem after all downloads have succeeded.
  for f in awb awb-lark; do mv "$stage/$f" "$bin/$f"; done
  mv "$skill_tmp" "$skill/SKILL.md"; skill_tmp=
fi
# optional: the compiled Lean model enables the board's audit and the differential selftest
if [ -f "$here/model/lakefile.toml" ]; then
  lake=$(command -v lake || echo "$HOME/.elan/bin/lake")
  if [ -x "$lake" ]; then (cd "$here/model" && "$lake" build -q) && echo "built Lean model: board audit enabled"
  else echo "no Lean (elan): board audit disabled"; fi
fi
# optional: with lark-cli (bot identity), each board mirrors into its own topic of one
# Lark topic group. AWB_LARK_CHAT=oc_xxx sets it; otherwise ask when a terminal is attached.
if command -v lark-cli >/dev/null; then
  chat=${AWB_LARK_CHAT:-}
  if [ -z "$chat" ] && [ -r /dev/tty ] && (: < /dev/tty) 2>/dev/null; then
    printf 'lark-cli found. Lark topic group for board progress (oc_..., empty to skip): ' > /dev/tty
    read -r chat < /dev/tty || chat=
  fi
  [ -z "$chat" ] || "$bin/awb-lark" setup "$chat" || echo "lark: setup failed; rerun: awb-lark setup $chat"
fi
for c in tmux jq; do command -v "$c" >/dev/null || echo "missing: $c (required)"; done
command -v flock >/dev/null || command -v lockf >/dev/null || echo "missing: flock or lockf (required for locking)"
case ":$PATH:" in *":$bin:"*) ;; *) echo "add to PATH: $bin" ;; esac
echo "installed $("$bin/awb" version) -> $bin/awb"
echo "skill -> $skill (Claude Code); other agents: run 'awb skill'"
