#!/bin/bash
# browser-lock.sh — OpenClaw browser ↔ Playwright mutex manager
#
# Usage:
#   browser-lock.sh acquire              — stop OpenClaw browser, start standalone Chrome, take lock
#   browser-lock.sh release              — kill standalone Chrome, release lock
#   browser-lock.sh run <script> [args]  — acquire → run script → release
#   browser-lock.sh status               — show current state

set -euo pipefail

LOCK_FILE="/tmp/openclaw-browser.lock"
CDP_PORT="${CDP_PORT:-18800}"
USER_DATA_DIR="$HOME/.openclaw/browser/openclaw/user-data"
PID_FILE="/tmp/openclaw-browser-standalone.pid"

if [ -z "${CHROME_BIN:-}" ]; then
  if [ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]; then
    CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  elif command -v google-chrome &>/dev/null; then
    CHROME_BIN="google-chrome"
  elif command -v chromium-browser &>/dev/null; then
    CHROME_BIN="chromium-browser"
  elif command -v chromium &>/dev/null; then
    CHROME_BIN="chromium"
  else
    echo "❌ Chrome not found. Set CHROME_BIN." >&2
    exit 1
  fi
fi

kill_cdp_chrome() {
  local pids
  pids=$(ps aux | grep "remote-debugging-port=$CDP_PORT" | grep -v grep | awk '{print $2}' || true)
  if [ -n "$pids" ]; then
    echo "⏹ Stopping Chrome on CDP port $CDP_PORT (PIDs: $pids)..."
    echo "$pids" | xargs kill 2>/dev/null || true
    sleep 1
    for pid in $pids; do
      kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
    done
  fi
}

start_chrome() {
  if curl -s --max-time 1 "http://127.0.0.1:$CDP_PORT/json/version" &>/dev/null; then
    echo "⚠️ CDP port $CDP_PORT already in use"
    return 0
  fi

  echo "🚀 Starting Chrome on CDP port $CDP_PORT..."
  "$CHROME_BIN" \
    --remote-debugging-port="$CDP_PORT" \
    --user-data-dir="$USER_DATA_DIR" \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-background-networking \
    --disable-component-update \
    --disable-features=Translate,MediaRouter \
    --disable-session-crashed-bubble \
    --hide-crash-restore-bubble \
    --password-store=basic \
    --disable-blink-features=AutomationControlled \
    about:blank &>/dev/null &

  local chrome_pid=$!
  echo "$chrome_pid" > "$PID_FILE"

  for i in $(seq 1 10); do
    if curl -s --max-time 1 "http://127.0.0.1:$CDP_PORT/json/version" &>/dev/null; then
      echo "✅ Chrome ready (PID: $chrome_pid, CDP: $CDP_PORT)"
      return 0
    fi
    sleep 0.5
  done
  echo "❌ Chrome failed to start" >&2
  return 1
}

acquire() {
  if [ -f "$LOCK_FILE" ]; then
    local lock_pid
    lock_pid=$(cat "$LOCK_FILE")
    if kill -0 "$lock_pid" 2>/dev/null; then
      echo "❌ Lock held by PID $lock_pid. Use 'release' first." >&2
      exit 1
    else
      echo "⚠️ Stale lock (PID $lock_pid dead), cleaning..."
      rm -f "$LOCK_FILE"
    fi
  fi
  echo $$ > "$LOCK_FILE"
  kill_cdp_chrome
  sleep 1
  start_chrome
}

release() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo "⏹ Stopping standalone Chrome (PID: $pid)..."
      kill "$pid" 2>/dev/null || true
      sleep 1
      kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
  fi
  kill_cdp_chrome
  rm -f "$LOCK_FILE"
  echo "🔓 Released. OpenClaw browser can restart via 'browser start'."
}

run_script() {
  if [ $# -lt 1 ]; then
    echo "Usage: browser-lock.sh run <script.js> [args...]" >&2
    exit 1
  fi
  acquire
  local exit_code=0
  echo "▶ Running: node $*"
  node "$@" || exit_code=$?
  release
  [ $exit_code -ne 0 ] && echo "❌ Script exited with code $exit_code"
  return $exit_code
}

status() {
  echo "--- Browser Lock Status ---"
  if [ -f "$LOCK_FILE" ]; then
    local lock_pid
    lock_pid=$(cat "$LOCK_FILE")
    if kill -0 "$lock_pid" 2>/dev/null; then
      echo "🔒 Locked by PID $lock_pid"
    else
      echo "⚠️ Stale lock (PID $lock_pid dead)"
    fi
  else
    echo "🔓 Unlocked"
  fi
  if curl -s --max-time 1 "http://127.0.0.1:$CDP_PORT/json/version" &>/dev/null; then
    echo "🌐 Chrome running on CDP port $CDP_PORT"
  else
    echo "⭕ No Chrome on CDP port $CDP_PORT"
  fi
}

case "${1:-status}" in
  acquire) acquire ;;
  release) release ;;
  run)     shift; run_script "$@" ;;
  status)  status ;;
  *)       echo "Usage: browser-lock.sh {acquire|release|run <script.js>|status}" >&2; exit 1 ;;
esac
