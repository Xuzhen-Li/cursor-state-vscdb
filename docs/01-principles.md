# Principles: why a local SQLite file can look like a network outage

> **Door:** Principles · **Use when:** you want the mental model before touching files.  
> **Not this page:** full measurements and A/B narrative → [CASE_STUDY.md](CASE_STUDY.md) / [zh/CASE_STUDY.md](zh/CASE_STUDY.md). Commands → [02-how-to.md](02-how-to.md).

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

SQLite file size ≈ `page_count × page_size`. If `freelist_count` is tiny (here ~0.016%), free pages left by deletes that never ran `VACUUM` are **not** the story. The pages are in use.

## Why JSONL transcripts do not explain the 52 GB

`~/.cursor/projects/**/agent-transcripts/*.jsonl` can be hundreds of MB while `state.vscdb` is tens of GB. The DB also holds KV copies, bubbles, checkpoints, and other internal state. JSONL is insurance, not a full UI restore.

## Why symptoms look like the network

| You see | Easy wrong guess | Local mechanism |
|---------|------------------|-----------------|
| Loading chats | API / HTTP/2 | Index / KV read on a huge DB |
| Agent spins on `hello` | Model / proxy | Agent path waiting on state |
| Many relaunches fail, one works | Flaky server | Cache / init / lock timing on a huge DB |
| After recovery everything is fast | “Fixed itself” | Luck + cache; size still abnormal |

*Figure (TBD):* [figures/schematic/storage-layout/](../figures/schematic/storage-layout/) — where `state.vscdb` sits vs transcripts.

## A/B is the causal test

Same Mac, network, install, account, project — only swap the DB file. If a fresh `state.vscdb` makes `hello` instant, the old DB is implicated. Restoring the old DB and seeing a fast start later does **not** mean the old DB is healthy; intermittent paths still leave a 50 GB file as an ongoing risk.

## GC is not a magic shrink

`Developer: GC Agent KV Blobs` removes **orphaned** KV. Live data still referenced by long / self-forked chats stays. Compaction can need free disk on the order of the DB size (sometimes approaching 2×). Do not `VACUUM` a tens-of-GB DB on a nearly full disk.

## Borrowed ideas

Peer tools shaped the *layering* (sense → clean → repair); credit and links live in [RELATED.md](RELATED.md). Scripts and prose here are original.
