# cursor-state-vscdb

[中文](README.zh.md)

## Overview

This repository keeps the full original case study intact and provides a read-only diagnosis script and guides for macOS Cursor IDE hangs caused by large `state.vscdb` SQLite databases. Loading chats or Agent hangs after a reboot can be a local SQLite issue rather than just a network problem.

## First steps

Run [`./scripts/diagnose.sh`](scripts/diagnose.sh) (read-only); read the full case; if the IDE is stuck and the DB is tens of GB, quit Cursor and follow the emergency `mv` in [How to](docs/02-how-to.md) (prefer move over delete).

## Documentation

- Full case study: [English](docs/CASE_STUDY.md) and [中文原文（勿删勿砍）](docs/zh/CASE_STUDY.md)
- Principles: [docs/01-principles.md](docs/01-principles.md)
- How to: [docs/02-how-to.md](docs/02-how-to.md)
- Daily care: [docs/03-daily-care.md](docs/03-daily-care.md)
- Read-only diagnose script: [`scripts/diagnose.sh`](scripts/diagnose.sh)
- Command reference: [docs/DIAGNOSTIC_COMMANDS.md](docs/DIAGNOSTIC_COMMANDS.md)
- Agent paste context: [docs/AGENT_CONTEXT.md](docs/AGENT_CONTEXT.md)
- Forum peers and tools: [docs/RELATED.md](docs/RELATED.md)
- Preserve rule: [docs/PRESERVE.md](docs/PRESERVE.md)

## Snapshot

```text
state.vscdb           ≈ 52 GB (Cursor 3.22.7)
cursorDiskKV          2,731,416 → 2,731,751 after GC
freelist              2,208 → 186 pages post-GC
A/B: move old DB aside → fresh DB → hello ≈ instant (restore intermittent)
GC Agent KV Blobs     >1h; WAL peak ≈52 GB; free dipped ≈18 GiB
page reclaim          ≈119 MiB (≈0.23%); main file still ≈52 GB
key rows              ≈98.4% bubbleId / agentKv / checkpointId
agent-transcripts     ≈1015 files / ~728 MB
```

## Usage

```bash
git clone https://github.com/Xuzhen-Li/cursor-state-vscdb.git
cd cursor-state-vscdb
./scripts/diagnose.sh
```

## Figures

- [Storage layout](figures/schematic/storage-layout/preview.png): `state.vscdb` vs transcripts
- [Recovery flow](figures/schematic/recovery-flow/preview.png): quit, `mv` aside, fresh DB (optional Export/GC)
- [Size compare](figures/charts/size-compare/preview.png): DB vs transcripts, workspace, cache (log scale)
- [KV shape](figures/charts/kv-shape/preview.png): table row magnitudes (log scale)

## License

MIT. Copyright (c) 2026 Xuzhen Li.
