# Diagnostic commands (read-only first)

Fully quit the IDE before any write/move. Ignore macOS `CursorUIViewService`.

## Size

```bash
du -h "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
du -sh "$HOME/Library/Application Support/Cursor/User/globalStorage"
du -sh "$HOME/Library/Application Support/Cursor/User/workspaceStorage"
```

## Tables and counts

```bash
DB="$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"

sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='table';"

sqlite3 "$DB" "
SELECT 'ItemTable', COUNT(*) FROM ItemTable
UNION ALL
SELECT 'cursorDiskKV', COUNT(*) FROM cursorDiskKV
UNION ALL
SELECT 'composerHeaders', COUNT(*) FROM composerHeaders;
"
```

## Pages vs freelist

```bash
sqlite3 "$DB" "PRAGMA page_size; PRAGMA page_count; PRAGMA freelist_count;"
```

Rough GiB in use: `page_count * page_size / 1024^3`. Freelist bytes: `freelist_count * page_size`.

## Key prefix sketch (read-only; can be slow)

```bash
sqlite3 "$DB" "
SELECT
  CASE
    WHEN key LIKE 'bubbleId:%' THEN 'bubbleId'
    WHEN key LIKE 'agentKv:%' THEN 'agentKv'
    WHEN key LIKE 'checkpointId:%' THEN 'checkpointId'
    WHEN key LIKE 'composerData:%' THEN 'composerData'
    WHEN key LIKE 'composerId:%' THEN 'composerId'
    ELSE 'other'
  END AS kind,
  COUNT(*) AS n,
  SUM(LENGTH(value)) AS bytes
FROM cursorDiskKV
GROUP BY 1
ORDER BY bytes DESC;
"
```

## Transcripts on disk

```bash
find "$HOME/.cursor/projects" -type f -path "*/agent-transcripts/*.jsonl" 2>/dev/null | wc -l
du -sh "$HOME/.cursor/projects"
```

## Emergency move (not delete)

```bash
cd "$HOME/Library/Application Support/Cursor/User/globalStorage"
mkdir -p state-vscdb-backup
for f in state.vscdb state.vscdb-shm state.vscdb-wal; do
  [ -e "$f" ] && mv "$f" state-vscdb-backup/
done
```

Do **not** run `DELETE ...` or `VACUUM` until you have free disk roughly on the order of the DB size and an explicit plan for chat loss.
