#!/usr/bin/env bash
# Read-only health sketch for Cursor globalStorage/state.vscdb.
# Does not modify any files. Quit Cursor before trusting row counts if the app is writing.
set -euo pipefail

DB="${CURSOR_STATE_DB:-$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb}"
GS="$(dirname "$DB")"

echo "== path =="
echo "$DB"
if [[ ! -f "$DB" ]]; then
  echo "missing: state.vscdb"
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

echo
echo "== tables =="
sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"

echo
echo "== row counts =="
sqlite3 -separator $'\t' "$DB" "
SELECT 'ItemTable', COUNT(*) FROM ItemTable
UNION ALL SELECT 'cursorDiskKV', COUNT(*) FROM cursorDiskKV
UNION ALL SELECT 'composerHeaders', COUNT(*) FROM composerHeaders;
" 2>/dev/null || echo "(row count failed — is Cursor holding a lock?)"

echo
echo "== pages =="
sqlite3 "$DB" "PRAGMA page_size; PRAGMA page_count; PRAGMA freelist_count;" 2>/dev/null || true

echo
echo "== freelist fraction (approx) =="
sqlite3 "$DB" "
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
echo "done (read-only)."
