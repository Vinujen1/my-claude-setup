# my-claude-setup

My Claude Code configuration — global instructions, skills, agents, and plugins — kept in one repo so every computer gets the same setup.

## What's here

| Path | What it is | How it's installed |
|---|---|---|
| `CLAUDE.md` | Global engineering standards | Copied to `~/.claude/CLAUDE.md` |
| `skills/` | Skills (`/ai-ml-engineer`, `/web-3d-motion`, …) | Linked into `~/.claude/skills/` |
| `agents/` | Read-only review subagents | Copied to `~/.claude/agents/` |
| `plugins.json` | Plugins and extra marketplaces | Merged into `~/.claude/settings.json`, then installed |
| `setup.ps1` / `setup.sh` | Apply the setup (Windows / macOS, Linux, Jetson) | — |
| `update.ps1` / `update.sh` | `git pull --ff-only`, then re-apply | — |

Skills are linked (directory junctions on Windows, symlinks elsewhere), so a pull updates them instantly. Skills you installed some other way are left alone. Your other `settings.json` keys (`env`, `model`, permissions, …) are never overwritten, and anything replaced is backed up to `~/.claude/backups/`.

## New computer

**Windows (PowerShell)**

```powershell
git clone https://github.com/Vinujen1/my-claude-setup.git $HOME\my-claude-setup
powershell -ExecutionPolicy Bypass -File $HOME\my-claude-setup\setup.ps1
```

**macOS / Linux / Jetson**

```bash
git clone https://github.com/Vinujen1/my-claude-setup.git ~/my-claude-setup
~/my-claude-setup/setup.sh
```

Restart Claude Code afterwards.

## Update an existing computer

```powershell
powershell -ExecutionPolicy Bypass -File $HOME\my-claude-setup\update.ps1   # Windows
```

```bash
~/my-claude-setup/update.sh                                                 # macOS / Linux
```

Then restart Claude Code. Inside Claude Code, `/plugin marketplace update` refreshes third-party plugins to their latest versions.

## Add something

- **Skill:** add `skills/<name>/SKILL.md`, commit, push, run `update` on other machines.
- **Plugin from the official marketplace:** add `"<plugin>@claude-plugins-official": true` to `enabledPlugins` in `plugins.json`.
- **Plugin from a GitHub marketplace:** add the marketplace under `extraKnownMarketplaces` (key = the `name` in its `.claude-plugin/marketplace.json`) and the plugin as `"<plugin>@<marketplace>": true`.

## Kept out of this repo on purpose

- API keys and tokens (keep them in environment variables; `.gitignore` blocks common secret file names).
- `~/.claude.json` (login and session state) and `settings.local.json`.
- Per-machine settings such as `ANTHROPIC_BASE_URL` for a local gateway — set those in that machine's `~/.claude/settings.json` `env` block; setup leaves them untouched.
- MCP servers that need per-machine auth — add them with `claude mcp add --scope user …` on each machine.
