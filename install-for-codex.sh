#!/usr/bin/env bash
#
# Implexa Codex plugin installer
# ──────────────────────────────────────────────────────────────────────────
# Run with:
#   curl -fsSL https://core.implexa.ai/install-for-codex.sh | bash
#
# What it does (one-time setup, idempotent — safe to re-run):
#   1. Checks that codex CLI is installed (or warns you to install it)
#   2. Reads IMPLEXA_API_KEY from env, --api-key flag, device-auth flow,
#      or interactive prompt (in that priority order)
#   3. Validates the key against https://core.implexa.ai/api/v2/auth/whoami
#   4. Writes the MCP server block to ~/.codex/config.toml (idempotent)
#   5. Prints verification steps: codex → $implexa-get-me-started
#
# After this script: open a new Codex session and type $implexa-get-me-started

set -e

# Add Homebrew to PATH if not already present (common on fresh Macs).
if ! command -v brew >/dev/null 2>&1; then
  if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
  if [ -x /usr/local/bin/brew ];   then eval "$(/usr/local/bin/brew shellenv)"; fi
fi

CODEX_DIR="$HOME/.codex"
CONFIG_TOML="$CODEX_DIR/config.toml"
API_BASE="${IMPLEXA_API_BASE_URL:-https://core.implexa.ai}"

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

# Helper: open URL in the user's default browser (best-effort).
open_browser() {
  local url="$1"
  if   command -v open     >/dev/null 2>&1; then open     "$url" >/dev/null 2>&1 &
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1 &
  elif command -v wslview  >/dev/null 2>&1; then wslview  "$url" >/dev/null 2>&1 &
  fi
}

echo ""
echo "${C_BOLD}Implexa Codex plugin installer${C_RESET}"
echo ""

# ─── Parse --api-key flag ────────────────────────────────────────────────
FLAG_API_KEY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-key)  FLAG_API_KEY="${2:-}"; shift 2 ;;
    --api-key=*) FLAG_API_KEY="${1#*=}"; shift ;;
    *) shift ;;
  esac
done

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

# ─── 3. Get the API key ──────────────────────────────────────────────────
# Priority: --api-key flag > IMPLEXA_API_KEY env > IMPLEXA_INSTALL_TOKEN
# > device-auth flow (browser) > interactive prompt (last resort)

API_KEY="${FLAG_API_KEY:-${IMPLEXA_API_KEY:-}}"

# -- Path 1: Install token (pre-baked from dashboard /install) -----------
if [ -z "$API_KEY" ] && [ -n "${IMPLEXA_INSTALL_TOKEN:-}" ]; then
  info "Redeeming install token..."
  REDEEM_RESPONSE=$(curl -sS -X POST "$API_BASE/api/v2/install-tokens/$IMPLEXA_INSTALL_TOKEN/redeem" \
    -H "Content-Type: application/json" 2>&1 || echo '{"error":"network error"}')
  API_KEY=$(echo "$REDEEM_RESPONSE" | jq -r '.apiKey // empty' 2>/dev/null)
  REDEEM_ERROR=$(echo "$REDEEM_RESPONSE" | jq -r '.error // empty' 2>/dev/null)
  if [ -z "$API_KEY" ]; then
    err "Failed to redeem install token: ${REDEEM_ERROR:-unknown error}"
    err "Tokens expire after 10 min and are single-use."
    err "Get a fresh install command at https://app.implexa.ai/install"
    exit 1
  fi
  ok "Token redeemed — got a fresh API key (${API_KEY:0:13}...)"
fi

