#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/implexa-codex-install-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

SECRET='imp_live_legacy_secret_must_disappear'
HOME_FIXTURE="$TMP/home"
PLUGIN_REPO="$TMP/plugin"
mkdir -p "$HOME_FIXTURE/.codex/plugins/cache/implexa/implexa/0.1.0" "$PLUGIN_REPO/.codex-plugin" "$PLUGIN_REPO/skills/help"

cat > "$PLUGIN_REPO/.codex-plugin/plugin.json" <<'JSON'
{"name":"implexa","version":"1.2.3"}
JSON
cat > "$PLUGIN_REPO/.mcp.json" <<JSON
{"implexa":{"url":"https://core.implexa.ai/api/v2/mcp?api_key=$SECRET"}}
JSON
printf '%s\n' '# fixture' > "$PLUGIN_REPO/skills/help/SKILL.md"
git -C "$PLUGIN_REPO" init -q
git -C "$PLUGIN_REPO" add .
git -C "$PLUGIN_REPO" -c user.name=test -c user.email=test@example.invalid commit -qm fixture
git -C "$PLUGIN_REPO" branch -M main

cat > "$HOME_FIXTURE/.codex/config.toml" <<EOF
[mcp_servers.other]
command = "/usr/bin/true"

[mcp_servers.implexa]
url = "https://core.implexa.ai/api/v2/mcp?api_key=$SECRET"

[features]
plugins = true
EOF
cat > "$HOME_FIXTURE/.codex/config.toml.implexa-backup-old" <<EOF
[other]
keep = "backup"
[mcp_servers.implexa]
headers = { Authorization = "Bearer $SECRET" }
EOF
cat > "$HOME_FIXTURE/.codex/config.toml.tmp.legacy" <<EOF
[other]
keep = "temporary"
[mcp_servers.implexa]
bearer_token = "$SECRET"
EOF
cat > "$HOME_FIXTURE/.codex/plugins/cache/implexa/implexa/0.1.0/.mcp.json" <<EOF
{"implexa":{"url":"https://core.implexa.ai/api/v2/mcp?api_key=$SECRET"}}
EOF
cp "$HOME_FIXTURE/.codex/plugins/cache/implexa/implexa/0.1.0/.mcp.json" \
  "$HOME_FIXTURE/.codex/plugins/cache/implexa/implexa/0.1.0/.mcp.json.tmp"

OUTPUT="$TMP/output"
HOME="$HOME_FIXTURE" IMPLEXA_API_KEY="$SECRET" IMPLEXA_PLUGIN_REPO_URL="$PLUGIN_REPO" \
  bash "$ROOT/install-for-codex.sh" >"$OUTPUT" 2>&1

if grep -R -Fq "$SECRET" "$HOME_FIXTURE"; then
  echo 'legacy secret survived installation' >&2
  exit 1
fi
if grep -Fq "$SECRET" "$OUTPUT"; then
  echo 'installer output leaked legacy secret' >&2
  exit 1
fi
grep -q '^\[mcp_servers.other\]' "$HOME_FIXTURE/.codex/config.toml"
grep -q '^\[features\]' "$HOME_FIXTURE/.codex/config.toml"
grep -q 'keep = "backup"' "$HOME_FIXTURE/.codex/config.toml.implexa-backup-old"
grep -q 'keep = "temporary"' "$HOME_FIXTURE/.codex/config.toml.tmp.legacy"
grep -q '^command = ' "$HOME_FIXTURE/.codex/config.toml"
if grep -Eq '^args[[:space:]]*=|/bin/(ba)?sh' "$HOME_FIXTURE/.codex/config.toml"; then
  echo 'installed MCP config unnecessarily uses a shell' >&2
  exit 1
fi
cmp "$ROOT/scripts/implexa-codex-mcp" "$HOME_FIXTURE/.implexa/bin/implexa-codex-mcp"

for manifest in \
  "$HOME_FIXTURE/.codex/marketplaces/implexa/.mcp.json" \
  "$HOME_FIXTURE/.codex/plugins/cache/implexa/implexa/0.1.0/.mcp.json" \
  "$HOME_FIXTURE/.codex/plugins/cache/implexa/implexa/0.1.0/.mcp.json.tmp" \
  "$HOME_FIXTURE/.codex/plugins/cache/implexa/implexa/1.2.3/.mcp.json"; do
  jq -e --arg expected "$HOME_FIXTURE/.implexa/bin/implexa-codex-mcp" \
    '.implexa.command == $expected and (.implexa | has("args") | not) and (.implexa | has("url") | not)' "$manifest" >/dev/null
