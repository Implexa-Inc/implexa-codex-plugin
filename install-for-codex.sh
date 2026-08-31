#!/usr/bin/env bash
#
# Implexa Codex plugin installer
# ──────────────────────────────────────────────────────────────────────────
# Run with:
#   curl -fsSL https://core.implexa.ai/install-for-codex.sh | bash
#
# What it does (one-time setup, idempotent — safe to re-run):
#   1. Checks that codex CLI is installed (or warns you to install it)
#   2. Installs a secret-free local MCP shim + config (idempotent)
#   3. Scrubs legacy Implexa MCP credentials from Implexa-owned config/cache
#   4. Prints verification steps: Codex → $implexa-help
#
# After this script: open Implexa Desktop, sign in, then start a new Codex
# session and type $implexa-help.

set -e

# Add Homebrew to PATH if not already present (common on fresh Macs).
if ! command -v brew >/dev/null 2>&1; then
  if [ -x /opt/homebrew/bin/brew ]; then PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"; export PATH; fi
  if [ -x /usr/local/bin/brew ];   then PATH="/usr/local/bin:/usr/local/sbin:$PATH"; export PATH; fi
fi

CODEX_DIR="$HOME/.codex"
CONFIG_TOML="$CODEX_DIR/config.toml"
IMPLEXA_DIR="$HOME/.implexa"
MCP_SHIM="$IMPLEXA_DIR/bin/implexa-codex-mcp"

# Color helpers
if [ -t 1 ]; then
  C_GREEN=$'\033[0;32m'; C_RED=$'\033[0;31m'; C_YELLOW=$'\033[0;33m'
  C_BLUE=$'\033[0;34m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_GREEN=''; C_RED=''; C_YELLOW=''; C_BLUE=''; C_BOLD=''; C_RESET=''
fi

ok()   { printf "%s✓%s %s\n" "$C_GREEN"  "$C_RESET" "$*"; }
warn() { printf "%s⚠%s %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf "%s✗%s %s\n" "$C_RED"    "$C_RESET" "$*" >&2; }
info() { printf "%s→%s %s\n" "$C_BLUE"   "$C_RESET" "$*"; }

echo ""
echo "${C_BOLD}Implexa Codex plugin installer${C_RESET}"
echo ""

# Account credentials belong exclusively to the Implexa Desktop app. Refuse
# legacy secret-bearing installer flags without ever echoing their values.
for arg in "$@"; do
  case "$arg" in
    --api-key|--api-key=*) err "API-key installer flags are no longer accepted. Sign in through Implexa Desktop."; exit 2 ;;
  esac
done
unset IMPLEXA_API_KEY IMPLEXA_INSTALL_TOKEN

# ─── 1. Check codex CLI ──────────────────────────────────────────────────
if ! command -v codex >/dev/null 2>&1; then
  warn "codex CLI not found. install it first:"
  echo "    npm install -g @openai/codex"
  echo "    — or — https://github.com/openai/codex"
  echo ""
  echo "Re-run this script after installing codex."
  # Non-fatal: user may be running from a context where codex isn't on PATH yet.
  # We still write the config so it's ready when they install codex.
  warn "Continuing anyway — config will be ready when codex is installed."
else
  ok "codex CLI found at $(command -v codex)"
fi

# ─── 2. Check jq (needed for JSON parsing) ──────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  warn "jq is required but not installed."
  if command -v brew >/dev/null 2>&1; then
    info "Installing jq via Homebrew..."
    brew install jq </dev/null
    ok "jq installed"
  else
    err "jq not found and Homebrew not available. Install jq manually and re-run."
    echo "    macOS:  brew install jq"
    echo "    Linux:  apt-get install jq  (or your distro's package manager)"
    exit 1
  fi
else
  ok "jq found at $(command -v jq)"
fi

# ─── 3. Authentication custody ───────────────────────────────────────────
# Codex receives only a local, revocable capability. Implexa Desktop holds and
# injects the account credential after binding each connection to the active account.
# The helper therefore fails closed while Desktop is absent or signed out.

# ─── 4. Ensure ~/.codex dir exists ──────────────────────────────────────
if [ ! -d "$CODEX_DIR" ]; then
  mkdir -p "$CODEX_DIR"
  ok "Created Codex config directory at $CODEX_DIR"
else
  ok "Codex config directory found at $CODEX_DIR"
fi
[ ! -L "$CONFIG_TOML" ] || { err "Refusing to replace a symlinked Codex config"; exit 1; }

