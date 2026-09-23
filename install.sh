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
  ln -sf "$here/skills/awb-workbench/SKILL.md" "$skill/SKILL.md"
else
  url=https://github.com/cklxx/awb/releases/latest/download
  curl -fsSL "$url/awb" -o "$bin/awb.tmp" && chmod +x "$bin/awb.tmp" && mv "$bin/awb.tmp" "$bin/awb"
  rm -f "$skill/SKILL.md"; curl -fsSL "$url/SKILL.md" -o "$skill/SKILL.md"
fi
for c in tmux jq; do command -v "$c" >/dev/null || echo "missing: $c (required)"; done
case ":$PATH:" in *":$bin:"*) ;; *) echo "add to PATH: $bin" ;; esac
echo "installed $("$bin/awb" version) -> $bin/awb"
echo "skill -> $skill (Claude Code); other agents: run 'awb skill'"
