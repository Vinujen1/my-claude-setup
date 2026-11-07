#!/usr/bin/env bash
# Installs this repo's Claude Code setup into ~/.claude (macOS / Linux / Jetson). Safe to re-run.
#   - symlinks each skill in ./skills into ~/.claude/skills (other skills are left alone)
#   - copies ./agents/*.md and CLAUDE.md into ~/.claude
#   - merges plugins.json into ~/.claude/settings.json without touching other settings
#   - installs the listed plugins with the claude CLI when available
# Replaced files are backed up to ~/.claude/backups/setup-<timestamp>/.
# Usage: ./setup.sh [--skip-plugins]
set -euo pipefail

SKIP_PLUGINS=0
[[ "${1:-}" == "--skip-plugins" ]] && SKIP_PLUGINS=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
BACKUP_DIR="$CLAUDE_DIR/backups/setup-$(date +%Y%m%d-%H%M%S)"
CHANGES=0

step() { printf '  %-8s %s\n' "$1" "$2"; }
backup() { [[ -e "$1" || -L "$1" ]] || return 0; mkdir -p "$BACKUP_DIR"; cp -RL "$1" "$BACKUP_DIR/" 2>/dev/null || cp -R "$1" "$BACKUP_DIR/"; }

echo "Claude Code setup: $REPO -> $CLAUDE_DIR"
mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/agents"

echo "Skills"
for src in "$REPO"/skills/*/; do
  src="${src%/}"; name="$(basename "$src")"; link="$CLAUDE_DIR/skills/$name"
  if [[ -L "$link" && "$(readlink "$link")" == "$src" ]]; then step ok "$name"; continue; fi
  if [[ -L "$link" ]]; then rm "$link"; elif [[ -e "$link" ]]; then backup "$link"; rm -rf "$link"; fi
  ln -s "$src" "$link"; step linked "$name"; CHANGES=$((CHANGES + 1))
done

echo "Agents and CLAUDE.md"
copy_if_changed() {
  if [[ -f "$2" ]] && cmp -s "$1" "$2"; then return 1; fi
  backup "$2"; cp "$1" "$2"
}
for agent in "$REPO"/agents/*.md; do
  if copy_if_changed "$agent" "$CLAUDE_DIR/agents/$(basename "$agent")"; then
    step updated "agents/$(basename "$agent")"; CHANGES=$((CHANGES + 1))
  fi
done
if copy_if_changed "$REPO/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"; then step updated CLAUDE.md; CHANGES=$((CHANGES + 1)); fi

echo "Plugins"
PY="$(command -v python3 || command -v python || true)"
[[ -n "$PY" ]] || { echo "python3 is required to merge settings.json" >&2; exit 1; }
SETTINGS="$CLAUDE_DIR/settings.json"
[[ -f "$SETTINGS" ]] && cp "$SETTINGS" "$SETTINGS.setup-tmp"
merge_status="$("$PY" - "$REPO/plugins.json" "$SETTINGS" <<'PYEOF'
import json, sys, pathlib
wanted = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
path = pathlib.Path(sys.argv[2])
raw = path.read_text(encoding="utf-8-sig") if path.exists() else ""
try:
    settings = json.loads(raw) if raw.strip() else {}
except json.JSONDecodeError as e:
    sys.exit(f"Could not parse {path}: {e}")
before = json.dumps(settings, sort_keys=True)
for section in ("extraKnownMarketplaces", "enabledPlugins"):
    if section in wanted:
        settings.setdefault(section, {}).update(wanted[section])
if json.dumps(settings, sort_keys=True) == before:
    print("unchanged")
else:
    path.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")
    print("merged")
PYEOF
)"
if [[ "$merge_status" == "merged" ]]; then
  [[ -f "$SETTINGS.setup-tmp" ]] && { mkdir -p "$BACKUP_DIR"; mv "$SETTINGS.setup-tmp" "$BACKUP_DIR/settings.json"; }
  step merged "plugins.json -> settings.json"; CHANGES=$((CHANGES + 1))
else
  rm -f "$SETTINGS.setup-tmp"; step ok "settings.json already lists every plugin"
fi

if [[ $SKIP_PLUGINS == 1 ]]; then
  step skipped "plugin install (--skip-plugins); Claude Code installs enabled plugins at next start"
elif ! command -v claude >/dev/null 2>&1; then
  step skipped "plugin install (claude CLI not on PATH); Claude Code installs enabled plugins at next start"
else
  while read -r loc; do
    [[ -n "$loc" ]] && claude plugin marketplace add "$loc" >/dev/null 2>&1 || true
  done < <("$PY" -c 'import json,sys; m=json.load(open(sys.argv[1])).get("extraKnownMarketplaces",{})
for v in m.values():
    s=v.get("source",{}); print(s.get("repo") if s.get("source")=="github" else s.get("url",""))' "$REPO/plugins.json")
  while read -r plugin; do
    if out="$(claude plugin install "$plugin" 2>&1)"; then step ok "$plugin"
    else echo "  warning: could not install $plugin: $out" >&2; fi
  done < <("$PY" -c 'import json,sys; [print(k) for k,v in json.load(open(sys.argv[1]))["enabledPlugins"].items() if v is True]' "$REPO/plugins.json")
fi

echo
if [[ $CHANGES == 0 ]]; then echo "Already up to date."; else echo "Done: $CHANGES change(s). Restart Claude Code to load them."; fi
[[ -d "$BACKUP_DIR" ]] && echo "Backups: $BACKUP_DIR"
exit 0
