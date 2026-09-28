# Related projects and forum threads

## Cursor Community Forum (closest to this case)

Official forum reports that match oversized `state.vscdb` / `cursorDiskKV`, Loading chats, GC/compaction, or move-aside recovery. Read them for staff replies and other users’ numbers; this repo’s measurements stay in [CASE_STUDY.md](CASE_STUDY.md).

| Thread | Why it matters here |
|--------|---------------------|
| [Best practices with state.vscdb and state.vscdb.backup](https://forum.cursor.com/t/best-practices-with-state-vscdb-and-state-vscdb-backup-in-cursor/156848) | Known unbounded `cursorDiskKV`; VACUUM / SQL cleanup caveats; Loading Chat risk |
| [State.vscdb grew from 3.1 GB → 97 GB (macOS)](https://forum.cursor.com/t/state-vscdb-grew-from-3-1-gb-97-gb-macos/166013) | Extreme growth; staff: prefer Delete Old Chats / GC, do not delete/rename DB lightly; transcripts ≪ SQLite |
| [macOS: 12.4 GB state.vscdb + 12.2 GB backup](https://forum.cursor.com/t/macos-state-vscdb-grew-to-12-4-gb-and-state-vscdb-backup-grew-to-12-2-gb-on-a-256-gb-macbook-air-seeking-safe-remediation-guidance/162623) | `cursorDiskKV` dominates; safe `state.vscdb.backup` reclaim; GC guidance |
| [Cursor using 231 GB on Mac (state.vscdb ~188 GB)](https://forum.cursor.com/t/cursor-is-using-231-gb-on-my-mac-i-guess-ive-been-building-an-operating-system-without-knowing-it/165602) | Same culprit path; backup delete + GC + Delete Old Chats; avoid wiping main DB |
| [State.vscdb grows to 30GB (bubbleId / agentKv)](https://forum.cursor.com/t/state-vscdb-grows-to-30gb-due-to-bubbleid-agentkv-entries/167641) | Compacting needs ~1–2× free disk; when GC fails, staff suggest **mv aside** (not rm) |
| [Cursor state.vscdb growing at 1 GB/day](https://forum.cursor.com/t/cursor-state-vscdb-growing-at-1-gb-in-a-day/151747) | Unbounded KV growth; rename warning → Loading Chat |
| [Deleting global state.vscdb → infinite Loading Chat](https://forum.cursor.com/t/deleting-global-state-vscdb-causes-infinite-loading-chat-in-projects-history-not-recoverable-without-corrupted-backup/153220) | Why “delete the DB” advice is dangerous for history UI |
| [How to remove local, archived chats?](https://forum.cursor.com/t/how-to-remove-local-archived-chats/158574) | Supported: Delete Old Chats… then GC Agent KV Blobs |
| [Fix the Memory leaks plz](https://forum.cursor.com/t/fix-the-memory-leaks-plz/164715) | History pile-up; GC path; last-resort `mv state.vscdb` aside after Quit |

Do **not** paste raw `ps` lines from those threads (or your machine) into issues — they may contain `--api-key`. Redact first.

## Peer tools (inspiration only)

We studied public READMEs and rewrote our own guides/scripts. Links for credit and further reading:

| Project | Useful idea |
|---------|-------------|
| [zhengchenliang/cursor-clean](https://github.com/zhengchenliang/cursor-clean) | Layered diagnose → configure → clean → repair; quit before DB ops |
| [Miks221/cursor-db-slim](https://github.com/Miks221/cursor-db-slim) | Estimate / dry-run before apply; timestamped backups |
| [shaun3141/CursorData-SDK](https://github.com/shaun3141/CursorData-SDK) | Structured view of `cursorDiskKV` |
| [MushroomSquad/cursor-export](https://github.com/MushroomSquad/cursor-export) | Export composer chats before destructive recovery |
| [Stan370/cursor-history-tools](https://github.com/Stan370/cursor-history-tools) | Search / recover history from local SQLite |
| [jeziellopes/vscdb-fix](https://github.com/jeziellopes/vscdb-fix) | Index vs on-disk session files (VS Code Copilot; related file name) |
| [456wyc/cursor-flash](https://github.com/456wyc/cursor-flash) | Inspect / reclaim `state.vscdb` space |
| [Aiweline/codex-cursor-cleaner](https://github.com/Aiweline/codex-cursor-cleaner) | Broader clean of oversized local AI DBs |

This repo’s case numbers (52 GB, 2.73M rows, freelist 2208, A/B hello) are from the author’s machine — see [CASE_STUDY.md](CASE_STUDY.md) / [zh/CASE_STUDY.md](zh/CASE_STUDY.md).