done

# Finder-like sparse execution reaches only the validated private socket path;
# without Desktop/locator it fails closed with no stdout or secret reflection.
if [ "$(uname -s)" = Darwin ] && [ -x /usr/bin/nc ]; then
  FINDER_HOME="$TMP/finder-home"
  SOCKET_ROOT="$(mktemp -d /private/tmp/implexa-codex-mcp-XXXXXX)"
  SOCKET_PATH="$SOCKET_ROOT/broker-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.sock"
  mkdir -p "$FINDER_HOME/.implexa"
  node -e '
    const net = require("net");
    const server = net.createServer((socket) => socket.once("data", (data) => {
      socket.end(data); server.close();
    }));
    server.listen(process.argv[1]);
  ' "$SOCKET_PATH" &
  SOCKET_SERVER_PID=$!
  for _try in 1 2 3 4 5 6 7 8 9 10; do [ -S "$SOCKET_PATH" ] && break; sleep 0.05; done
  printf '%s' "$SOCKET_PATH" > "$FINDER_HOME/.implexa/codex-mcp.current"
  chmod 600 "$FINDER_HOME/.implexa/codex-mcp.current"
  REQUEST='{"jsonrpc":"2.0","id":1,"method":"ping"}'
  RESPONSE="$(printf '%s\n' "$REQUEST" | env -i HOME="$FINDER_HOME" PATH=/usr/bin:/bin "$ROOT/scripts/implexa-codex-mcp")"
  wait "$SOCKET_SERVER_PID"
  [ "$RESPONSE" = "$REQUEST" ]
  rm -rf "$SOCKET_ROOT"

  MISSING_HOME="$TMP/finder-missing-home"
  mkdir -p "$MISSING_HOME"
  if env -i HOME="$MISSING_HOME" PATH=/usr/bin:/bin "$ROOT/scripts/implexa-codex-mcp" >"$TMP/finder-missing-out" 2>"$TMP/finder-missing-err"; then
    echo 'shim connected without Desktop locator' >&2
    exit 1
  fi
  [ ! -s "$TMP/finder-missing-out" ]
  grep -q 'Open Implexa' "$TMP/finder-missing-err"
  ! grep -Fq "$SECRET" "$TMP/finder-missing-err"
fi

# Idempotence: a second Finder-like run stays secret-free and direct-command.
env -i HOME="$HOME_FIXTURE" PATH="$PATH" IMPLEXA_PLUGIN_REPO_URL="$PLUGIN_REPO" \
  bash "$ROOT/install-for-codex.sh" >"$TMP/output-second" 2>&1
! grep -R -Eiq 'api_key=imp_|bearer_token[^[:cntrl:]]*imp_|authorization[^[:cntrl:]]*imp_' "$HOME_FIXTURE"

# Legacy secret flags are refused without reflecting the value.
if HOME="$HOME_FIXTURE" bash "$ROOT/install-for-codex.sh" "--api-key=$SECRET" >"$TMP/refused" 2>&1; then
  echo 'legacy API-key flag was accepted' >&2
  exit 1
fi
! grep -Fq "$SECRET" "$TMP/refused"

# A symlinked config is never followed or replaced.
SYMLINK_HOME="$TMP/symlink-home"
mkdir -p "$SYMLINK_HOME/.codex"
printf '%s\n' 'sentinel = true' > "$TMP/config-target"
ln -s "$TMP/config-target" "$SYMLINK_HOME/.codex/config.toml"
if HOME="$SYMLINK_HOME" IMPLEXA_PLUGIN_REPO_URL="$PLUGIN_REPO" bash "$ROOT/install-for-codex.sh" >"$TMP/symlink-output" 2>&1; then
  echo 'symlinked config was accepted' >&2
  exit 1
fi
grep -q '^sentinel = true$' "$TMP/config-target"