# ─── 5. Install secret-free MCP shim + config (idempotent) ──────────────
#
# Finder-launched Codex has no safe shell environment for an account bearer
# token. The Implexa Desktop app owns that credential and exposes a revocable,
# per-app-life Unix-socket capability. Codex receives only this fixed shim path.
# No account key is written to config, plugin cache, argv, env or logs.

mkdir -p "$IMPLEXA_DIR/bin"
chmod 700 "$IMPLEXA_DIR" "$IMPLEXA_DIR/bin" 2>/dev/null || true
MCP_SHIM_TMP="$MCP_SHIM.tmp.$$"
cat > "$MCP_SHIM_TMP" <<'IMPLEXA_CODEX_MCP_SHIM'
#!/bin/sh
# Secret-free Codex MCP transport.  The Implexa Desktop app owns the account
# credential and publishes only a short-lived Unix-socket capability.  This
# shim carries JSON-RPC bytes; it never reads, receives or expands an API key.
# Unix ownership cannot distinguish Codex from another process running under
# the same macOS uid. That explicit residual is constrained by Desktop's method
# allowlist, fixed upstream origin, account generation and app lifetime.
set -eu

LOCATOR="$HOME/.implexa/codex-mcp.current"
UID_NOW="$(/usr/bin/id -u)"

refuse() {
  echo "Implexa MCP is unavailable. Open Implexa, sign in, then retry." >&2
  exit 1
}

[ -f "$LOCATOR" ] || refuse

# The locator is capability material.  Refuse symlinks, foreign ownership and
# loose modes before reading it. BSD stat is the production path; GNU stat keeps
# the same script testable on non-macOS CI.
[ ! -L "$LOCATOR" ] || refuse
if STAT_LINE="$(/usr/bin/stat -f '%u %Lp' "$LOCATOR" 2>/dev/null)"; then
  :
elif STAT_LINE="$(/usr/bin/stat -c '%u %a' "$LOCATOR" 2>/dev/null)"; then
  :
else
  refuse
fi
[ "$STAT_LINE" = "$UID_NOW 600" ] || refuse

SOCKET="$(/bin/cat "$LOCATOR")" || refuse
[ -n "$SOCKET" ] || refuse
# Exactly one line, and only a capability path minted by Desktop for this uid.
[ "$(/usr/bin/wc -l < "$LOCATOR" | /usr/bin/tr -d ' ')" = "0" ] || refuse
printf '%s' "$SOCKET" | /usr/bin/grep -Eq "^/tmp/implexa-${UID_NOW}/codex-mcp/broker-[a-f0-9]{48}\\.sock$" || refuse
[ -S "$SOCKET" ] || refuse

exec /usr/bin/nc -U "$SOCKET"
IMPLEXA_CODEX_MCP_SHIM
chmod 700 "$MCP_SHIM_TMP"
mv "$MCP_SHIM_TMP" "$MCP_SHIM"
ok "Installed secret-free Codex MCP shim"

MCP_COMMAND_TOML=$(jq -Rn --arg value "$MCP_SHIM" '$value')
MCP_BLOCK="[mcp_servers.implexa]
command = $MCP_COMMAND_TOML"

