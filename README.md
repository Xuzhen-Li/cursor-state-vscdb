# cursor-state-vscdb

**Loading chats** / Agent hang after reboot can be a **local** SQLite problem: a multi-ten-GB `state.vscdb`, not (only) the network.

This repository keeps the **full original case study intact** and adds short guides plus a read-only diagnose script.

## In 3 minutes: which door?

| You need… | Open |
|-----------|------|
| Why a local DB can look like a network outage | [Principles](docs/01-principles.md) |
| Commands to measure size / recover safely | [How to](docs/02-how-to.md) |
| Weekly size check and habits | [Daily care](docs/03-daily-care.md) |
| Full incident write-up (measurements, A/B, community) | [Full case study (EN)](docs/CASE_STUDY.md) · [完整中文原文](docs/zh/CASE_STUDY.md) |

Do not delete or shorten the case-study files. See [docs/PRESERVE.md](docs/PRESERVE.md).

## Guides and tools

| Doc | Role |
|-----|------|
| [docs/01-principles.md](docs/01-principles.md) | Mental model only |
| [docs/02-how-to.md](docs/02-how-to.md) | Diagnose + emergency `mv` + GC order |
| [docs/03-daily-care.md](docs/03-daily-care.md) | Weekly two-minute check |
| [scripts/diagnose.sh](scripts/diagnose.sh) | One-shot read-only check |
| [docs/AGENT_CONTEXT.md](docs/AGENT_CONTEXT.md) | Paste-ready context for a local Agent |
| [docs/RELATED.md](docs/RELATED.md) | Related tools (inspiration, not copies) |
| [docs/DIAGNOSTIC_COMMANDS.md](docs/DIAGNOSTIC_COMMANDS.md) | Short command checklist |

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
