# Related projects (inspiration only)

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

This repo’s case numbers (52 GB, 2.73M rows, freelist 2208, A/B hello) are from the author’s machine — see [CASE_STUDY.md](CASE_STUDY.md).
