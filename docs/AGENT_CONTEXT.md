# Agent handoff (read-only first)

Paste the block below into a local Agent when continuing analysis on the same machine. Do not start from network guesses.

```text
I am debugging an oversized local IDE state database. Use the facts below; do not blame the network first.

Symptoms (Mac reboot):
1. App starts; chat stays on Loading chats.
2. Even after UI loads, New Chat "hello" spins with no reply.
3. Many force-quits fail; one relaunch once recovered and felt fast.
4. App can work again now, but the old DB is still huge — do not treat that as "fixed forever."

Confirmed paths / sizes:
~/Library/Application Support/Cursor/User/globalStorage/state.vscdb ≈ 52 GB
globalStorage ≈ 58 GB; workspaceStorage ≈ 294 MB; Cache ≈ 41 MB

SQLite tables: ItemTable, cursorDiskKV, composerHeaders
Rows: ItemTable=976; cursorDiskKV=2,731,416; composerHeaders=1,048
cursorDiskKV: key TEXT, value BLOB

Pages: page_size=4096; page_count=13,551,257; freelist_count=2,208
→ ~51.69 GiB pages; freelist ~8.6 MiB (~0.016%). Not empty freelist bloat.

ItemTable max value ~759 KB — cannot explain 52 GB. Main suspect: cursorDiskKV.

~/.cursor/projects has ~1015 agent-transcripts/*.jsonl; whole projects dir ~728 MB (~70× smaller than the DB).

A/B: fully quit; move state.vscdb + wal + shm aside; relaunch; new DB; New Chat hello → instant. Restored old DB later; currently starts fast again. Oversized DB still needs handling.

Forum parallels: 30–96 GB state.vscdb; heavy bubbleId / agentKv / checkpointId; GC Agent KV Blobs; self-fork transcript copies; compaction needs large free disk.

Your tasks (analysis first, no destructive deletes):
1. Key-type distribution in cursorDiskKV.
2. Counts and approximate bytes for bubbleId, agentKv, checkpointId, composerData, etc.
3. Whether a few composers/chats dominate size.
4. Map composer/chat IDs to KV volume when possible.
5. Prefer official GC Agent KV Blobs / supported maintenance.
6. If chats must be deleted, identify the largest ones and ask me to choose.
7. Keep existing ~/.cursor/projects agent-transcripts.
8. Do not DELETE FROM cursorDiskKV / rm state.vscdb / VACUUM without explicit impact + confirmation.
9. Quit the IDE completely before any DB write/move.
10. Before compact/VACUUM, confirm free disk is enough.
11. Do not break a currently bootable install.

First output: (A) diagnostic plan, (B) read-only SQL to run, (C) how you will find the heaviest chats, (D) safest cleanup path. No destructive deletes without confirmation.
```
