# cursor-state-vscdb

[English](README.md)

## 概述

本仓库完整保留原始案例，并提供只读诊断脚本和操作指南，用于排查因 `state.vscdb` 本地 SQLite 数据库体积过大导致的 macOS Cursor IDE 卡死问题。重启后聊天加载或 Agent 卡死可能是一个本地 SQLite 问题，而不仅仅是网络故障。

## 第一步

运行 [`./scripts/diagnose.sh`](scripts/diagnose.sh) (只读)；阅读完整案例；如果 IDE 卡住且数据库达到几十 GB，请退出 Cursor 并按照 [怎么做](docs/02-how-to.md) 中的紧急 `mv` 步骤操作（建议移动而不是删除）。

## 文档

- 完整案例：[English](docs/CASE_STUDY.md) 与 [中文原文（勿删勿砍）](docs/zh/CASE_STUDY.md)
- 原理：[docs/01-principles.md](docs/01-principles.md)
- 怎么做：[docs/02-how-to.md](docs/02-how-to.md)
- 日常：[docs/03-daily-care.md](docs/03-daily-care.md)
- 只读诊断脚本：[`scripts/diagnose.sh`](scripts/diagnose.sh)
- 命令参考：[docs/DIAGNOSTIC_COMMANDS.md](docs/DIAGNOSTIC_COMMANDS.md)
- Agent 粘贴上下文：[docs/AGENT_CONTEXT.md](docs/AGENT_CONTEXT.md)
- 论坛同行与工具：[docs/RELATED.md](docs/RELATED.md)
- 保护规则：[docs/PRESERVE.md](docs/PRESERVE.md)

## 案例快照

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

## 用法

```bash
git clone https://github.com/Xuzhen-Li/cursor-state-vscdb.git
cd cursor-state-vscdb
./scripts/diagnose.sh
```

## 图表

- [Storage layout](figures/schematic/storage-layout/preview.png)：`state.vscdb` 对比 transcripts
- [Recovery flow](figures/schematic/recovery-flow/preview.png)：退出，`mv` 移走，全新数据库（可选 Export/GC）
- [Size compare](figures/charts/size-compare/preview.png)：数据库对比 transcripts、workspace、cache（对数坐标）
- [KV shape](figures/charts/kv-shape/preview.png)：表行数数量级（对数坐标）

## 许可证

MIT。Copyright (c) 2026 Xuzhen Li。
