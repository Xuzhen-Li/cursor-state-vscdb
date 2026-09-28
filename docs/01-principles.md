# Principles: why a local SQLite file can look like a network outage

Keep the full incident narrative in [CASE_STUDY.md](CASE_STUDY.md) and [zh/CASE_STUDY.md](zh/CASE_STUDY.md). This page is the mental model only.

## What `state.vscdb` is

Cursor (VS Code / Electron lineage) stores long-lived UI and Agent state in SQLite under:

```text
~/Library/Application Support/Cursor/User/globalStorage/state.vscdb
```

Typical tables in this case:

| Table | Role (observed) |
|-------|-----------------|
| `ItemTable` | Small key/value workbench settings and caches |
| `cursorDiskKV` | Large BLOB store (`key TEXT`, `value BLOB`) for bubbles, agent KV, checkpoints, composer payloads |
| `composerHeaders` | Composer / chat headers (thousands, not millions) |

When `cursorDiskKV` holds millions of blobs, cold start, chat index load, and Agent init can stall — even though the editor shell opens.

## Real data vs “virtual fat”

SQLite file size ≈ `page_count × page_size`. If `freelist_count` is tiny (here ~0.016%), deleted-but-not-`VACUUM`’d free pages are **not** the story. The pages are in use.

## Why JSONL transcripts do not explain the 52 GB

`~/.cursor/projects/**/agent-transcripts/*.jsonl` can be hundreds of MB while `state.vscdb` is tens of GB. The DB also holds KV copies, bubbles, checkpoints, and other internal state. JSONL is insurance, not a full UI restore.

## Why symptoms look like the network

| You see | Easy wrong guess | Local mechanism |
|---------|------------------|-----------------|
| Loading chats | API / HTTP/2 | Index / KV read on a huge DB |
| Agent spins on `hello` | Model / proxy | Agent path waiting on state |
| Many relaunches fail, one works | Flaky server | Cache / init / lock timing on a huge DB |
| After recovery everything is fast | “Fixed itself” | Luck + cache; size still abnormal |

## A/B is the causal test

Same Mac, network, install, account, project — only swap the DB file. If a fresh `state.vscdb` makes `hello` instant, the old DB is implicated. Restoring the old DB and seeing a fast start later does **not** mean the old DB is healthy; intermittent paths still leave a 50 GB file as a bomb.

## GC is not a magic shrink

`Developer: GC Agent KV Blobs` removes **orphaned** KV. Live data still referenced by long / self-forked chats stays. Compaction can need free disk on the order of the DB size (sometimes approaching 2×). Do not `VACUUM` a multi-ten-GB DB on a nearly full disk.

## Borrowed ideas (rewritten, not copied)

Peer tools taught useful *shape*, not paste-ready code:

- Layered actions: read-only sense → safe clean → DB repair only after quit ([cursor-clean](https://github.com/zhengchenliang/cursor-clean) pattern).
- Dry-run / estimate before apply ([cursor-db-slim](https://github.com/Miks221/cursor-db-slim)).
- Typed view of `cursorDiskKV` ([CursorData-SDK](https://github.com/shaun3141/CursorData-SDK)).
- Export chats before destructive moves ([cursor-export](https://github.com/MushroomSquad/cursor-export)).

Our scripts and prose are original to this repo.
