# How to: diagnose and recover (safely)

Full story: [CASE_STUDY.md](CASE_STUDY.md). Commands only here.

## 0. Quit the IDE first (for moves / GC / VACUUM)

```bash
# Cmd+Q in the UI, then:
ps aux | grep -i "[C]ursor"
```

Ignore macOS `CursorUIViewService`. No Cursor IDE / Electron workers should remain.

## 1. Read-only diagnose

```bash
./scripts/diagnose.sh
# or:
du -h "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
sqlite3 "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
  "SELECT COUNT(*) FROM cursorDiskKV;"
sqlite3 "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
  "PRAGMA page_size; PRAGMA page_count; PRAGMA freelist_count;"
```

Rough thresholds (heuristic, not official):

| `state.vscdb` | Action |
|---------------|--------|
| &lt; 2 GB | Monitor |
| 2–10 GB | Export important chats; consider GC; avoid endless single chats |
| 10–30 GB | Plan cleanup soon; free disk before compact |
| &gt; 30 GB | Treat as incident; prefer move-aside recovery if IDE is unusable |

## 2. Emergency: work again now (`mv`, never `rm`)

```bash
cd "$HOME/Library/Application Support/Cursor/User/globalStorage"
mkdir -p state-vscdb-backup-$(date +%Y%m%d)
for f in state.vscdb state.vscdb-shm state.vscdb-wal; do
  [ -e "$f" ] && mv "$f" state-vscdb-backup-$(date +%Y%m%d)/
done
```

Relaunch Cursor → new DB → New Chat → `hello`. Keep the backup forever until you decide.

## 3. Prefer keeping history

```text
Quit → confirm agent-transcripts exist
  → Export Chat for anything precious
  → Command Palette: Developer: GC Agent KV Blobs
  → Quit again → re-run diagnose.sh
```

If still huge: export → delete a few monster long chats → GC → quit. Prefer that over raw SQL `DELETE` + `VACUUM`.

## 4. Do not start here

```sql
DELETE FROM cursorDiskKV WHERE key LIKE 'agentKv:%';
-- ...
VACUUM;
```

Users have reported chat loss. Only after explicit impact discussion and backup.

## 5. Free disk before compact

Need roughly DB-sized free space (plan for up to ~2×). If compact hits Disk Full mid-way, you can worsen the outage.

## 6. Redact secrets

`ps` lines may contain `--api-key`. Never paste raw process lists to GitHub / Reddit / forums.