strip_implexa_block() {
  local input="$1"
  local output="$2"
  awk '
    /^\[mcp_servers\.implexa\]/ { skip=1; next }
    /^\[/ && skip { skip=0 }
    !skip { print }
  ' "$input" > "$output"
}

contains_installed_account_secret() {
  # Match only credential-bearing forms from legacy Implexa installers. Never
  # print a matching line: it may itself contain the retired account key.
  LC_ALL=C grep -Eiq "api_key[[:space:]]*=[[:space:]]*['\"]?imp_|api_key=imp_|bearer_token[[:space:]]*=[[:space:]]*['\"]?imp_|authorization[^[:cntrl:]]*(bearer[[:space:]]+)?imp_|x-api-key[^[:cntrl:]]*imp_" "$1"
}

prove_secret_free() {
  local candidate="$1"
  [ -e "$candidate" ] || return 0
  [ -f "$candidate" ] && [ ! -L "$candidate" ] || {
    err "Cannot prove an Implexa-owned Codex config is secret-free; refusing to continue."
    exit 1
  }
  if contains_installed_account_secret "$candidate"; then
    err "A legacy Implexa credential remains in Codex configuration; refusing to continue."
    exit 1
  fi
}

if [ ! -f "$CONFIG_TOML" ]; then
  # Fresh file — just write the block.
  printf '%s\n' "$MCP_BLOCK" > "$CONFIG_TOML"
  ok "Created $CONFIG_TOML with Implexa MCP server config"
else
  # File exists. If a [mcp_servers.implexa] section is present (any
  # format), strip it cleanly and append a fresh canonical block. This
  # handles both the legacy `bearer_token` format and the canonical
  # `headers` format equally well.
  if grep -q '^\[mcp_servers\.implexa\]' "$CONFIG_TOML" 2>/dev/null; then
    BACKUP="$CONFIG_TOML.implexa-backup-$(date +%s)-$$"

    # The backup is deliberately sanitized too. A byte-for-byte backup would
    # preserve the very query/header credential this migration removes.
    strip_implexa_block "$CONFIG_TOML" "$BACKUP"
    chmod 600 "$BACKUP" 2>/dev/null || true
    strip_implexa_block "$CONFIG_TOML" "$CONFIG_TOML.tmp.$$"

    # Append fresh canonical block.
    printf '\n%s\n' "$MCP_BLOCK" >> "$CONFIG_TOML.tmp.$$"
    mv "$CONFIG_TOML.tmp.$$" "$CONFIG_TOML"
    ok "Migrated [mcp_servers.implexa] to the local Desktop broker (sanitized backup: $BACKUP)"
  else
    # No existing block — append it.
    echo "" >> "$CONFIG_TOML"
    printf '%s\n' "$MCP_BLOCK" >> "$CONFIG_TOML"
    ok "Appended [mcp_servers.implexa] block to $CONFIG_TOML"
  fi
fi
chmod 600 "$CONFIG_TOML" 2>/dev/null || true

# Scrub every older installer backup we own. Remove only the Implexa MCP block;
# all unrelated Codex settings and MCP servers survive byte-for-byte through awk.
for LEGACY_BACKUP in "$CODEX_DIR"/config.toml.implexa-backup-*; do
  [ -e "$LEGACY_BACKUP" ] || continue
  [ -f "$LEGACY_BACKUP" ] && [ ! -L "$LEGACY_BACKUP" ] || {
    err "An Implexa-owned Codex backup is not a safe regular file; refusing to continue."
    exit 1
  }
  LEGACY_TMP="$LEGACY_BACKUP.tmp.$$"
  strip_implexa_block "$LEGACY_BACKUP" "$LEGACY_TMP"
  mv "$LEGACY_TMP" "$LEGACY_BACKUP"
  chmod 600 "$LEGACY_BACKUP" 2>/dev/null || true
done
# Interrupted legacy installs can leave a secret-bearing temporary config even
# when config.toml itself was migrated. These names are owned by this installer;
# scrub only the Implexa block and preserve every unrelated section.
for LEGACY_CONFIG_TMP in "$CODEX_DIR"/config.toml.tmp.*; do
  [ -e "$LEGACY_CONFIG_TMP" ] || continue
  [ -f "$LEGACY_CONFIG_TMP" ] && [ ! -L "$LEGACY_CONFIG_TMP" ] || {
    err "An Implexa-owned Codex temporary config is not a safe regular file; refusing to continue."
    exit 1
  }
  SCRUBBED_CONFIG_TMP="$LEGACY_CONFIG_TMP.scrubbed.$$"
  strip_implexa_block "$LEGACY_CONFIG_TMP" "$SCRUBBED_CONFIG_TMP"
  mv "$SCRUBBED_CONFIG_TMP" "$LEGACY_CONFIG_TMP"
  chmod 600 "$LEGACY_CONFIG_TMP" 2>/dev/null || true
done
prove_secret_free "$CONFIG_TOML"
for LEGACY_BACKUP in "$CODEX_DIR"/config.toml.implexa-backup-*; do
  [ -e "$LEGACY_BACKUP" ] || continue
  prove_secret_free "$LEGACY_BACKUP"
done
for LEGACY_CONFIG_TMP in "$CODEX_DIR"/config.toml.tmp.*; do
  [ -e "$LEGACY_CONFIG_TMP" ] || continue
  prove_secret_free "$LEGACY_CONFIG_TMP"
done

# ─── 6. Install plugin skills into Codex's plugin cache ──────────────────
#
# Codex's MCP config (the block we wrote above) only exposes the MCP
# *tools* to the model. It does NOT install the SKILL.md files that
# define the $implexa-* slash commands. Those have to live at codex's
# canonical plugin cache path:
#
#   ~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/skills/
#
# Mimics what `codex plugin install` does internally — clone the repo
# into a marketplace dir and copy to the versioned cache. The .mcp.json is
# permanently secret-free: it invokes the same local Desktop broker shim.
# Failure here is
# NON-FATAL: the MCP tools still work, the user just won't see
# $implexa-* slash commands. We log a clear warning + a manual command
# they can run.
#
# Note: codex reads these paths on launch. Restart codex (close all
# sessions, reopen) to pick up newly-installed plugins.

MARKETPLACE_DIR="$CODEX_DIR/marketplaces/implexa"
PLUGIN_REPO_URL="${IMPLEXA_PLUGIN_REPO_URL:-https://github.com/Implexa-Inc/implexa-codex-plugin.git}"
PLUGIN_CACHE_BASE="$CODEX_DIR/plugins/cache/implexa/implexa"

write_secret_free_mcp_json() {
  local output="$1"
  jq -n --arg command "$MCP_SHIM" '{implexa: {command: $command}}' > "$output"
  chmod 600 "$output" 2>/dev/null || true
}

# Old versioned caches remain after upgrades. Rewrite only Implexa-owned MCP
# manifests, never another marketplace/plugin, so a stale version cannot keep
# leaking a retired query/header credential through `codex mcp list/get`.
for LEGACY_MCP in "$PLUGIN_CACHE_BASE"/*/.mcp.json "$PLUGIN_CACHE_BASE"/*/.mcp.json.tmp*; do
  [ -e "$LEGACY_MCP" ] || continue
  [ -f "$LEGACY_MCP" ] && [ ! -L "$LEGACY_MCP" ] || {
    err "An Implexa-owned cached MCP manifest is not a safe regular file; refusing to continue."
    exit 1
  }
  LEGACY_MCP_TMP="$LEGACY_MCP.tmp.$$"
  write_secret_free_mcp_json "$LEGACY_MCP_TMP"
  mv "$LEGACY_MCP_TMP" "$LEGACY_MCP"
done
for LEGACY_MCP in "$PLUGIN_CACHE_BASE"/*/.mcp.json "$PLUGIN_CACHE_BASE"/*/.mcp.json.tmp*; do
  [ -e "$LEGACY_MCP" ] || continue
  prove_secret_free "$LEGACY_MCP"
done

print_skill_fallback() {
  warn "Couldn't auto-install the Implexa skill files into Codex's plugin cache."
  echo "    The MCP tools still work — you can invoke them via natural language"
  echo "    (\"implexa, run a skill for X\"). The \$implexa-* slash commands need"
  echo "    the plugin install to complete."
  echo ""
}

install_skill_files() {
  command -v git >/dev/null 2>&1 || { warn "git not found — can't clone plugin repo"; return 1; }

  mkdir -p "$CODEX_DIR/marketplaces" || return 1
  mkdir -p "$(dirname "$PLUGIN_CACHE_BASE")" || return 1

  # 1. Clone or refresh the marketplace source.
  if [ -d "$MARKETPLACE_DIR/.git" ]; then
    info "Updating Implexa plugin marketplace..."
    if ! (cd "$MARKETPLACE_DIR" && git fetch --quiet origin main && git reset --hard --quiet origin/main); then
      warn "git refresh failed (keeping existing copy)"
    fi
  else
    info "Cloning Implexa plugin marketplace..."
    if ! git clone --quiet --depth 1 "$PLUGIN_REPO_URL" "$MARKETPLACE_DIR"; then
      err "git clone failed (network issue?)"
      return 1
    fi
  fi

  # 2. Read the version from the plugin manifest.
  local plugin_json="$MARKETPLACE_DIR/.codex-plugin/plugin.json"
  if [ ! -f "$plugin_json" ]; then
    err "plugin.json missing after clone: $plugin_json"
    return 1
  fi
  local plugin_version
  plugin_version=$(jq -r '.version // "0.11.0"' "$plugin_json")
  printf '%s' "$plugin_version" | LC_ALL=C grep -Eq '^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$' || {
    err "plugin.json contains an unsafe version"
    return 1
  }
  local cache_dir="$PLUGIN_CACHE_BASE/$plugin_version"

  # 3. Copy into the versioned cache. Strip .git to keep the cache lean.
  rm -rf "$cache_dir"
  mkdir -p "$cache_dir"
  if ! cp -R "$MARKETPLACE_DIR/." "$cache_dir/"; then
    err "Failed to copy plugin to $cache_dir"
    return 1
  fi
  rm -rf "$cache_dir/.git"

  # 4. Defense in depth: canonicalize the cache manifest even if a stale
  # marketplace checkout was reused. Never substitute or persist an API key.
  if [ -f "$cache_dir/.mcp.json" ]; then
    write_secret_free_mcp_json "$cache_dir/.mcp.json"
    prove_secret_free "$cache_dir/.mcp.json"
  fi
  if [ -f "$MARKETPLACE_DIR/.mcp.json" ] && [ ! -L "$MARKETPLACE_DIR/.mcp.json" ]; then
    write_secret_free_mcp_json "$MARKETPLACE_DIR/.mcp.json"
    prove_secret_free "$MARKETPLACE_DIR/.mcp.json"
  fi

  ok "Installed $plugin_version skill files at $cache_dir"
  ok "$(ls "$cache_dir/skills" 2>/dev/null | wc -l | tr -d ' ') \$implexa-* commands available after Codex restart"
  return 0
}

if ! install_skill_files; then
  print_skill_fallback
fi

# ─── 6b. Register the plugin in config.toml ─────────────────────────────
#
# Cached skill files alone don't make $implexa-* commands surface. Codex
# only loads plugins that are explicitly registered via two TOML blocks:
#
#   [marketplaces.implexa]
#   source_type = "local"
#   source = "<path to cloned marketplace>"
#
#   [plugins."implexa@implexa"]
#   enabled = true
#
# Plugin id pattern is "<plugin-name>@<marketplace-name>". Both are
# "implexa" for us.
#
# Idempotent: if the blocks already exist, skip; if they're partially
# present, repair. Never touches other [marketplaces.*] / [plugins."*"]
# blocks.

register_plugin_in_config() {
  if [ ! -f "$CONFIG_TOML" ]; then
    err "config.toml missing — can't register plugin"
    return 1
  fi

  local needs_marketplace=0
  local needs_plugin=0

  if ! grep -q '^\[marketplaces\.implexa\]' "$CONFIG_TOML"; then
    needs_marketplace=1
  fi
  if ! grep -q '^\[plugins\.\"implexa@implexa\"\]' "$CONFIG_TOML"; then
    needs_plugin=1
  fi

  if [ $needs_marketplace -eq 0 ] && [ $needs_plugin -eq 0 ]; then
    ok "Plugin already registered in config.toml"
    return 0
  fi

  if [ $needs_marketplace -eq 1 ]; then
    printf '\n[marketplaces.implexa]\nsource_type = "local"\nsource = "%s"\n' "$MARKETPLACE_DIR" >> "$CONFIG_TOML"
  fi
  if [ $needs_plugin -eq 1 ]; then
    printf '\n[plugins."implexa@implexa"]\nenabled = true\n' >> "$CONFIG_TOML"
  fi

  ok "Registered [marketplaces.implexa] + [plugins.\"implexa@implexa\"] in config.toml"
  return 0
}

register_plugin_in_config || warn "couldn't register plugin in config.toml — \$implexa-* commands won't surface until you add the blocks manually"

# ─── 7. Done ─────────────────────────────────────────────────────────────
echo ""
echo "${C_BOLD}${C_GREEN}setup complete.${C_RESET}"
echo ""
echo "${C_BOLD}verify it works:${C_RESET}"
echo "  1. open Implexa Desktop and sign in"
echo "  2. keep Implexa open; fully quit Codex (close all sessions + the desktop app)"
echo "  3. relaunch Codex"
echo "  4. type: ${C_BOLD}\$implexa-help${C_RESET}"
echo "  5. you should see: 7 commands + your credit balance"
echo ""
echo "${C_BOLD}what's installed:${C_RESET}"
echo "  - MCP transport: revocable local Implexa Desktop broker"
echo "  - Your account key stays in Implexa Desktop and is never installed into Codex"
echo "  - 7 visible commands: suggest, run, record, my-skills, schedule, share-this, help"
echo "    (plus run-scheduled internally for the scheduler callback)"
echo "  - everything else (fork, morning brief, skill-roi, clawhub publish) is one natural-language ask away"
echo "  - Config: $CONFIG_TOML"
echo "  - Plugin cache: $PLUGIN_CACHE_BASE"
echo ""
echo "full docs at https://implexa.ai"
echo ""
