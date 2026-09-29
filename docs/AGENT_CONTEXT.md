# Agent handoff (read-only first)

Paste the block below into a local Agent when continuing analysis on the same machine. Do not start from network guesses.

```text
I am debugging an oversized local IDE state database. Use the facts below; do not blame the network first.

Symptoms (Mac reboot):
1. App starts; chat stays on Loading chats.
2. Even after UI loads, New Chat "hello" spins with no reply.
3. Many force-quits fail; one relaunch once recovered and felt fast (intermittent).
4. A/B: move state.vscdb (+wal/shm) aside → fresh DB → hello instant; restoring old DB can hang again only intermittently.
5. App can work again now, but the old DB is still huge — do not treat that as "fixed forever."

Version: Cursor ~3.22.7 (when GC was measured).

Confirmed paths / sizes (pre-GC):
~/Library/Application Support/Cursor/User/globalStorage/state.vscdb ≈ 52 GB
globalStorage ≈ 58 GB; workspaceStorage ≈ 294 MB; Cache ≈ 41 MB

SQLite tables: ItemTable, cursorDiskKV, composerHeaders
Rows pre-GC: ItemTable=976; cursorDiskKV=2,731,416; composerHeaders=1,048
Rows post-GC: ItemTable=985; cursorDiskKV=2,731,751; composerHeaders=1,048
cursorDiskKV: key TEXT, value BLOB

Pages pre-GC: page_size=4096; page_count=13,551,257; freelist_count=2,208
→ ~51.69 GiB pages; freelist ~8.6 MiB (~0.016%). Not empty freelist bloat.
Pages post-GC: page_count=13,520,717 (−30,540 ≈ 119.3 MiB ≈ 0.23%); freelist_count=186 (~762 KB).
Main file still ≈52 GB. Log note: 0 deleted (16 errors) on reference walk — trust page_count.

ItemTable max value ~759 KB — cannot explain 52 GB. Main suspect: cursorDiskKV.

~/.cursor/projects has ~1015 agent-transcripts/*.jsonl; whole projects dir ~728 MB (~70× smaller than the DB).

GC Agent KV Blobs (not manual DELETE, not VACUUM): Compacting Storage >1h.
WAL: few MB → ~52G → checkpoint ~4.3MB. Free disk dipped to ~18 GiB (APFS free once jumped 18→66 GiB while WAL still ~52G — purgeable/system reclaim inference, not proven Cursor freed 48GB). CPU high then idle.

Key prefix counts post-GC (ROWS only; byte GiB NOT measured yet):
bubbleId 2,029,436 (~74.29%); agentKv 653,694 (~23.93%); checkpointId 4,659 (~0.17%);
sum 2,687,789 / 2,731,751 ≈ 98.39%.

Pending (unrun / do not invent results):
SELECT CASE WHEN key LIKE 'bubbleId:%' THEN 'bubbleId' WHEN key LIKE 'agentKv:%' THEN 'agentKv' WHEN key LIKE 'checkpointId:%' THEN 'checkpointId' ELSE 'other' END AS kind, COUNT(*) AS n, SUM(length(value)) AS bytes FROM cursorDiskKV GROUP BY 1 ORDER BY bytes DESC;

Same-day later: startup still scanned ~903 agent headers; extension force-quit once — consistent with still-huge DB; does not overturn page counts.

Official staff order Export → Delete Old Chats… → GC → Cmd+Q cites forum (e.g. globalStorage 61.1GB thread) but Delete Old Chats is UNTESTED locally — do not invent outcomes.
Second GC is pointless while freelist is tight and live data dominates.

Do NOT: DELETE bubbleId/agentKv/checkpointId; rm state.vscdb; expect VACUUM to shrink (freelist empty); blind second GC.

Forum parallels: 30–96+ GB state.vscdb; heavy bubbleId / agentKv / checkpointId; GC Agent KV Blobs; self-fork transcript copies; compaction needs large free disk; WAL can ≈ main DB.

Your tasks (analysis first, no destructive deletes):
1. Run the SUM(length(value)) key-class weighing (slow).
2. Map heaviest composers/chats when possible.
3. Prefer official Delete Old Chats + GC / supported maintenance after Export.
4. If chats must be deleted, identify the largest ones and ask me to choose.
5. Keep existing ~/.cursor/projects agent-transcripts.
6. Do not DELETE FROM cursorDiskKV / rm state.vscdb / VACUUM without explicit impact + confirmation.
7. Quit the IDE completely before any DB write/move.
8. Before compact/VACUUM, confirm free disk ≈ DB size (WAL peak risk).
9. Do not break a currently bootable install.

First output: (A) diagnostic plan, (B) read-only SQL to run, (C) how you will find the heaviest chats, (D) safest cleanup path. No destructive deletes without confirmation.
```