# -- Path 2: Device-auth flow (browser login from terminal) --------------
# Used when the user runs: curl -fsSL https://core.implexa.ai/install-for-codex.sh | bash
# CRITICAL: always read from /dev/tty, never from stdin (stdin IS the script when piped from curl).
if [ -z "$API_KEY" ] && [ -r /dev/tty ]; then
  echo ""
  info "Starting browser login..."
  START_RESPONSE=$(curl -sS -X POST "$API_BASE/api/v2/cli-auth/start" \
    -H "Content-Type: application/json" -d '{}' 2>&1 || echo '{"error":"network error"}')
  DEVICE_CODE=$(echo "$START_RESPONSE"       | jq -r '.deviceCode // empty'       2>/dev/null)
  VERIFICATION_CODE=$(echo "$START_RESPONSE" | jq -r '.verificationCode // empty' 2>/dev/null)
  VERIFICATION_URL=$(echo "$START_RESPONSE"  | jq -r '.verificationUrl // empty'  2>/dev/null)
  POLL_INTERVAL=$(echo "$START_RESPONSE"     | jq -r '.interval // 2'             2>/dev/null)
  EXPIRES_IN=$(echo "$START_RESPONSE"        | jq -r '.expiresIn // 600'          2>/dev/null)

  if [ -z "$DEVICE_CODE" ] || [ -z "$VERIFICATION_URL" ]; then
    err "Failed to start browser login (could not reach $API_BASE)."
    warn "Falling back to manual API-key prompt."
  else
    echo ""
    echo "${C_BOLD}Open this URL in your browser to log in:${C_RESET}"
    echo ""
    echo "    ${C_BLUE}$VERIFICATION_URL${C_RESET}"
    echo ""
    echo "${C_BOLD}Verification code:${C_RESET}  ${C_GREEN}$VERIFICATION_CODE${C_RESET}"
    echo "    Make sure the browser shows the same code before approving."
    echo ""

    open_browser "$VERIFICATION_URL"
    info "Tried to open your browser automatically. If nothing happened, copy the URL above."

    MAX_POLLS=$(( (EXPIRES_IN / POLL_INTERVAL) + 5 ))
    POLL_COUNT=0
    AUTH_EMAIL=""
    echo -n "→ Waiting for approval (press Ctrl+C to cancel) "
    while [ $POLL_COUNT -lt $MAX_POLLS ]; do
      sleep "$POLL_INTERVAL"
      POLL_RESPONSE=$(curl -sS -X POST "$API_BASE/api/v2/cli-auth/poll" \
        -H "Content-Type: application/json" \
        -d "{\"deviceCode\":\"$DEVICE_CODE\"}" 2>&1 || echo '{"status":"network-error"}')
      POLL_STATUS=$(echo "$POLL_RESPONSE" | jq -r '.status // empty' 2>/dev/null)

      case "$POLL_STATUS" in
        approved)
          API_KEY=$(echo "$POLL_RESPONSE"    | jq -r '.apiKey // empty' 2>/dev/null)
          AUTH_EMAIL=$(echo "$POLL_RESPONSE" | jq -r '.email // empty'  2>/dev/null)
          if [ -n "$API_KEY" ]; then
            echo ""
            ok "Logged in as ${C_BOLD}$AUTH_EMAIL${C_RESET}"
          fi
          break
          ;;
        denied)
          echo ""; err "Login denied. Run the install command again if that wasn't intentional."
          exit 1 ;;
        expired)
          echo ""; err "Login session expired. Run the install command again."
          exit 1 ;;
        consumed)
          echo ""; err "Login session already used. Run the install command again."
          exit 1 ;;
        pending|"")
          if [ $(( POLL_COUNT % 5 )) -eq 0 ]; then printf "."; fi ;;
        *)
          if [ $(( POLL_COUNT % 5 )) -eq 0 ]; then printf "?"; fi ;;
      esac
      POLL_COUNT=$(( POLL_COUNT + 1 ))
    done

    if [ -z "$API_KEY" ]; then
      echo ""; err "Timed out waiting for browser approval. Run the install command again."
      exit 1
    fi

    echo ""
    echo "${C_BOLD}Press Enter to install, or Ctrl+C to cancel.${C_RESET}"
    read -r _confirm < /dev/tty || true
  fi
fi

