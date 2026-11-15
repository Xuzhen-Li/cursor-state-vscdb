# cursor-state-vscdb

[中文](README.zh.md)

After a reboot, Cursor on my Mac sat on "Loading chats" and the Agent would not answer a plain `hello`. It looked like a network problem. It was not: Cursor's local SQLite file, `state.vscdb`, had grown to about 52 GB. Moving that file aside and letting Cursor start a new one made `hello` come back at once.

This repo has the full write-up of that case, a read-only script to check your own file, and the steps I used to get Cursor working again without losing the old data.

## Check your own file

```bash
git clone https://github.com/Xuzhen-Li/cursor-state-vscdb.git
cd cursor-state-vscdb
./scripts/diagnose.sh
```

The script only reads. It prints the file size, table row counts, and page and freelist counts. It needs `bash`; the row and page counts also need the `sqlite3` command (without it you get the sizes only).

Where it looks by default:

| System | Path |
|--------|------|
| macOS | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` |
| Linux | `~/.config/Cursor/User/globalStorage/state.vscdb` |
| Windows | `%APPDATA%\Cursor\User\globalStorage\state.vscdb` (run the script from Git Bash or WSL with `CURSOR_STATE_DB` set) |

For any other location:

```bash
CURSOR_STATE_DB=/full/path/to/state.vscdb ./scripts/diagnose.sh
```

Quit Cursor first if you want the row counts to be exact; Cursor writes to the file while it runs.

## If Cursor is stuck right now

If the file is tens of GB and Cursor will not load chats, quit Cursor, then move `state.vscdb` and its `-wal` and `-shm` files into a backup folder. Do not delete them. Cursor makes a new empty file on the next start. The exact commands are in [How to](docs/02-how-to.md), section 2.

## What I measured

```text
state.vscdb           ≈ 52 GB (Cursor 3.22.7)
cursorDiskKV rows     2,731,416 → 2,731,751 after GC
freelist pages        2,208 → 186 after GC
A/B test              old DB moved aside → new DB → hello ≈ instant (old DB put back: works only some of the time)
GC Agent KV Blobs     over 1 h; WAL peaked ≈ 52 GB; free disk dropped to ≈ 18 GiB
space given back      ≈ 119 MiB (≈ 0.23%); file still ≈ 52 GB
row types             ≈ 98.4% of rows are bubbleId / agentKv / checkpointId
agent-transcripts     ≈ 1015 files, ~728 MB
```

## Files

- The full case: [English](docs/CASE_STUDY.md), [中文原文（勿删勿砍）](docs/zh/CASE_STUDY.md)
- [Why a local file can look like a network fault](docs/01-principles.md)
- [How to check and recover](docs/02-how-to.md)
- [Weekly check](docs/03-daily-care.md)
- [Command list](docs/DIAGNOSTIC_COMMANDS.md)
- [Text to paste to an AI agent helping you](docs/AGENT_CONTEXT.md)
- [Forum threads and other tools](docs/RELATED.md)
- [What must not be cut from the case study](docs/PRESERVE.md)

Figures:

- [Storage layout](figures/schematic/storage-layout/preview.png): `state.vscdb` next to the transcript files
- [Recovery flow](figures/schematic/recovery-flow/preview.png): quit, move the file aside, start fresh, then export or GC if you want
- [Size compare](figures/charts/size-compare/preview.png): the DB against transcripts, workspace and cache (log scale)
- [KV shape](figures/charts/kv-shape/preview.png): row counts per table (log scale)

## License

MIT. Copyright (c) 2026 Xuzhen Li.
