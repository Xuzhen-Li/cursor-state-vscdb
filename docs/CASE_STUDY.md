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

That command ran with no output for a long time until Ctrl+C. That does **not** prove corruption — a 50+ GB scan can simply be slow. Prefer row counts and page stats first.

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

## 14. Measured run: `Developer: GC Agent KV Blobs`

After the A/B test I ran Cursor’s own maintenance command (not hand-written `DELETE`, not manual `VACUUM`) on **Cursor 3.22.7**:

```text
Developer: GC Agent KV Blobs
```

I did **not** first run the staff-suggested order often cited on the forum:

```text
Export → Developer: Delete Old Chats… → GC Agent KV Blobs → Cmd+Q
```

(See e.g. [macOS globalStorage 61.1GB](https://forum.cursor.com/t/macos-globalstorage-61-1gb/171211).) **Delete Old Chats is still untested on this machine.** Every number below is from a **GC-only** path.

GC removes **orphaned** Agent KV. Live data still referenced by long chats stays. It is not “52 GB → 500 MB in one click.”

---

## 15. During GC: WAL can match the main DB size

`Compacting Storage` ran for **more than one hour**. Observed ranges:

| Signal | During the run |
|--------|----------------|
| `state.vscdb-wal` | few MB → 31G → 45G → **≈52G**, then checkpoint → **≈4.3 MB** |
| APFS free space | ~32 → **18** → 66 → 69 → 122 GiB |
| CPU | ~91% → 97% → 70% → 4% → 0.2% |

Takeaways:

1. **WAL peak can ≈ main DB size (~52 GB).** Running GC/compact with only teens of GiB free is the same risk class as community Disk Full reports on ~30 GB DBs.
2. Free space once dipped to ~**18 GiB**, then rose again. At one point APFS free jumped ~18 → ~**66 GiB** while WAL was still ~**52G** — consistent with purgeable / system reclaim, **not** proof that Cursor had freed 48 GB of main-file data.
3. After checkpoint, WAL returned to a few MB; the main `state.vscdb` file stayed ~**52 GB**.

---

## 16. After GC: how much was actually reclaimed?

Trust SQLite pages over “the disk felt bigger”:

| Metric | Pre-GC | Post-GC | Δ |
|--------|--------|---------|---|
| ItemTable | 976 | 985 | +9 |
| cursorDiskKV | 2,731,416 | **2,731,751** | **+335** |
| composerHeaders | 1,048 | 1,048 | 0 |
| page_count | 13,551,257 | **13,520,717** | **−30,540** |
| freelist_count | 2,208 | **186** | −2,022 |

```text
−30,540 pages × 4096 ≈ 119.3 MiB ≈ 0.23% of the DB
```

So: one GC Agent KV Blobs run **did not** turn a 52 GB library into a small one. Pages fell by ~**119 MiB**; `cursorDiskKV` row count slightly **rose**; freelist got tighter (186 pages ≈ 762 KB).

Cursor logs noted something like **0 deleted (16 errors)** during the reference walk. The `page_count` drop is still real — **treat `page_count` as ground truth**, not the “0 deleted” phrasing alone.

With freelist this tight and live data dominating, a **blind second GC is pointless**.

---

## 17. Key classes: ~98.4% bubble / agentKv / checkpoint (row counts)

Post-GC prefix counts (**rows only; byte GiB per class not measured yet**):

| Prefix | Rows | Share of cursorDiskKV |
|--------|------|------------------------|
| `bubbleId` | 2,029,436 | ≈74.29% |
| `agentKv` | 653,694 | ≈23.93% |
| `checkpointId` | 4,659 | ≈0.17% |
| **Sum** | **2,687,789 / 2,731,751** | **≈98.39%** |

Strong association with Agent/Chat KV prefixes. But **rows ≠ bytes**. Which class owns tens of GiB, and which chats own those bytes, is **still unknown**.

Planned read-only weighing SQL (**not run / results not claimed here**):

```sql
SELECT
  CASE
    WHEN key LIKE 'bubbleId:%' THEN 'bubbleId'
    WHEN key LIKE 'agentKv:%' THEN 'agentKv'
    WHEN key LIKE 'checkpointId:%' THEN 'checkpointId'
    WHEN key LIKE 'composerData:%' THEN 'composerData'
    ELSE 'other'
  END AS kind,
  COUNT(*) AS n,
  SUM(length(value)) AS bytes
FROM cursorDiskKV
GROUP BY 1
ORDER BY bytes DESC;
```

Until `SUM(length(value))` and per-chat aggregation exist, do not claim a final byte-level root cause.

---

## 18. Explicit do-nots

1. Do **not** `DELETE` `bubbleId` / `agentKv` / `checkpointId` keys.
2. Do **not** `rm state.vscdb` as “cleanup” — emergency recovery uses **`mv` aside** (next section).
3. Do **not** expect `VACUUM` to shrink when freelist is already empty-ish (186 pages here).
4. Do **not** blind-run a second GC while freelist is tight and live data dominates.
5. Prefer staff order **Export → Delete Old Chats… → GC → Cmd+Q**, but **Delete Old Chats remains untested locally** — this write-up invents no results for it.

Peer tools / gists that **SQL DELETE then VACUUM** conflict with this case when history still matters — treat as high risk, not a default prescription.

---

## 19. Fastest safe recovery if Cursor is unusable

1. Quit fully (`Cmd+Q`); confirm no IDE processes (`ps` — ignore `CursorUIViewService`).
2. **Move** (do not delete) `state.vscdb` + `-wal` + `-shm` aside:

```bash
cd "$HOME/Library/Application Support/Cursor/User/globalStorage"
mkdir -p state-vscdb-backup
for f in state.vscdb state.vscdb-shm state.vscdb-wal; do
  [ -e "$f" ] && mv "$f" state-vscdb-backup/
done
```

3. Relaunch → fresh DB → New Chat → `hello` → **near-instant** (measured).
4. Keep the backup; old chat index may not appear in the new DB.

Restoring the old file can bring the hang back **only intermittently** — same stateful / cache / init dependence as before. Fast start ≠ healed DB.

---

## 20. If you still want old chats (conservative order)

Staff-shaped path (**Delete Old Chats untested here**):

```text
Quit → keep old DB → confirm agent-transcripts
  → Export Chat for anything important
  → Developer: Delete Old Chats…   ← not measured locally
  → Developer: GC Agent KV Blobs
  → Quit → re-check page_count / freelist / du
```

This measured GC (without Delete Old Chats) reclaimed only ~**119 MiB**, while WAL peak ≈ main DB. Reserve ~DB-sized free disk before compact. If still tens of GB afterward, suspect **live** Agent/Chat KV, not orphan empty-shell fat.

---

## 21. Avoid blind SQL DELETE

```sql
DELETE FROM cursorDiskKV WHERE key LIKE 'agentKv:%';
-- bubbleId / checkpointId ...
VACUUM;
```

May free disk and destroy chat data. Users have reported loss. With ~**98.4%** of rows in those three prefixes, blind delete ≈ gutting Agent state. Not a first option if history matters.

---

## 22. Evidence chain (including measured GC)

```text
Mac reboot → Loading chats → Agent spin (intermittent recovery)
→ blamed network/HTTP2/service
→ state.vscdb ≈ 52 GB
→ page_count 13,551,257 / freelist 2,208 → real data
→ ItemTable 976 / max ~759 KB
→ cursorDiskKV 2,731,416
→ 1015 transcripts / 728 MB
→ mv old DB → new DB → hello instant
→ restore old DB → sometimes fast again (intermittent)
→ GC Agent KV Blobs (>1h)
→ WAL peak ≈52G; free dipped to ≈18 GiB
→ page_count −30,540 ≈ 119.3 MiB; freelist → 186
→ cursorDiskKV rows +335; main file still ≈52 GB
→ bubbleId+agentKv+checkpointId ≈ 98.39% of rows
→ byte GiB / Delete Old Chats: not measured yet
```

---

## 23. Judgment

Not “install corrupted” and not “API unreachable only.” Better fit:

> Local Agent/Composer state accumulated until `state.vscdb` / `cursorDiskKV` reached abnormal scale and is **strongly associated** with Loading chats / Agent hang. Measured GC shows the DB is still dominated by **live** KV; one orphan GC reclaimed ~0.23% of pages.

On this machine (Cursor **3.22.7**):

```text
state.vscdb        ≈ 52 GB (main file still ~that after GC)
cursorDiskKV       2,731,416 → 2,731,751
page_count         13,551,257 → 13,520,717 (≈ −119.3 MiB)
freelist_count     2,208 → 186
key prefixes       bubbleId / agentKv / checkpointId ≈ 98.4% of rows
agent transcripts  ≈ 1015 / 728 MB
```

Same day later: startup still scanned ~**903** agent headers; extension process force-quit once — consistent with a still-huge DB; **does not overturn** the page counts.

Strong association + live Agent/Chat KV dominance is fair. Final byte-level attribution waits on `SUM(length(value))` and per-chat aggregation.

---

## 24. Daily monitoring

```bash
du -h "$HOME/Library/Application Support/Cursor/User/globalStorage/"state.vscdb*
sqlite3 ".../state.vscdb" "SELECT COUNT(*) FROM cursorDiskKV;"
sqlite3 ".../state.vscdb" "PRAGMA page_size; PRAGMA page_count; PRAGMA freelist_count;"
```

Act when size climbs through multi-GB into tens of GB. Before GC/compact: **reserve free disk on the order of the main DB** (WAL peak ≈ DB here). Prefer new chats over one endless self-forking thread.

---

## 25. Redact API keys

`ps` may show `--api-key`. Redact `/Users/<USER>/`, `<PROJECT>`, never paste `crsr_…` or raw tokens. Rotate if already leaked.

---

## Summary

The surprise was not “Cursor has a 52 GB SQLite file.” It was how much a **local DB** can look like a **network** failure — including intermittent recovery. The chain that settled direction, reinforced by GC measurement:

```text
52 GB state.vscdb
+ ~2.73M cursorDiskKV
+ near-zero freelist (tighter after GC)
+ fresh DB → instant hello
+ one GC ≈ 119 MiB / 0.23% pages
+ ≈98.4% rows in bubbleId / agentKv / checkpointId
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

See [AGENT_CONTEXT.md](AGENT_CONTEXT.md) (updated with post-GC numbers). The full Chinese appendix block, including the measured GC facts, is in [zh/CASE_STUDY.md](zh/CASE_STUDY.md).

---

## Memo: chat entry points and third-party tools

- **Delete Old Chats…** is often placed before GC in staff replies; **not measured locally** — no invented reclaim numbers here.
- Forum peers (including 52GB-class + staff order): [RELATED.md](RELATED.md), especially [macOS globalStorage 61.1GB](https://forum.cursor.com/t/macos-globalstorage-61-1gb/171211).
- Third-party cleaners (memo only, not this repo’s prescription):
  - [vilaca/cursor-chat-cleaner](https://github.com/vilaca/cursor-chat-cleaner)
  - [zhengchenliang/cursor-clean](https://github.com/zhengchenliang/cursor-clean) and some gists: often **SQL DELETE then VACUUM** — conflicts with “do not blind-delete bubble/agentKv/checkpoint” when history matters.
- **Colima**: ~30GB under `~/.colima` on the same Mac is **unrelated** to Cursor `state.vscdb` — disk-accounting memo only.
