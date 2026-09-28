> **Preservation:** The complete original Chinese write-up is archived at [docs/zh/CASE_STUDY.md](zh/CASE_STUDY.md) and must not be deleted or shortened. This file is the full English case study (same sections). Guides and figures live in other paths only.

# After reboot, Cursor stuck on Loading chats: a 52 GB `state.vscdb`

I hit a painful Cursor failure.

After a Mac reboot, Cursor itself opened, but chat stayed on:

```text
Loading chats
```

Even when the chat UI finally appeared, the simplest message:

```text
hello
```

spun forever with no reply.

Stranger still: many force-quits and relaunches did nothing, then one relaunch suddenly felt completely normal — chat load and AI replies both fast.

I first blamed network, proxy, Cursor servers, HTTP/2, and Agent background processes. After a fuller investigation, the real anomaly was local:

```text
state.vscdb
```

That Cursor local SQLite database had grown to:

```text
52 GB
```

with `cursorDiskKV` at:

```text
2,731,416 rows
```

The decisive A/B test:

> Move the old `state.vscdb` aside and let Cursor create a fresh database.

Cursor recovered immediately. New Chat `hello` answered almost instantly.

This article records the full investigation.

---

## 1. Symptoms

The failure appeared right after a Mac reboot. Three patterns:

### 1.1 App opens, chat stays on Loading chats

No crash; the editor works; chat shows `Loading chats`. Sometimes history eventually appears; sometimes it hangs.

### 1.2 After chat UI appears, Agent still fails

New Chat sending `hello` still spins. So this is not only “slow history UI” — the Agent / chat request path is affected.

### 1.3 Many failed relaunches, then sudden recovery

```text
reboot Mac → start Cursor → Loading chats → send message hangs
→ force quit → reopen → still broken → repeat many times
→ one relaunch suddenly fine → chat fast → Agent fast
```

That looks like flaky network or server. Later evidence pointed at the local state database.

---

## 2. Confirm Cursor has fully quit

Before touching the DB:

```bash
ps aux | grep -i "[C]ursor"
```

After a full quit, only macOS helpers like `CursorUIViewService` may remain — that is **not** the Cursor IDE. Ignore it.

---

## 3. The anomaly: `state.vscdb` ≈ 52 GB

macOS global state directory:

```text
~/Library/Application Support/Cursor/User/globalStorage/
```

```bash
ls -lah "$HOME/Library/Application Support/Cursor/User/globalStorage/"
```

Notable sizes:

```text
conversation-search.db       24M
state.vscdb                  52G
state.vscdb-shm              32K
state.vscdb-wal             4.7M
```

Whole `globalStorage` ≈ 58 GB. Contrast: `workspaceStorage` ≈ 294 MB, Cursor Cache ≈ 41 MB. Almost all bloat is `state.vscdb`.

---

## 4. What is `state.vscdb`?

Cursor follows a VS Code / Electron architecture and persists app state in SQLite. Tables on this machine:

```bash
sqlite3 "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
  "SELECT name FROM sqlite_master WHERE type='table';"
```

```text
ItemTable
cursorDiskKV
composerHeaders
```

---

## 5. Full `integrity_check` is a bad first step

```bash
sqlite3 ".../state.vscdb" "PRAGMA integrity_check;"
```

ran with no output for a long time until Ctrl+C. That does **not** prove corruption — a 50+ GB scan can simply be slow. Prefer row counts and page stats first.

---

## 6. Row counts

```sql
SELECT 'ItemTable', COUNT(*) FROM ItemTable
UNION ALL
SELECT 'cursorDiskKV', COUNT(*) FROM cursorDiskKV
UNION ALL
SELECT 'composerHeaders', COUNT(*) FROM composerHeaders;
```

```text
ItemTable              976
cursorDiskKV      2,731,416
composerHeaders        1048
```

`cursorDiskKV` is orders of magnitude larger.

---

## 7. Real data vs freelist “virtual fat”

```bash
sqlite3 ".../state.vscdb" "PRAGMA page_size; PRAGMA page_count; PRAGMA freelist_count;"
```

```text
page_size       4096
page_count      13551257
freelist_count  2208
```

`13551257 × 4096 ≈ 51.69 GiB` matches the on-disk 52 GB. Freelist ≈ 8.6 MiB (~0.016%). This is **not** an empty shell that forgot `VACUUM` — most pages are in use.

---

## 8. `ItemTable` cannot explain 52 GB

Largest `ItemTable` values were under ~759 KB. With 976 rows, suspicion concentrates on `cursorDiskKV` (`key TEXT`, `value BLOB`, 2.73M rows).

---

## 9. Not an isolated case

Cursor Community Forum reports include ~30 GB / ~1.96M `cursorDiskKV` rows (heavy `bubbleId` / `agentKv` / `checkpointId`) and ~96 GB cases that keep growing with long Agent use. Support notes mention Agent self-fork / full transcript copies in a few long chats.

---

## 10. Agent transcripts on disk are tiny by comparison

```bash
find "$HOME/.cursor/projects" -type f -path "*/agent-transcripts/*.jsonl" 2>/dev/null | wc -l
du -sh "$HOME/.cursor/projects"
```

