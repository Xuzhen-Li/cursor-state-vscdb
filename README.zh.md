# cursor-state-vscdb

[English](README.md)

我的 Mac 重启后，Cursor 一直卡在「Loading chats」，Agent 连一句 `hello` 都不回复。表面上看像网络故障，实际原因在于 Cursor 本地的 SQLite 文件 `state.vscdb` 已经膨胀到约 52 GB。将该文件移走并让 Cursor 新建数据库后，`hello` 立刻恢复响应。

本仓库记录了这次排查的完整过程、一个不写数据库的检查脚本，以及在不丢失旧数据的前提下恢复 Cursor 正常使用的方法。

## 检查你自己的文件

```bash
git clone https://github.com/Xuzhen-Li/cursor-state-vscdb.git
cd cursor-state-vscdb
./scripts/diagnose.sh
```

脚本不会向数据库写入任何内容，它会输出文件大小、各表行数、总页数和空闲页数。运行需要 `bash`；统计行数和页数还需要安装 `sqlite3` 命令（若未安装则仅显示文件大小）。

打开方式取决于 Cursor 是否正在运行（脚本通过 `pgrep` 判断；也可设置 `CURSOR_DIAG_OPEN=immutable` 或 `CURSOR_DIAG_OPEN=readonly` 手动指定）：

- Cursor 已退出，且没有残留的 `state.vscdb-wal`：以 `file:…?mode=ro&immutable=1` 打开，SQLite 不会生成附属文件。immutable 模式会忽略 `-wal` 文件，因此若 Cursor 实际仍在运行，读取到的数字可能是旧的。
- Cursor 已退出，但 `state.vscdb-wal` 非空（崩溃或强制退出后会出现这种情况）：改用 `sqlite3 -readonly`，将 `-wal` 中尚未合并的改动一并计入，并打印选择该模式的原因。
- Cursor 正在运行：使用 `sqlite3 -readonly` 打开。由于 Cursor 的数据库处于 WAL 模式，SQLite 可能会在同目录下新建或更新 `state.vscdb-wal` 与 `state.vscdb-shm`。

文件默认位置（脚本在 macOS 和 Linux 上自动查找）：

| 系统 | 路径 |
|------|------|
| macOS | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` |
| Linux | `~/.config/Cursor/User/globalStorage/state.vscdb` |
| Windows | `%APPDATA%\Cursor\User\globalStorage\state.vscdb`（无默认值，需设置 `CURSOR_STATE_DB`，WSL 下同样适用） |

文件位于其他路径时：

```bash
CURSOR_STATE_DB=/完整路径/state.vscdb ./scripts/diagnose.sh
```

Cursor 运行时会持续写入该文件，如需精确数字请先退出 Cursor。正常退出后 `-wal` 通常为空，不会产生附属文件；崩溃后脚本会用 `-readonly` 读取残留的 `-wal`，此时可能会生成 `state.vscdb-shm`。

## Cursor 现在就卡住了怎么办

如果文件已有几十 GB 且 Cursor 无法加载聊天记录：先退出 Cursor，再将 `state.vscdb` 及其同目录下的 `-wal`、`-shm` 文件移入备份文件夹，切勿删除。下次启动时 Cursor 会自动新建一个空文件。具体命令见 [怎么做](docs/02-how-to.md) 第 2 节。

## 实测数据

```text
state.vscdb           ≈ 52 GB (Cursor 3.22.7)
cursorDiskKV 行数     2,731,416 → GC 后 2,731,751
空闲页 freelist       2,208 → GC 后 186
A/B 对照              移走旧库 → 新库 → hello 几乎立刻回复（放回旧库：那次也很快启动；故障是间歇性的）
GC Agent KV Blobs     超过 1 小时；WAL 峰值 ≈ 52 GB；剩余磁盘降到 ≈ 18 GiB
回收空间              ≈ 119 MiB（≈ 0.23%）；文件仍 ≈ 52 GB
行类型                ≈ 98.4% 的行是 bubbleId / agentKv / checkpointId
agent-transcripts     ≈ 1015 个文件，约 728 MB
```

## 文件

- 完整案例：[English](docs/CASE_STUDY.md)、[中文原文（勿删勿砍）](docs/zh/CASE_STUDY.md)
- [为什么本地文件会像网络故障](docs/01-principles.md)
- [怎么检查、怎么恢复](docs/02-how-to.md)
- [每周检查](docs/03-daily-care.md)
- [命令清单](docs/DIAGNOSTIC_COMMANDS.md)
- [可以直接贴给 AI 助手的说明](docs/AGENT_CONTEXT.md)
- [论坛帖子和其他工具](docs/RELATED.md)
- [案例里哪些内容不能删](docs/PRESERVE.md)

图：

- [Storage layout](figures/schematic/storage-layout/preview.png)：`state.vscdb` 和 transcript 文件的位置
- [Recovery flow](figures/schematic/recovery-flow/preview.png)：退出、移走文件、重新开始，之后按需导出或 GC
- [Size compare](figures/charts/size-compare/preview.png)：数据库与 transcripts、workspace、cache 的大小对比（对数坐标）
- [KV shape](figures/charts/kv-shape/preview.png)：各表行数（对数坐标）

## 许可证

MIT。Copyright (c) 2026 Xuzhen Li。
