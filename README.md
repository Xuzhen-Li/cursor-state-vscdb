# cursor-state-vscdb

**Loading chats** / Agent hang after reboot can be a **local** SQLite problem: a tens-of-GB `state.vscdb`, not only a network problem. Paths and scripts below target **macOS Cursor**.

This repository keeps the **full original case study intact** and adds short guides, a read-only diagnose script, and figures.

## In 3 minutes: which door?

| Door | 门 | Go here |
|------|----|---------|
| Full case study | 完整案例 | [English](docs/CASE_STUDY.md) · [中文原文（勿删勿砍）](docs/zh/CASE_STUDY.md) |
| Principles | 原理 | [docs/01-principles.md](docs/01-principles.md) |
| How to | 怎么做 | [docs/02-how-to.md](docs/02-how-to.md) |
| Daily care | 日常 | [docs/03-daily-care.md](docs/03-daily-care.md) |

**Tonight:** run [`./scripts/diagnose.sh`](scripts/diagnose.sh) (read-only) · read the full case · if the IDE is stuck and the DB is tens of GB, quit Cursor and follow emergency `mv` in [How to](docs/02-how-to.md) (prefer move over delete).

### Also / Tools

- Read-only one-shot: [`scripts/diagnose.sh`](scripts/diagnose.sh)
- Command reference: [docs/DIAGNOSTIC_COMMANDS.md](docs/DIAGNOSTIC_COMMANDS.md) (also linked from How to)
- Agent paste context: [docs/AGENT_CONTEXT.md](docs/AGENT_CONTEXT.md)
- Related tools (inspiration): [docs/RELATED.md](docs/RELATED.md)
- Preserve rule: [docs/PRESERVE.md](docs/PRESERVE.md)

## Snapshot from the case

```text
state.vscdb           ≈ 52 GB
cursorDiskKV          ≈ 2,731,416 rows
freelist              ≈ 8.6 MB (~0.016%)
agent-transcripts     ≈ 1015 files / ~728 MB
A/B: move old DB aside → fresh DB → New Chat "hello" ≈ instant
```

## Quick start

```bash
git clone https://github.com/Xuzhen-Li/cursor-state-vscdb.git
cd cursor-state-vscdb
./scripts/diagnose.sh
```

## Figures

- [Storage layout](figures/schematic/storage-layout/preview.png) — `state.vscdb` vs transcripts
- [Recovery flow](figures/schematic/recovery-flow/preview.png) — Path A keep DB / Path B `mv` bypass
- Charts (size / KV shape): landing in follow-up PRs

## License

MIT. Copyright (c) 2026 Xuzhen Li.
