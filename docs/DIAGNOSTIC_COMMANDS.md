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

Row counts are cheap relative to `SUM(LENGTH(value))`. This case measured prefix **counts** post-GC (~98.4% bubble/agentKv/checkpoint) but **not** byte GiB yet — keep the `SUM` query marked unrun until you finish it.

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

## Post-GC reference (this case; Cursor 3.22.7)

After one `Developer: GC Agent KV Blobs` run (>1h; WAL peak ≈52 GB; free dipped ≈18 GiB):

```text
ItemTable           985
cursorDiskKV        2,731,751   (+335 vs pre)
composerHeaders     1,048
page_count          13,520,717  (−30,540 ≈ 119.3 MiB)
freelist_count      186
bubbleId rows       2,029,436   (~74.29%)
agentKv rows        653,694     (~23.93%)
checkpointId rows   4,659       (~0.17%)
sum of three        ≈98.39% of cursorDiskKV rows
```

Byte GiB per class: **not measured yet**. Use the key-prefix `SUM(LENGTH(value))` query above; it can be very slow on a 50+ GB DB. Do not invent GiB numbers.

While freelist is already ~186 pages, do **not** expect `VACUUM` to shrink the main file. Prefer Export → Delete Old Chats… → GC → Quit when following staff order (Delete Old Chats untested in this case study). Blind second GC is pointless with live data dominating.
