# When Cursor stuck on Loading chats: a 52 GB `state.vscdb`

After a Mac reboot, Cursor opened fine, but chat stayed on **Loading chats**. Even after the UI appeared, a new chat saying `hello` spun forever. Force-quit and relaunch failed many times; once it suddenly recovered and felt fast again.

I first blamed network, proxy, HTTP/2, and the service. The real anomaly was local:

```text
~/Library/Application Support/Cursor/User/globalStorage/state.vscdb  ≈ 52 GB
cursorDiskKV                                                      ≈ 2,731,416 rows
```

Moving that SQLite file aside (not deleting it) and letting Cursor create a fresh DB made New Chat answer `hello` almost instantly.

This repo is the full write-up: symptoms, measurements, A/B test, community parallels, and a safer cleanup order.

---

## Symptoms

1. **App starts, chat does not.** Editor works; chat shows `Loading chats` for a long time.
2. **Agent path is broken too.** After history loads, New Chat still spins on a trivial message — not just a slow history list.
3. **Intermittent recovery.** Many relaunches fail; one relaunch suddenly works and feels snappy. That pattern looks like a flaky network, but local evidence pointed elsewhere.

---

## Rule out a stuck process

Fully quit Cursor (`Cmd+Q`), then:

```bash
ps aux | grep -i "[C]ursor"
```

Ignore macOS `CursorUIViewService` (TextInput helper). Confirm no Cursor IDE / Electron workers remain before touching the DB.

---

## The oversized file

```bash
ls -lah "$HOME/Library/Application Support/Cursor/User/globalStorage/"
```

On this machine:

| Path | Size |
|------|------|
| `state.vscdb` | **52 GB** |
| `state.vscdb-wal` | ~4.7 MB |
| `conversation-search.db` | ~24 MB |
| whole `globalStorage` | ~58 GB |
| `workspaceStorage` (contrast) | ~294 MB |
| Cursor Cache (contrast) | ~41 MB |

Almost all of the bloat is one SQLite file: `state.vscdb`.

Tables:

```bash
sqlite3 "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
  "SELECT name FROM sqlite_master WHERE type='table';"
```

```text
ItemTable
cursorDiskKV
composerHeaders
```

A full `PRAGMA integrity_check;` on a 50+ GB DB can run forever; interrupt it. Prefer row counts and page stats first.

---

## Row counts

```sql
SELECT 'ItemTable', COUNT(*) FROM ItemTable
UNION ALL
SELECT 'cursorDiskKV', COUNT(*) FROM cursorDiskKV
UNION ALL
SELECT 'composerHeaders', COUNT(*) FROM composerHeaders;
```

| Table | Rows |
|-------|------|
| ItemTable | 976 |
| **cursorDiskKV** | **2,731,416** |
| composerHeaders | 1,048 |

---

## Not freelist “virtual fat”

```bash
sqlite3 "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
  "PRAGMA page_size; PRAGMA page_count; PRAGMA freelist_count;"
```

```text
page_size       4096
page_count      13551257
freelist_count  2208
```

- Used pages: `13551257 × 4096 ≈ 51.69 GiB` (matches the 52 GB file).
- Freelist: `2208 × 4096 ≈ 8.6 MiB` (~0.016% of the file).

So this is **not** a DB that deleted most data and never ran `VACUUM`. Most pages are in use.

`ItemTable` largest values were under ~759 KB; 976 rows cannot explain 52 GB. Suspicion concentrates on `cursorDiskKV` (`key TEXT`, `value BLOB`).

---

## Transcripts on disk are tiny by comparison

```bash
find "$HOME/.cursor/projects" -type f -path "*/agent-transcripts/*.jsonl" 2>/dev/null | wc -l
du -sh "$HOME/.cursor/projects"
```

```text
1015 JSONL transcripts
~/.cursor/projects ≈ 728 MB
```

~728 MB of JSONL vs ~52 GB of `state.vscdb` (~70×). The SQLite file is not “just because I chat a lot.” Treat JSONL as extra insurance, not a full UI / index restore.

---

## A/B test (strongest evidence)

With Cursor fully quit:

```bash
cd "$HOME/Library/Application Support/Cursor/User/globalStorage"
mkdir -p state-vscdb-backup
for f in state.vscdb state.vscdb-shm state.vscdb-wal; do
  [ -e "$f" ] && mv "$f" state-vscdb-backup/
done
```

Relaunch Cursor → new empty `state.vscdb` → New Chat → `hello` → **near-instant reply**.

Unchanged: Mac, network, install, account, model, project. Changed: old 52 GB DB → new DB.

Restoring the old DB later also started quickly again. That does **not** mean the DB healed itself; oversized DBs can fail in cold-start / cache / init–dependent ways. Treat 52 GB as still abnormal.

---

## Community parallels

Cursor Community Forum reports include ~30 GB / ~1.96M `cursorDiskKV` rows (`bubbleId`, `agentKv`, `checkpointId`), and even ~96 GB cases that keep growing with long Agent use. Support notes mention Agent self-fork / full transcript copies, and **Developer: GC Agent KV Blobs** for orphaned KV — GC is conservative and will not shrink live data still referenced by long chats. Compaction may need roughly as much free disk as the DB size (sometimes approaching 2×); do not `VACUUM` a 50 GB DB on a nearly full disk.

---

## Safer recovery if Cursor is unusable

1. Quit fully; confirm no IDE processes.
2. **Move** (do not delete) `state.vscdb`, `-wal`, `-shm` aside.
3. Relaunch so Cursor creates a small DB and you can work again.
4. Keep the backup; chat history in the new DB may not list the old threads.

If you still care about old chats and have disk headroom:

```text
Quit → keep old DB → confirm agent-transcripts exist
  → Export Chat for anything important
  → Developer: GC Agent KV Blobs
  → Quit again → re-check size and behavior
```

If still tens of GB: export, delete the few enormous long chats, GC again, quit. Prefer that over raw SQL `DELETE FROM cursorDiskKV ...` + `VACUUM` (users have reported chat loss that way).

---

## Monitoring

```bash
du -h "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"

sqlite3 "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
  "SELECT COUNT(*) FROM cursorDiskKV;"

sqlite3 "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
  "PRAGMA page_size; PRAGMA page_count; PRAGMA freelist_count;"
```

Act when the file climbs through multi-GB into tens of GB. Prefer shorter Agent threads over one endless chat that self-forks.

**Do not paste `ps` lines that include `--api-key` into public posts.** Redact tokens; rotate if you already leaked one.

---

## Takeaway

A local SQLite state file can look exactly like a network / API failure: Loading chats, Agent spin, many failed relaunches, then a sudden fast recovery. In this case the chain was:

```text
52 GB state.vscdb
+ ~2.73M cursorDiskKV rows
+ near-zero freelist
+ fresh DB → instant hello
```

When you see that pattern after a reboot, check `state.vscdb` before reinstalling the app.

---

## Repo layout

| Path | Purpose |
|------|---------|
| [README.md](README.md) | This case study |
| [docs/AGENT_CONTEXT.md](docs/AGENT_CONTEXT.md) | Paste-ready context for a local Agent to continue *read-only* analysis |
| [docs/DIAGNOSTIC_COMMANDS.md](docs/DIAGNOSTIC_COMMANDS.md) | Short command checklist |
| [social/x-draft.md](social/x-draft.md) | Draft post for X |
| [social/reddit-draft.md](social/reddit-draft.md) | Draft post for Reddit |

MIT. Copyright (c) 2026 Xuzhen Li.
