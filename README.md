# cursor-state-vscdb

**Loading chats** / Agent hang after reboot can be a **local** SQLite problem: a multi-ten-GB `state.vscdb`, not (only) the network.

This repository keeps the **full original case study intact** and adds short guides, a read-only diagnose script, and figures.

| Door | Go here |
|------|---------|
| Full incident write-up (English) | [docs/CASE_STUDY.md](docs/CASE_STUDY.md) |
| **完整中文原文（勿删勿砍）** | [docs/zh/CASE_STUDY.md](docs/zh/CASE_STUDY.md) |
| Why it behaves like a network outage | [docs/01-principles.md](docs/01-principles.md) |
| What to run / how to recover | [docs/02-how-to.md](docs/02-how-to.md) |
| Weekly habits | [docs/03-daily-care.md](docs/03-daily-care.md) |
| One-shot read-only check | [scripts/diagnose.sh](scripts/diagnose.sh) |
| Agent paste context | [docs/AGENT_CONTEXT.md](docs/AGENT_CONTEXT.md) |
| Related tools (inspiration) | [docs/RELATED.md](docs/RELATED.md) |

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

If the IDE is unusable and the DB is tens of GB, see emergency `mv` steps in [docs/02-how-to.md](docs/02-how-to.md). Prefer move over delete.

## Figures

Schematics and charts live under `figures/` (added in follow-up PRs). Guides reference them once previews land.

## License

MIT. Copyright (c) 2026 Xuzhen Li.
