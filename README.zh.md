# cursor-state-vscdb

[English](README.md)

我的 Mac 重启后，Cursor 一直停在「Loading chats」，Agent 连一句 `hello` 都不回。看起来像网络问题，其实不是：Cursor 本地的 SQLite 文件 `state.vscdb` 已经涨到大约 52 GB。把这个文件移走、让 Cursor 新建一个之后，`hello` 马上就有回复了。

这里放着这次排查的完整记录、一个不写数据库的检查脚本，以及我让 Cursor 恢复可用、又不丢旧数据的做法。

## 检查你自己的文件

```bash
git clone https://github.com/Xuzhen-Li/cursor-state-vscdb.git
cd cursor-state-vscdb
./scripts/diagnose.sh
```

脚本不会写数据库，会打印文件大小、各表行数、页数和空闲页数。需要 `bash`；行数和页数还需要 `sqlite3` 命令（没有的话只显示大小）。

打开方式取决于 Cursor 是否在运行（脚本用 `pgrep` 判断；也可以设 `CURSOR_DIAG_OPEN=immutable` 或 `CURSOR_DIAG_OPEN=readonly` 自己指定）：

- Cursor 已退出、且没有残留的 `state.vscdb-wal`：以 `file:…?mode=ro&immutable=1` 打开，SQLite 不会新建附属文件。immutable 模式会忽略 `-wal` 文件，所以如果 Cursor 其实还在运行，读出的数字可能是旧的。
- Cursor 已退出、但 `state.vscdb-wal` 不为空（崩溃或强制退出后会这样）：改用 `sqlite3 -readonly`，把 `-wal` 里还没合并的改动也算进去，并说明原因。
- Cursor 在运行：用 `sqlite3 -readonly` 打开。Cursor 的数据库是 WAL 模式，SQLite 可能在旁边新建或更新 `state.vscdb-wal` 和 `state.vscdb-shm`。

文件通常的位置（macOS 和 Linux 上脚本默认找这里）：

| 系统 | 路径 |
|------|------|
| macOS | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` |
| Linux | `~/.config/Cursor/User/globalStorage/state.vscdb` |
| Windows | `%APPDATA%\Cursor\User\globalStorage\state.vscdb`（没有默认值，需设置 `CURSOR_STATE_DB`，WSL 下也一样） |

文件在别处时：

```bash
CURSOR_STATE_DB=/完整路径/state.vscdb ./scripts/diagnose.sh
```

Cursor 运行时会一直写这个文件，想要准确的数字请先退出 Cursor。正常退出后 `-wal` 通常是空的，不会产生附属文件；崩溃后脚本会用 `-readonly` 读残留的 `-wal`，这时可能新建 `state.vscdb-shm`。

## Cursor 现在就卡住了怎么办

如果文件有几十 GB、Cursor 加载不出聊天：先退出 Cursor，再把 `state.vscdb` 和同目录的 `-wal`、`-shm` 文件移到一个备份文件夹里，不要删除。下次启动时 Cursor 会新建一个空文件。具体命令见 [怎么做](docs/02-how-to.md) 第 2 节。

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