# Cache parent and version components are validated before any write. Neither a
# parent symlink nor a version symlink may redirect migration into an external
# target, and a refused setup must not print the success footer.
for kind in parent version; do
  LINK_HOME="$TMP/link-$kind-home"
  EXTERNAL="$TMP/link-$kind-external"
  mkdir -p "$LINK_HOME/.codex" "$EXTERNAL"
  printf '%s\n' "$SECRET" > "$EXTERNAL/sentinel"
  if [ "$kind" = parent ]; then
    ln -s "$EXTERNAL" "$LINK_HOME/.codex/plugins"
  else
    mkdir -p "$LINK_HOME/.codex/plugins/cache/implexa/implexa"
    ln -s "$EXTERNAL" "$LINK_HOME/.codex/plugins/cache/implexa/implexa/9.9.9"
  fi
  if HOME="$LINK_HOME" IMPLEXA_PLUGIN_REPO_URL="$PLUGIN_REPO" bash "$ROOT/install-for-codex.sh" >"$TMP/link-$kind-output" 2>&1; then
    echo "symlinked cache $kind was accepted" >&2
    exit 1
  fi
  grep -q "^$SECRET$" "$EXTERNAL/sentinel"
  ! grep -q 'setup complete' "$TMP/link-$kind-output"
done

# An existing marketplace is scrubbed before refresh. Even when its remote is
# unavailable, both the retained checkout and the copied cache are canonical.
OFFLINE_HOME="$TMP/offline-home"
mkdir -p "$OFFLINE_HOME/.codex/marketplaces"
git clone -q "$PLUGIN_REPO" "$OFFLINE_HOME/.codex/marketplaces/implexa"
git -C "$OFFLINE_HOME/.codex/marketplaces/implexa" remote set-url origin "$TMP/does-not-exist"
cat > "$OFFLINE_HOME/.codex/marketplaces/implexa/.mcp.json" <<EOF
{"implexa":{"url":"https://core.implexa.ai/api/v2/mcp?api_key=$SECRET"}}
EOF
HOME="$OFFLINE_HOME" bash "$ROOT/install-for-codex.sh" >"$TMP/offline-output" 2>&1
! grep -R -Fq "$SECRET" "$OFFLINE_HOME/.codex/marketplaces/implexa/.mcp.json" \
  "$OFFLINE_HOME/.codex/plugins/cache/implexa/implexa/1.2.3/.mcp.json"
grep -q 'git refresh failed' "$TMP/offline-output"
grep -q 'setup complete' "$TMP/offline-output"

# A symlinked marketplace manifest is unsrubbable and therefore terminal. The
# external target remains byte-for-byte intact and success is never claimed.
MARKET_LINK_HOME="$TMP/market-link-home"
mkdir -p "$MARKET_LINK_HOME/.codex/marketplaces/implexa"
printf '%s\n' "$SECRET" > "$TMP/market-external"
ln -s "$TMP/market-external" "$MARKET_LINK_HOME/.codex/marketplaces/implexa/.mcp.json"
if HOME="$MARKET_LINK_HOME" bash "$ROOT/install-for-codex.sh" >"$TMP/market-link-output" 2>&1; then
  echo 'symlinked marketplace manifest was accepted' >&2
  exit 1
fi
grep -q "^$SECRET$" "$TMP/market-external"
! grep -q 'setup complete' "$TMP/market-link-output"

# An untrusted plugin version cannot turn the cache cleanup into path traversal.
UNSAFE_REPO="$TMP/unsafe-plugin"
UNSAFE_HOME="$TMP/unsafe-home"
mkdir -p "$UNSAFE_REPO/.codex-plugin" "$UNSAFE_REPO/skills/help" "$UNSAFE_HOME/victim"
printf '%s\n' '{"name":"implexa","version":"../../victim"}' > "$UNSAFE_REPO/.codex-plugin/plugin.json"
printf '%s\n' '{}' > "$UNSAFE_REPO/.mcp.json"
printf '%s\n' '# fixture' > "$UNSAFE_REPO/skills/help/SKILL.md"
printf '%s\n' 'do not delete' > "$UNSAFE_HOME/victim/sentinel"
git -C "$UNSAFE_REPO" init -q
git -C "$UNSAFE_REPO" add .
git -C "$UNSAFE_REPO" -c user.name=test -c user.email=test@example.invalid commit -qm fixture
git -C "$UNSAFE_REPO" branch -M main
HOME="$UNSAFE_HOME" IMPLEXA_PLUGIN_REPO_URL="$UNSAFE_REPO" bash "$ROOT/install-for-codex.sh" >"$TMP/unsafe-output" 2>&1
grep -q 'unsafe version' "$TMP/unsafe-output"
grep -q '^do not delete$' "$UNSAFE_HOME/victim/sentinel"

echo 'secret-free Codex install migration: ok'