```text
1015 JSONL files
~/.cursor/projects ≈ 728 MB
```

~728 MB vs ~52 GB (~70×). The DB is not “just because I chat a lot.” JSONL is extra insurance, not a full UI / index restore.

---

## 11. Decisive A/B: fresh DB

With Cursor fully quit, **move** (do not delete):

```bash
cd "$HOME/Library/Application Support/Cursor/User/globalStorage"
mkdir -p state-vscdb-backup
for f in state.vscdb state.vscdb-shm state.vscdb-wal; do
  [ -e "$f" ] && mv "$f" state-vscdb-backup/
done
```

Relaunch → new DB → New Chat → `hello` → **near-instant**. Unchanged: Mac, network, install, account, model, project. Changed: old 52 GB DB → new DB. Strongest causal evidence in this investigation.

---

## 12. Why did it “suddenly work” before?

A 52 GB SQLite file is not read end-to-end on every launch. Access involves page cache, FS cache, chat index, KV queries, Agent init, conversation search, WAL checkpoint, multiple Electron/Agent processes. Failure can be intermittent (cold start / blocked query / failed init), then fast after cache hits. Force-quit is not a real fix.

---

## 13. Restoring the old DB can also start fast

After proving the new DB works, restoring the old DB again started quickly. That does **not** contradict the A/B test. It means the failure mode can be stateful / cache / init dependent — not a simple “DB > 50 GB ⇒ every launch fails.” The 52 GB file remains abnormal and still needs a cleanup plan. “Suddenly normal” ≠ “DB healed itself.”

---

## 14. `Developer: GC Agent KV Blobs`

Official-ish maintenance for orphaned Agent KV. Orphans can go; live data referenced by huge chats stays. A 96 GB case reportedly reclaimed only ~18% because most copies were still live. GC is not “52 GB → 500 MB” in one click.

---

## 15. GC / VACUUM need lots of free disk

Compaction may rewrite nearly a full DB copy (sometimes approaching 2× free space). Community reports of Disk Full during “Compacting Storage” on ~30 GB DBs. Do not `VACUUM` a multi-ten-GB DB when the disk is almost full.

---

## 16. Fastest safe recovery if Cursor is unusable

1. Quit fully (`Cmd+Q`); confirm no IDE processes.
2. **Move** `state.vscdb` + `-wal` + `-shm` aside (not delete).
3. Relaunch so Cursor creates a small DB and you can work.
4. Keep the backup; old chat index may not appear in the new DB.

---

## 17. If you still want old chats

```text
Quit → keep old DB → confirm agent-transcripts
  → Export Chat for anything important
  → GC Agent KV Blobs → Quit → re-check size/performance
```

If still huge: Export → delete a few monster long chats → GC → Quit.

---

## 18. Avoid blind SQL DELETE

```sql
DELETE FROM cursorDiskKV WHERE key LIKE 'agentKv:%';
-- bubbleId / checkpointId ...
VACUUM;
```

May free disk and destroy chat data. Users have reported loss. Not a first option if history matters.

---

## 19. Evidence chain

```text
Mac reboot → Loading chats → Agent spin
→ blamed network/HTTP2/service
→ globalStorage → state.vscdb = 52 GB
→ 13,551,257 pages / freelist 2208 → real data, not empty freelist
→ ItemTable 976 / max value < 1 MB
→ cursorDiskKV 2,731,416 → main suspect
→ 1015 transcripts / 728 MB → not “chat volume alone”
→ move old DB → new DB → hello instant
```

---

## 20. Judgment

Not “install corrupted” and not “API unreachable only.” Better fit: local Agent/Composer state accumulated until `state.vscdb` / `cursorDiskKV` reached abnormal scale and hurt cold start / history restore / Agent init. A clean DB restored instant replies. When you see Loading chats + Agent spin + intermittent recovery after reboot, check `state.vscdb` as well as the network.

---

## 21. Daily monitoring

```bash
du -h "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
sqlite3 ".../state.vscdb" "SELECT COUNT(*) FROM cursorDiskKV;"
```

Act when size climbs through multi-GB into tens of GB. Prefer new chats over one endless self-forking thread.

---

## 22. Redact API keys

`ps` may show `--api-key`. Redact before posting. Rotate credentials if you already leaked a token.

---

## Summary

The surprise was not “Cursor has a 52 GB SQLite file.” It was how much a **local DB** can look like a **network** failure: Loading chats, Agent silence, many failed relaunches, sudden fast recovery. The chain that settled direction:

```text
52 GB state.vscdb + 2.73M cursorDiskKV + near-zero freelist + fresh DB → instant hello
```

First commands worth running:

```bash
du -h "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
sqlite3 "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
  "SELECT COUNT(*) FROM cursorDiskKV;"
sqlite3 "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
  "PRAGMA page_size; PRAGMA page_count; PRAGMA freelist_count;"
```

---

## Appendix: paste-ready Agent context

See also [AGENT_CONTEXT.md](AGENT_CONTEXT.md). The full Chinese appendix block is preserved verbatim in [zh/CASE_STUDY.md](zh/CASE_STUDY.md).