# -- Path 3: Interactive prompt (last resort) ----------------------------
if [ -z "$API_KEY" ]; then
  if [ ! -r /dev/tty ]; then
    err "No API key provided and no terminal available to prompt."
    err "Set IMPLEXA_API_KEY first, or download + run the script directly:"
    echo "    curl -O https://raw.githubusercontent.com/Implexa-Inc/implexa-codex-plugin/main/install-for-codex.sh"
    echo "    bash install-for-codex.sh"
    exit 1
  fi
  echo ""
  echo "${C_BOLD}Enter your Implexa API key (imp_live_...):${C_RESET}"
  echo "Get one at https://app.implexa.ai/install"
  echo -n "API key: "
  read -r API_KEY < /dev/tty
  echo ""
  if [ -z "$API_KEY" ]; then
    err "No API key provided. Aborting."; exit 1
  fi
fi

# -- Sanity check key prefix --------------------------------------------
case "$API_KEY" in
  imp_*) ok "API key looks valid (starts with imp_)" ;;
  *)     warn "API key doesn't start with 'imp_' — proceeding anyway, but double-check it's correct" ;;
esac

# ─── 4. Validate the key ─────────────────────────────────────────────────
# Capture http status separately so we can surface meaningful errors instead
# of silently exiting on a 401/403/timeout. The previous version trusted
# `err` to print to stderr, but in the curl|bash pipe context some terminals
# buffer stderr separately and the user sees nothing before the script exits.
# Writing everything to stdout (with explicit flushes) is more reliable.
info "Validating API key against $API_BASE/api/v2/auth/whoami..."

WHOAMI_TMP=$(mktemp -t implexa-whoami.XXXXXX) || WHOAMI_TMP="/tmp/implexa-whoami.$$"
WHOAMI_HTTP=$(curl -sS -w '%{http_code}' -o "$WHOAMI_TMP" \
  --connect-timeout 10 --max-time 15 \
  "$API_BASE/api/v2/auth/whoami" \
  -H "Authorization: Bearer $API_KEY" 2>"$WHOAMI_TMP.err" || echo 'curl-failed')
WHOAMI_RESPONSE=$(cat "$WHOAMI_TMP" 2>/dev/null || true)
WHOAMI_CURL_ERR=$(cat "$WHOAMI_TMP.err" 2>/dev/null || true)
rm -f "$WHOAMI_TMP" "$WHOAMI_TMP.err"

WHOAMI_EMAIL=$(echo "$WHOAMI_RESPONSE" | jq -r '.email // .user.email // empty' 2>/dev/null)
WHOAMI_ERROR=$(echo "$WHOAMI_RESPONSE" | jq -r '.error // empty' 2>/dev/null)

if [ -z "$WHOAMI_EMAIL" ]; then
  # Print to stdout (not stderr) so curl|bash users always see it.
  echo ""
  echo "${C_RED}✗${C_RESET} API key validation failed."
  echo "  HTTP status: ${WHOAMI_HTTP:-(no response)}"
  [ -n "$WHOAMI_ERROR" ] && echo "  Error: $WHOAMI_ERROR"
  [ -n "$WHOAMI_CURL_ERR" ] && echo "  curl: $WHOAMI_CURL_ERR"
  echo ""
  case "$WHOAMI_HTTP" in
    401|403)
      echo "Your API key is rejected by the server. It may be revoked, expired,"
      echo "or never existed. Common cause: a stale IMPLEXA_API_KEY env var from"
      echo "an earlier install attempt. Fix:"
      echo ""
      echo "    unset IMPLEXA_API_KEY"
      echo "    curl -fsSL https://core.implexa.ai/install-for-codex.sh | bash"
      echo ""
      echo "Or grab a fresh key at https://app.implexa.ai/settings/api-keys"
      ;;
    000|curl-failed|"")
      echo "Couldn't reach $API_BASE. Check your network, then retry."
      ;;
    *)
      echo "Unexpected response from $API_BASE."
      [ -n "$WHOAMI_RESPONSE" ] && echo "Body: $WHOAMI_RESPONSE"
      echo "Get a fresh key at https://app.implexa.ai/settings/api-keys"
      ;;
  esac
  exit 1
