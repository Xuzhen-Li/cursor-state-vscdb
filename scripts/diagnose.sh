#!/usr/bin/env bash
# Health check for Cursor's globalStorage/state.vscdb. It never writes to the database.
#
# How it opens the file:
#   Cursor not running: as file:...?mode=ro&immutable=1. SQLite then skips locking and
#     does not create the -wal/-shm side files. If Cursor is in fact running and writing,
#     the numbers can be wrong or inconsistent, so quit Cursor first.
#   Cursor running: with sqlite3 -readonly. The read is consistent, but the Cursor DB is
#     in WAL mode, so SQLite may create or update state.vscdb-wal / state.vscdb-shm.
# The script guesses which case applies with pgrep. To choose yourself, set
#   CURSOR_DIAG_OPEN=immutable   or   CURSOR_DIAG_OPEN=readonly
# (URI options: https://www.sqlite.org/uri.html; WAL side files: https://www.sqlite.org/wal.html)
set -euo pipefail

# Default locations (Cursor staff, forum.cursor.com/t/124271):
#   macOS:   ~/Library/Application Support/Cursor/User/globalStorage/state.vscdb
#   Linux:   ~/.config/Cursor/User/globalStorage/state.vscdb
#   Windows: %APPDATA%\Cursor\User\globalStorage\state.vscdb (no default: set CURSOR_STATE_DB)
case "$(uname -s)" in
  Darwin) DEFAULT_DB="$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" ;;
  Linux)  DEFAULT_DB="$HOME/.config/Cursor/User/globalStorage/state.vscdb" ;;
  *)      DEFAULT_DB="" ;;
esac
DB="${CURSOR_STATE_DB:-$DEFAULT_DB}"
if [[ -z "$DB" ]]; then
  echo "Unknown system. Set CURSOR_STATE_DB to the full path of state.vscdb and run again."
  exit 1
fi
GS="$(dirname "$DB")"

echo "== path =="
echo "$DB"
if [[ ! -f "$DB" ]]; then
  echo "missing: state.vscdb"
  echo "If Cursor keeps it somewhere else, run: CURSOR_STATE_DB=/full/path/state.vscdb $0"
  exit 1
fi

echo
echo "== size =="
du -h "$DB" "${DB}-wal" "${DB}-shm" 2>/dev/null || true
du -sh "$GS" 2>/dev/null || true

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo
  echo "sqlite3 not found; install it to see row/page stats."
  exit 0
fi

# Percent-encode a path for use in a file: URI (keeps letters, digits, / . _ ~ -).
uri_path() {
  local LC_ALL=C s="$1" out="" c hex i
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      [A-Za-z0-9/._~-]) out+="$c" ;;
      *) printf -v hex '%%%02X' "'$c"; out+="$hex" ;;
    esac
  done
  printf '%s' "$out"
}

cursor_running() {
  # Best guess only: process names differ between installs.
  pgrep -x Cursor >/dev/null 2>&1 || pgrep -x cursor >/dev/null 2>&1
}

MODE="${CURSOR_DIAG_OPEN:-}"
if [[ -z "$MODE" ]]; then
  if ! command -v pgrep >/dev/null 2>&1; then
    MODE=readonly
    echo
    echo "(pgrep not found; cannot tell if Cursor is running, so using -readonly)"
  elif cursor_running; then
    MODE=readonly
  else
    MODE=immutable
  fi
fi

echo
echo "== open mode =="
case "$MODE" in
  immutable)
    TARGET="file:$(uri_path "$DB")?mode=ro&immutable=1"
    echo "immutable (Cursor looks closed). No -wal/-shm files are created."
    echo "If Cursor is actually running, these numbers may be inconsistent."
    ;;
  readonly)
    TARGET="$DB"
    echo "readonly (Cursor looks open, or the script could not tell). The database is not written, but in WAL mode"
    echo "SQLite may create or update state.vscdb-wal and state.vscdb-shm."
    ;;
  *)
    echo "CURSOR_DIAG_OPEN must be 'immutable' or 'readonly', not '$MODE'."
    exit 1
    ;;
esac

q() { sqlite3 -readonly -separator $'\t' "$TARGET" "$1"; }

echo
echo "== tables =="
q "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;" 2>/dev/null \
  || echo "(could not read the table list: the file may be locked or damaged)"

echo
echo "== row counts =="
for t in ItemTable cursorDiskKV composerHeaders; do
  n="$(q "SELECT COUNT(*) FROM $t;" 2>/dev/null)" || n="(not found or unreadable)"
  printf '%s\t%s\n' "$t" "$n"
done

echo
echo "== pages =="
q "PRAGMA page_size; PRAGMA page_count; PRAGMA freelist_count;" 2>/dev/null || true

echo
echo "== freelist fraction (approx) =="
q "
SELECT printf('pages=%s freelist=%s freelist_pct=%.4f',
  page_count, freelist_count,
  100.0 * freelist_count / CASE WHEN page_count=0 THEN 1 ELSE page_count END)
FROM pragma_page_count(), pragma_freelist_count();
" 2>/dev/null || true

echo
echo "== transcripts on disk (optional) =="
if [[ -d "$HOME/.cursor/projects" ]]; then
  find "$HOME/.cursor/projects" -type f -path '*/agent-transcripts/*.jsonl' 2>/dev/null | wc -l | awk '{print "jsonl_count",$1}'
  du -sh "$HOME/.cursor/projects" 2>/dev/null || true
else
  echo "~/.cursor/projects not found"
fi

echo
echo "done (the database was not written; open mode: $MODE)."
