# cursor-state-vscdb

[中文](README.zh.md)

After a reboot, Cursor on my Mac hung on "Loading chats" and the Agent would not reply to a plain `hello`. It looked like a network issue, but it was not: Cursor's local SQLite database, `state.vscdb`, had grown to about 52 GB. Moving that file aside so Cursor could create a fresh one restored `hello` replies immediately.

This repository contains the full write-up of that incident, a script that inspects your own file without writing to it, and the steps I used to get Cursor working again without losing old data.

## Check your own file

```bash
git clone https://github.com/Xuzhen-Li/cursor-state-vscdb.git
cd cursor-state-vscdb
./scripts/diagnose.sh
```

The script never writes to the database. It prints the file size, table row counts, and page and freelist counts. It requires `bash`; row and page counts also require the `sqlite3` CLI (without it, only file sizes are shown).

How it opens the file depends on whether Cursor is running (checked via `pgrep`; set `CURSOR_DIAG_OPEN=immutable` or `CURSOR_DIAG_OPEN=readonly` to override):

- Cursor closed and no leftover `state.vscdb-wal`: opens the file as `file:…?mode=ro&immutable=1`. SQLite creates no side files. Immutable mode ignores any `-wal` file, so if Cursor is actually running, the numbers may be out of date.
- Cursor closed but `state.vscdb-wal` is non-empty (which happens after a crash or force-quit): runs `sqlite3 -readonly` so the changes still in the `-wal` are counted, and prints why.
- Cursor running: runs `sqlite3 -readonly`. Because the Cursor database uses WAL mode, SQLite may create or update `state.vscdb-wal` and `state.vscdb-shm` alongside it.

Default file locations (checked automatically on macOS and Linux):

| System | Path |
|--------|------|
| macOS | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` |
| Linux | `~/.config/Cursor/User/globalStorage/state.vscdb` |
| Windows | `%APPDATA%\Cursor\User\globalStorage\state.vscdb` (no default: set `CURSOR_STATE_DB`, also under WSL) |

For any other location:

```bash
CURSOR_STATE_DB=/full/path/to/state.vscdb ./scripts/diagnose.sh
```

Quit Cursor first if you want exact numbers, since Cursor writes to the file while running. After a normal quit, `-wal` is usually empty and no side files are created; after a crash, the script reads the leftover `-wal` with `-readonly`, which may create `state.vscdb-shm`.

## If Cursor is stuck right now

If the file is tens of GB and Cursor will not load chats, quit Cursor, then move `state.vscdb` along with its `-wal` and `-shm` files into a backup folder. Do not delete them. Cursor creates a new empty file on the next startup. Exact commands are in [How to](docs/02-how-to.md), section 2.

## What I measured

```text
state.vscdb           ≈ 52 GB (Cursor 3.22.7)
cursorDiskKV rows     2,731,416 → 2,731,751 after GC
freelist pages        2,208 → 186 after GC
A/B test              old DB moved aside → new DB → hello ≈ instant (old DB put back: also started fast that time; the failure comes and goes)
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
- [Size compare](figures/charts/size-compare/preview.png): the DB compared against transcripts, workspace, and cache (log scale)
- [KV shape](figures/charts/kv-shape/preview.png): row counts per table (log scale)

## License

MIT. Copyright (c) 2026 Xuzhen Li.