fi
ok "Validated. Connected as $WHOAMI_EMAIL"

# ─── 5. Ensure ~/.codex dir exists ───────────────────────────────────────
if [ ! -d "$CODEX_DIR" ]; then
  mkdir -p "$CODEX_DIR"
  ok "Created Codex config directory at $CODEX_DIR"
else
  ok "Codex config directory found at $CODEX_DIR"
fi

# ─── 6. Write MCP server config to ~/.codex/config.toml (idempotent) ────
# Strategy:
#   - If config.toml doesn't exist, create it with just the implexa block.
#   - If it exists and already has an [mcp_servers.implexa] block, check if
#     the bearer_token differs. If same, skip. If different, update it.
#   - Never overwrite other [mcp_servers.*] blocks or unrelated config.
#
# We use awk for this — no external dependencies beyond what ships with macOS/Linux.

MCP_BLOCK="[mcp_servers.implexa]
type = \"http\"
url = \"https://core.implexa.ai/api/v2/mcp\"
bearer_token = \"$API_KEY\""

if [ ! -f "$CONFIG_TOML" ]; then
  # Fresh file — just write the block.
  printf '%s\n' "$MCP_BLOCK" > "$CONFIG_TOML"
  ok "Created $CONFIG_TOML with Implexa MCP server config"
else
  # File exists — check if [mcp_servers.implexa] section is already present.
  if grep -q '^\[mcp_servers\.implexa\]' "$CONFIG_TOML" 2>/dev/null; then
    # Section exists. Extract current bearer_token value.
    CURRENT_TOKEN=$(awk '/^\[mcp_servers\.implexa\]/{found=1} found && /bearer_token/{gsub(/[" ]/, ""); split($0,a,"="); print a[2]; exit}' "$CONFIG_TOML")
    if [ "$CURRENT_TOKEN" = "$API_KEY" ]; then
      ok "config.toml already has correct Implexa MCP config — no change needed"
    else
      # Token differs — replace just the bearer_token line within that section.
      BACKUP="$CONFIG_TOML.implexa-backup-$(date +%s)"
      cp "$CONFIG_TOML" "$BACKUP"
      awk -v new_token="$API_KEY" '
        /^\[mcp_servers\.implexa\]/ { in_section=1 }
        /^\[/ && !/^\[mcp_servers\.implexa\]/ { in_section=0 }
        in_section && /^bearer_token/ { print "bearer_token = \"" new_token "\""; next }
        { print }
      ' "$CONFIG_TOML" > "$CONFIG_TOML.tmp.$$" && mv "$CONFIG_TOML.tmp.$$" "$CONFIG_TOML"
      ok "Updated bearer_token in existing [mcp_servers.implexa] block (backup: $BACKUP)"
    fi
  else
    # Section not present — append it.
    echo "" >> "$CONFIG_TOML"
    printf '%s\n' "$MCP_BLOCK" >> "$CONFIG_TOML"
    ok "Appended [mcp_servers.implexa] block to $CONFIG_TOML"
  fi
fi

# ─── 7. Done ─────────────────────────────────────────────────────────────
echo ""
echo "${C_BOLD}${C_GREEN}setup complete.${C_RESET}"
echo ""
echo "${C_BOLD}verify it works:${C_RESET}"
echo "  1. open a new Codex session: ${C_BOLD}codex${C_RESET}"
echo "  2. type: ${C_BOLD}\$implexa-get-me-started${C_RESET}"
echo "  3. you should see: your Implexa identity + a quick-win Playbook run"
echo ""
echo "${C_BOLD}what's installed:${C_RESET}"
echo "  - MCP server: https://core.implexa.ai/api/v2/mcp (Streamable HTTP)"
echo "  - 14 skills: record, run, schedule, share, fork, playbooks, and more"
echo "  - Config: $CONFIG_TOML"
echo ""
echo "full docs at https://implexa.ai"
echo ""
