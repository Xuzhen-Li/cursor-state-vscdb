# Cursor 重启后卡在 Loading Chats：我最终定位到一个 52 GB 的 `state.vscdb`

最近我遇到了一个非常折磨人的 Cursor 问题。

Mac 重启之后，Cursor 本身能够正常打开，但聊天区域长时间停留在：

```text
Loading chats
```

即使聊天界面最终显示出来，随便输入一句最简单的话，例如：

```text
hello
```

Cursor 也会一直转圈，没有回复。

更奇怪的是，我连续强制退出、重新启动很多次都没有改善，但某一次重新打开之后，它又突然完全恢复正常，而且聊天加载和 AI 回复都非常快。

最开始我怀疑过网络、代理、Cursor 服务端、HTTP/2、Agent 后台进程等问题。但最后经过一轮比较完整的排查，真正值得怀疑的东西出现在本机：

```text
state.vscdb
```

这个 Cursor 本地 SQLite 数据库竟然已经膨胀到了：

```text
52 GB
```

而其中的 `cursorDiskKV` 表已经有：

```text
2,731,416 条记录
```

最终通过一次非常直接的 A/B 测试：

> 把旧的 `state.vscdb` 暂时移开，让 Cursor 自动建立一个全新的数据库。

Cursor 立刻恢复，New Chat 输入 `hello` 几乎秒回。

这篇文章完整记录这次排查过程。

---

## 一、问题的表现

这次故障是在 Mac 重启以后突然出现的。

主要表现有三个。

### 1. Cursor 能打开，但一直 Loading Chats

应用本身没有崩溃，编辑器也能进入，但是 Chat 部分一直显示：

```text
Loading chats
```

有时候最终能把历史聊天加载出来，有时候长时间没有反应。

### 2. Chat 打开以后，Agent 仍然不能正常工作

即使聊天列表出现了，新建一个 Chat，发送：

```text
hello
```

也会一直转圈。

所以这不是单纯的：

> 历史聊天 UI 加载慢。

而是已经影响到：

> Agent / Chat 的正常请求流程。

### 3. 多次重启失败后，某一次又突然全部正常

这是整个问题最迷惑的地方。

表现大概是：

```text
重启 Mac
    ↓
启动 Cursor
    ↓
Loading chats
    ↓
发消息卡住
    ↓
强制退出
    ↓
重新打开
    ↓
还是不行
    ↓
重复很多次
    ↓
某一次突然完全恢复
    ↓
Chat 加载很快
    ↓
Agent 回复也很快
```

这使得它一开始非常像网络或 Cursor 服务端偶发故障。

但后面的证据表明，本地状态数据库才是最大的异常点。

---

## 二、第一步：确认 Cursor 是否真的完全退出

为了避免数据库仍然被 Cursor 占用，我首先完全退出 Cursor，然后检查进程：

```bash
ps aux | grep -i "[C]ursor"
```

Cursor 完全退出后，只剩：

```text
/System/Library/PrivateFrameworks/TextInputUIMacHelper.framework/...
CursorUIViewService.xpc
```

这里需要注意：

```text
CursorUIViewService
```

并不是 Cursor IDE。

这是 macOS 自己的文本输入相关系统服务，只是名字恰好包含 `Cursor`。

因此可以忽略。

---

## 三、真正异常的东西出现了：`state.vscdb` 有 52 GB

Cursor 在 macOS 上的全局状态目录位于：

```text
~/Library/Application Support/Cursor/User/globalStorage/
```

检查目录：

```bash
ls -lah "$HOME/Library/Application Support/Cursor/User/globalStorage/"
```

结果中最夸张的是：

```text
conversation-search.db       24M
conversation-search.db-wal  6.9M

state.vscdb                  52G
state.vscdb-shm              32K
state.vscdb-wal             4.7M
```

整个：

```text
globalStorage
```

已经达到：

```text
58 GB
```

作为对比：

```text
workspaceStorage    294 MB
Cursor Cache         41 MB
```

也就是说，真正的大头几乎全部来自：

```text
state.vscdb
```

一个 SQLite 状态数据库占掉了五十多个 GB。

这已经非常不正常。

---

## 四、`state.vscdb` 到底是什么？

Cursor 基于 VS Code / Electron 架构，它需要在本地保存大量应用状态。

其中一个重要文件就是：

```text
state.vscdb
```

它本质上是 SQLite 数据库。

在我的数据库中执行：

```bash
sqlite3 "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
"SELECT name FROM sqlite_master WHERE type='table';"
```

得到：

```text
ItemTable
cursorDiskKV
composerHeaders
```

也就是说，这个 52 GB 的数据库主要由这三个表组成。

---

## 五、完整 SQLite integrity check 直接变得不可行

我尝试运行：

```bash
sqlite3 "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
"PRAGMA integrity_check;"
```

结果长时间没有任何输出。

最后只能：

```text
Ctrl + C
```

手动中断。

需要强调：

这并不能证明数据库已经损坏。

`PRAGMA integrity_check` 需要扫描数据库结构，而数据库已经超过 50 GB，因此执行时间可能非常长。

所以对于这种体积的数据库，直接运行完整 integrity check 并不是一个高效的第一步。

---

## 六、三个表到底有多少记录？

接下来只统计行数：

```sql
SELECT 'ItemTable', COUNT(*) FROM ItemTable
UNION ALL
SELECT 'cursorDiskKV', COUNT(*) FROM cursorDiskKV
UNION ALL
SELECT 'composerHeaders', COUNT(*) FROM composerHeaders;
```

结果：

```text
ItemTable              976
cursorDiskKV      2,731,416
composerHeaders        1048
```

这里已经出现了一个非常明显的异常：

```text
cursorDiskKV = 273 万条
```

而：

```text
ItemTable = 976
composerHeaders = 1048
```

数量完全不在一个量级。

---

## 七、52 GB 是 SQLite “虚胖”，还是里面真的有数据？

这是非常关键的一步。

SQLite 文件很大，并不一定意味着里面真的存在那么多有效数据。

一种可能是：

> 曾经存在大量数据，后来数据被删除，但 SQLite 没有执行 VACUUM，所以数据库文件没有缩小。

所以检查：

```bash
sqlite3 "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
"PRAGMA page_size; PRAGMA page_count; PRAGMA freelist_count;"
```

结果：

```text
page_size
4096

page_count
13551257

freelist_count
2208
```

计算一下。

数据库总页面：

```text
13,551,257 × 4096
= 55,505,948,672 bytes
≈ 51.69 GiB
```

和磁盘看到的 52 GB 完全吻合。

但是空闲页面只有：

```text
2208 × 4096
≈ 8.6 MiB
```

也就是说：

```text
52 GB 数据库
```

里面真正处于 freelist 的空间只有大约：

```text
8.6 MB
```

占整个数据库大约：

```text
0.016%
```

这意味着：

> 这个数据库不是一个“删除数据以后没有 VACUUM 的 52 GB 空壳”。

而是绝大部分页面确实正在被 SQLite 使用。

这是整个排查中的关键证据之一。

---

## 八、`ItemTable` 基本可以排除

继续看：

```sql
SELECT key, length(value) AS bytes
FROM ItemTable
ORDER BY bytes DESC
LIMIT 20;
```

最大的几个对象分别只有：

```text
workbench.experiments.statsigBootstrap              758738 bytes

agentData.cacheStorage...                           479848 bytes

reactiveStorageServiceImpl...                       462948 bytes

slashMenuItems...                                   336171 bytes
```

最大的也就：

```text
~759 KB
```

所以只有 976 条记录的 `ItemTable` 显然无法解释 52 GB。

这时嫌疑基本全部集中到了：

```text
cursorDiskKV
```

它的结构非常简单：

```text
key    TEXT
value  BLOB
```

但里面有：

```text
2,731,416
```

条记录。

---

## 九、Cursor 社区中已经有人遇到几乎一样的问题

继续查 Cursor Community Forum 后发现，这不是孤立案例。

2026 年 8 月已经有人报告：

```text
state.vscdb ≈ 30 GB
cursorDiskKV = 1,962,076 rows
```

进一步分析后，其中包括大约：

```text
bubbleId       1.33 million
agentKv        582k
checkpointId   4k
```

该用户同样报告 Cursor 最终变得非常难用甚至无法使用。

另一个 2026 年 9 月的案例更加夸张：

```text
state.vscdb → 96 GB
```

数据库会随着长时间 Agent 使用继续快速增长。Cursor 社区支持人员在回复中指出，一些 Agent self-fork 场景可能产生完整 transcript 副本，因此问题可能集中在少数几个非常长、持续使用的 Agent Chat 中。

所以我的：

```text
52 GB
2.73 million cursorDiskKV rows
```

并不是完全没有先例。

---

## 十、另一个重要发现：Agent transcript 还单独存在

因为直接处理 `state.vscdb` 有可能影响历史聊天，所以我继续检查：

```text
~/.cursor/projects
```

运行：

```bash
find "$HOME/.cursor/projects" \
-type f -path "*/agent-transcripts/*.jsonl" 2>/dev/null | wc -l
```

结果：

```text
1015
```

也就是说本机还存在：

```text
1015 个 agent transcript JSONL
```

整个目录：

```bash
du -sh "$HOME/.cursor/projects"
```

只有：

```text
728 MB
```

于是出现了一个非常有意思的比例：

```text
Agent transcripts
≈ 728 MB

state.vscdb
≈ 52 GB
```

相差约：

```text
70 倍
```

这进一步说明：

> `state.vscdb` 的巨大体积并不能简单解释成“我的聊天本来就很多”。

数据库中明显还有大量 Agent KV、Bubble、Checkpoint、状态副本或者其他内部数据。

但这里也要注意：

`agent-transcripts/*.jsonl` 存在，并不意味着可以直接删除数据库。

因为：

> 聊天正文存在 ≠ Cursor UI 中的聊天索引、Workspace 关系、Composer metadata 都可以自动恢复。

所以这些 JSONL 更适合作为额外保险，而不是把它理解成完整数据库备份。

---

## 十一、最关键的实验：换一个全新的 DB

到这里其实依然只能说：

> 52 GB 数据库高度可疑。

但“高度可疑”和“真正导致问题”是两回事。

所以做了一个非常简单的 A/B 测试。

完全退出 Cursor 后，把：

```text
state.vscdb
state.vscdb-shm
state.vscdb-wal
```

全部移动到备份目录。

注意：

是：

```text
mv
```

不是删除。

例如：

```bash
cd "$HOME/Library/Application Support/Cursor/User/globalStorage"

mkdir -p state-vscdb-backup

for f in state.vscdb state.vscdb-shm state.vscdb-wal; do
    [ -e "$f" ] && mv "$f" state-vscdb-backup/
done
```

然后重新打开 Cursor。

因为找不到：

```text
state.vscdb
```

Cursor 自动建立一个新的、干净的数据库。

接着：

```text
New Chat
```

输入：

```text
hello
```

结果：

> **秒回。**

Cursor 的启动、Chat 界面和 Agent 全部恢复正常。

这是整个排查过程中最强的一条因果证据。

因为在这个实验中：

```text
Mac 没变
网络没变
Cursor 安装没变
Cursor 账号没变
模型没变
项目没变
```

主要改变的就是：

```text
旧的 52 GB state.vscdb
        ↓
新的干净 state.vscdb
```

结果从：

```text
Loading chats
Agent 一直转圈
```

变成：

```text
秒开
秒回
```

因此可以非常有把握地认为：

> 原始 `state.vscdb` 的异常状态与 Cursor 的 Loading Chats / Agent 卡死高度相关。

---

## 十二、为什么它之前会“突然又好了”？

这是我一开始最不能理解的地方。

如果数据库真的有问题，为什么连续启动十几次都不行，但某一次又突然正常？

这里有几个合理解释，但目前无法仅凭本地观察确定 Cursor 内部具体是哪一个阶段造成的。

首先，一个 52 GB 的 SQLite 文件，并不代表 Cursor 每次启动都会顺序读取完整 52 GB。

实际访问可能涉及：

```text
SQLite page cache
macOS filesystem cache
聊天索引
cursorDiskKV 查询
Agent 初始化
conversation search
Workspace 状态恢复
WAL checkpoint
多个 Electron / Agent 后台进程
```

所以一个超大数据库带来的问题很可能不是：

```text
每次固定慢 30 秒
```

而是：

```text
冷启动偶尔非常慢
某些查询突然阻塞
某次初始化失败
Agent 等待状态数据库
再次启动后缓存命中
又突然非常快
```

这更符合实际看到的行为。

而反复强制退出并不是推荐的解决办法。

它更可能只是恰好让某一次初始化路径发生了变化。

---

## 十三、为什么后来恢复旧 DB，Cursor 又可以正常启动？

这是另一个值得强调的地方。

在确认“新 DB 秒回”之后，我又把原来的数据库恢复了回来。

之后再次启动 Cursor：

> 启动速度也变得非常快，而且目前全部正常。

这并不和前面的实验矛盾。

它只能说明：

> 超大数据库导致的问题可能具有状态性、缓存性或者初始化依赖，并不是一个“只要 DB > 50 GB 就必然每次启动失败”的简单线性问题。

换句话说：

```text
52 GB 数据库
```

仍然是一个极其明显的异常。

但具体是哪一个 Cursor 内部查询、Agent 状态恢复流程或者 KV 访问路径触发长时间阻塞，还需要进一步分析。

因此目前我不会把：

```text
现在突然正常了
```

理解成：

```text
数据库已经自己修好了
```

这两件事不是一个概念。

---

## 十四、实测：`Developer: GC Agent KV Blobs`（完整记录）

社区支持此前建议用 Command Palette 里的：

```text
Developer: GC Agent KV Blobs
```

清理不再被聊天引用的 Agent KV blobs。在 A/B 测试之后，我在本机真实跑了一次（Cursor **3.22.7**），并全程记录磁盘与 SQLite 指标。

重要前提：

- 这是 Cursor 自带的 GC，**不是**手工 `DELETE FROM cursorDiskKV ...`
- **不是**手动 `VACUUM`
- 期望值要现实：GC 只清 orphan；仍被长 Chat 引用的 live 数据不会被删掉

我没有先跑社区论坛里常见的官方顺序：

```text
Export → Developer: Delete Old Chats… → GC Agent KV Blobs → Cmd+Q
```

（见 [macOS globalStorage 61.1GB](https://forum.cursor.com/t/macos-globalstorage-61-1gb/171211) 等帖中的 staff 建议。）本机尚未实测 Delete Old Chats；下面所有数字都来自「只跑了一次 GC」的路径。

---

## 十五、GC 过程中：WAL 涨到与主库同量级

GC 进入 `Compacting Storage` 后持续 **超过 1 小时**。期间大致看到：

| 指标 | 过程中观察到的量级 |
|------|-------------------|
| `state.vscdb-wal` | 几 MB → 31G → 45G → **≈52G**，随后 checkpoint → **≈4.3 MB** |
| APFS 可用空间 | 约 32 → **18** → 66 → 69 → 122 GiB |
| CPU | 约 91% → 97% → 70% → 4% → 0.2% |

要点：

1. **WAL 峰值可以接近主库体积（≈52 GB）**。盘上只剩十几 GiB 时硬跑 GC / compact，风险和社区 30 GB Disk Full 案例同类，甚至更糟。
2. 过程中可用空间一度掉到约 **18 GiB**，随后又回升。其中有一次：APFS free 从约 18 跳到约 **66 GiB**，而 WAL 当时仍约 **52G**——更像 purgeable / 系统回收的表现，**不能**据此断定 Cursor 已经释放了 48 GB 主库数据。
3. checkpoint 之后 WAL 回到几 MB；主文件 `state.vscdb` 仍约 **52 GB**。

---

## 十六、GC 之后：真正回收了多少？

以 SQLite 页面为准（比「感觉磁盘变大了」可靠）：

| 指标 | GC 前 | GC 后 | 变化 |
|------|-------|-------|------|
| ItemTable | 976 | 985 | +9 |
| cursorDiskKV | 2,731,416 | **2,731,751** | **+335** |
| composerHeaders | 1,048 | 1,048 | 0 |
| page_count | 13,551,257 | **13,520,717** | **−30,540** |
| freelist_count | 2,208 | **186** | −2,022 |

换算：

```text
−30,540 pages × 4096
≈ 119.3 MiB
≈ 主库的 0.23%
```

结论非常明确：

> 一次 GC Agent KV Blobs **没有**把 52 GB 变成「可用的小库」。页面大约只少了 **119 MiB**；`cursorDiskKV` 行数甚至略增；freelist 更紧（186 pages ≈ 762 KB）。

Cursor 日志里还有一句值得记：reference walk 期间显示类似 **0 deleted（16 errors）**。即便如此，`page_count` 的下降仍是真实的——**以 `page_count` 为真相**，不要被「0 deleted」文案带偏。

在 freelist 已经很紧、live 数据仍主导的前提下，**盲目再跑第二次 GC 没有意义**。

---

## 十七、key 类型：约 98.4% 是 bubble / agentKv / checkpoint

GC 后对 `cursorDiskKV` 做了前缀计数（**只计行数，尚未按字节称重**）：

| 前缀 | 行数 | 约占 cursorDiskKV |
|------|------|-------------------|
| `bubbleId` | 2,029,436 | ≈74.29% |
| `agentKv` | 653,694 | ≈23.93% |
| `checkpointId` | 4,659 | ≈0.17% |
| **三者合计** | **2,687,789 / 2,731,751** | **≈98.39%** |

这说明：

> 空间嫌疑高度集中在 Agent / Chat 相关的 KV 前缀上。

但必须同时强调：

- **行数 ≠ 字节数**。哪一类真正占几十 GB、哪几个 Chat 拥有这些字节，**还没测**。
- 下一步只读 SQL（**尚未在本机跑完 / 结果未写入本文**）形态如下：

```sql
SELECT
  CASE
    WHEN key LIKE 'bubbleId:%' THEN 'bubbleId'
    WHEN key LIKE 'agentKv:%' THEN 'agentKv'
    WHEN key LIKE 'checkpointId:%' THEN 'checkpointId'
    WHEN key LIKE 'composerData:%' THEN 'composerData'
    ELSE 'other'
  END AS kind,
  COUNT(*) AS n,
  SUM(length(value)) AS bytes
FROM cursorDiskKV
GROUP BY 1
ORDER BY bytes DESC;
```

在拿到 `SUM(length(value))` 和按 Chat/Composer 聚合之前，不要声称「已经找到最终根因字节归属」。

---

## 十八、明确不要做的事

结合本次实测，再次强调：

1. **不要** `DELETE FROM cursorDiskKV WHERE key LIKE 'bubbleId:%'` / `agentKv:%` / `checkpointId:%`
2. **不要** `rm state.vscdb`（以及配套的 wal/shm）当作「清理」——需要紧急恢复时用 **`mv` 移开**，见下一节
3. **不要**指望在 freelist 已接近空（本次 GC 后仅 186 pages）时，靠 `VACUUM` 把 52 GB「挤掉」——没有可回收空页，VACUUM 也变不出空间
4. **不要**在 freelist 紧、live 数据仍主导时盲目再跑第二次 GC
5. 官方顺序 **Export → Delete Old Chats… → GC → Cmd+Q** 仍建议优先尝试，但 **本机尚未实测 Delete Old Chats 的效果**，本文不编造结果

第三方脚本若走「SQL DELETE 再 VACUUM」路径（例如部分 clean 工具 / gist），与本次结论冲突：在 chat history 仍有价值时，应视为高风险，而不是默认处方。

---

## 十九、如果只是想马上恢复 Cursor，最安全的方法是什么？

如果：

```text
Cursor 已经无法使用
```

而数据库又几十 GB，可以采用我这次 A/B **验证过**的方法：

### 第一步：完全退出 Cursor

```text
Cmd + Q
```

确认：

```bash
ps aux | grep -i "[C]ursor"
```

没有真正的 Cursor IDE 进程。

### 第二步：移动数据库，而不是删除

路径：

```text
~/Library/Application Support/Cursor/User/globalStorage/
```

移动：

```text
state.vscdb
state.vscdb-wal
state.vscdb-shm
```

到其他目录。例如：

```bash
cd "$HOME/Library/Application Support/Cursor/User/globalStorage"
mkdir -p state-vscdb-backup
for f in state.vscdb state.vscdb-shm state.vscdb-wal; do
    [ -e "$f" ] && mv "$f" state-vscdb-backup/
done
```

Cursor Community Forum 的支持回复也给出过类似方案：compaction 失败或库过大时，完整退出后把 oversized DB **移走**，让 Cursor 创建新的小库。

### 第三步：重新打开 Cursor

Cursor 会创建新的 `state.vscdb`。本次实测：New Chat 输入 `hello` **秒回**。

代价是：原来的本地 Chat history 索引可能不会直接显示在新数据库中。所以不要急着删除旧库。

把旧库移回去之后，卡顿有时又会出现——说明问题可以是**间歇性**的，并不等于「库已经自愈」。

---

## 二十、如果还想保留旧 Chat，更保守的顺序

磁盘空间足够时，社区 staff 常见建议（**本机 Delete Old Chats 仍未测**）：

```text
完整退出 Cursor
        ↓
保留旧 state.vscdb
        ↓
确认 ~/.cursor/projects/agent-transcripts 存在
        ↓
必要 Chat 使用 Export Chat
        ↓
Developer: Delete Old Chats…   ← 本机尚未实测
        ↓
Developer: GC Agent KV Blobs
        ↓
完全 Cmd+Q
        ↓
用 page_count / freelist / du 复核
```

注意本次实测：在 **未** Delete Old Chats 的前提下，单独 GC 只回收约 **119 MiB**，且 WAL 峰值可≈主库。跑 GC 前请预留接近主库体积的空闲空间。

若 GC 后库仍几十 GB，问题很可能是 **live** Agent/Chat KV，而不是 orphan 空壳。

---

## 二十一、不建议直接手工删除这些 SQL 记录

网上可以找到类似：

```sql
DELETE FROM cursorDiskKV
WHERE key LIKE 'agentKv:%';

DELETE FROM cursorDiskKV
WHERE key LIKE 'bubbleId:%';

DELETE FROM cursorDiskKV
WHERE key LIKE 'checkpointId:%';

VACUUM;
```

这种操作确实可能瞬间「解决」磁盘问题，但风险同样非常明显：

> 它可能直接破坏或者删除旧 Agent Chat 所需要的数据。

已经有用户报告过类似路径缩小数据库但同时丢失聊天。本次 key 分布又显示这三类合计约 **98.4%** 行——盲删几乎等于掏空 Agent 状态。

如果 Chat history 有价值：

> 不应该把暴力 SQL DELETE 当第一方案。

---

## 二十二、这次排查得到的完整证据链（含 GC 实测）

```text
Mac 重启
    ↓
Cursor Loading Chats / Agent 转圈（可间歇恢复）
    ↓
最初怀疑网络 / HTTP2 / Cursor 服务
    ↓
globalStorage → state.vscdb ≈ 52 GB
    ↓
page_count 13,551,257 / freelist 2,208
    ↓
证明 52 GB 基本不是空闲页虚胖
    ↓
ItemTable 976 / max value ~759 KB
    ↓
cursorDiskKV 2,731,416 → 主嫌疑
    ↓
agent-transcripts 1015 个 / ~/.cursor/projects ≈ 728 MB
    ↓
mv 旧 DB → 新 DB → hello 秒回
    ↓
恢复旧 DB → 有时又快（间歇）
    ↓
Developer: GC Agent KV Blobs（>1h）
    ↓
WAL 峰值 ≈52G；可用曾低至 ≈18 GiB
    ↓
page_count −30,540 ≈ 119.3 MiB；freelist → 186
    ↓
cursorDiskKV 行数略增；主文件仍 ≈52 GB
    ↓
bubbleId+agentKv+checkpointId ≈ 98.39% 行
    ↓
字节级归属与 Delete Old Chats 效果：待测
```

---

## 二十三、目前我的判断

这次问题并不是传统意义上的「Cursor 安装坏了」，也不像单纯「网络连不上 Cursor API」。

更加符合：

> **本地 Agent / Composer 状态长期积累，使 `state.vscdb` / `cursorDiskKV` 膨胀到异常规模；与 Loading chats / Agent 卡死高度相关。GC 实测表明当前库以 live KV 为主，单次 orphan GC 只能回收约 0.23% 页面。**

对本机（Cursor **3.22.7**）：

```text
state.vscdb          ≈ 52 GB（GC 后主文件仍约此量级）
cursorDiskKV         2,731,416 → 2,731,751
page_count           13,551,257 → 13,520,717（≈ −119.3 MiB）
freelist_count       2,208 → 186
key 前缀（行数）      bubbleId / agentKv / checkpointId ≈ 98.4%
agent transcripts    ≈ 1015 / 728 MB
```

同日稍后：启动仍会扫描约 **903** 个 agent headers；extension 进程曾被强制退出一次——与「库仍然巨大」一致，**并不推翻**上面的 `page_count` 记录。

因此至少在本案例里：

> 当出现 Loading chats、Agent 无限转圈、反复重启偶尔又突然恢复时，除了网络之外，非常值得检查 `state.vscdb`。强关联 + live Agent/Chat KV 主导，可以成立；字节级最终根因归属仍待 `SUM(length(value))` 与按 Chat 聚合。

---

## 二十四、建议的日常监控方法

以后我会偶尔运行：

```bash
du -h "$HOME/Library/Application Support/Cursor/User/globalStorage/"state.vscdb*
```

同时看看：

```bash
sqlite3 "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
"SELECT COUNT(*) FROM cursorDiskKV;"

sqlite3 "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
"PRAGMA page_size; PRAGMA page_count; PRAGMA freelist_count;"
```

如果出现「几 GB → 十几 GB → 几十 GB」的快速增长，就应该尽早处理。

准备跑 GC / compact 时，额外记住一句：

> **预留接近主库体积的空闲磁盘**（本次 WAL 峰值 ≈ 主库）。盘只剩十几 GiB 时不要硬跑。

长期 Agent 工作流尽量避免无限延长同一个 Chat；社区对超大库的分析里，self-fork / 完整 transcript 副本是常见增长模式。

---

## 二十五、一个安全细节：不要把 API Key 发到网上

排查时 `ps aux | grep -i "[C]ursor"` 的输出里，Agent worker 参数可能包含：

```text
--api-key ...
```

发到 GitHub / Forum / Blog / Reddit 前，务必打码：

```text
API key / token / 用户名 / 项目私有路径
```

路径一律写成 `/Users/<USER>/`、`<PROJECT>`；永远不要粘贴 `crsr_…` 一类凭证。若已公开过完整 token，应重新登录或轮换凭证。

---

## 总结

这次排查最让我意外的，并不是 Cursor 有一个 52 GB 的 SQLite 文件，而是：

> 一个本地数据库问题，可以表现得如此像网络问题。

表现不是简单的「启动慢」，而是 Loading chats、Agent 不回复、连续重启无效、某一次突然恢复、恢复以后又异常流畅——以及后来证实的**间歇性**。

最终真正让我确定方向，并被 GC 实测加固的是：

```text
52 GB state.vscdb
+
273 万级 cursorDiskKV
+
几乎为零的 SQLite freelist（GC 后更紧）
+
全新 DB 后 Agent 秒回
+
单次 GC 仅 ≈119 MiB / ≈0.23% 页面
+
≈98.4% 行落在 bubbleId / agentKv / checkpointId
```

第一批值得检查的命令：

```bash
du -h "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"

sqlite3 "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
"SELECT COUNT(*) FROM cursorDiskKV;"

sqlite3 "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
"PRAGMA page_size; PRAGMA page_count; PRAGMA freelist_count;"
```

这几条可能比反复重装 Cursor 有用得多。

---

## 附录：我准备直接交给 Cursor Agent 的自修复上下文

下面这段可以直接复制给 Cursor，让它在本机继续**只读**分析。也见英文精简版 [AGENT_CONTEXT.md](../AGENT_CONTEXT.md)。

```text
我正在排查 Cursor 自己的本地状态数据库异常，请基于以下已经确认的信息继续分析，不要从头猜测网络问题。

【故障表现】

Mac 重启之后：
1. Cursor 可以启动，但 Chat 长时间显示 Loading chats。
2. 即使 Chat UI 加载出来，New Chat 输入 hello 也一直转圈，没有回复。
3. 多次强制退出重新启动后，某一次曾突然完全恢复，之后加载很快。
4. A/B：移开旧 DB → 新 DB → hello 秒回；恢复旧 DB 后卡顿可间歇再现。
5. 不要因为某次又变快，就认为 52 GB 库已经永久修好。

【版本】

Cursor 约 3.22.7（本机实测 GC 时）。

【已经确认的 Cursor 本地数据库】

路径：

~/Library/Application Support/Cursor/User/globalStorage/state.vscdb

GC 前曾检查到：

state.vscdb      ≈ 52 GB
globalStorage    ≈ 58 GB
workspaceStorage ≈ 294 MB
Cursor Cache     ≈ 41 MB

SQLite 表：ItemTable / cursorDiskKV / composerHeaders

GC 前行数：ItemTable=976；cursorDiskKV=2,731,416；composerHeaders=1,048
GC 后行数：ItemTable=985；cursorDiskKV=2,731,751；composerHeaders=1,048

cursorDiskKV schema：key TEXT，value BLOB

GC 前页面：page_size=4096；page_count=13,551,257；freelist_count=2,208
→ 总页面约 51.69 GiB；freelist 约 8.6 MiB（≈0.016%）。不是空壳虚胖。

GC 后页面：page_count=13,520,717（−30,540 ≈ 119.3 MiB ≈ 0.23%）；freelist_count=186（≈762 KB）。
主文件仍约 52 GB。日志可见 0 deleted（16 errors）；以 page_count 为准。

ItemTable 最大 value ≈759 KB → 不能解释 52 GB。

【Agent transcript】

~/.cursor/projects 中 agent-transcripts/*.jsonl ≈ 1015 个；整个 projects 目录 ≈728 MB（与 52 GB DB 差约 70 倍）。

【GC 过程】

Developer: GC Agent KV Blobs，Compacting Storage >1h。
WAL：几 MB → ≈52G → checkpoint 后 ≈4.3MB。
可用磁盘曾低至 ≈18 GiB；APFS free 曾在 WAL 仍大时从 ≈18 跳到 ≈66 GiB（更像系统 purgeable，不能当成 Cursor 释放了 48GB 主库）。
CPU 高负载后回落。

【key 前缀（GC 后，仅行数）】

bubbleId 2,029,436（≈74.29%）
agentKv 653,694（≈23.93%）
checkpointId 4,659（≈0.17%）
合计 ≈98.39% of 2,731,751
字节 GiB / 按 Chat 归属：尚未测量。

【同日后续】

启动仍扫描约 903 agent headers；extension 曾 force-quit——与巨大 DB 一致，不推翻 page_count。

【禁止】

不要 DELETE bubbleId/agentKv/checkpointId；
不要 rm state.vscdb；
不要在 freelist 已空时幻想 VACUUM 能缩小；
不要盲目第二次 GC；
官方 Export→Delete Old Chats→GC→Cmd+Q 顺序本机尚未测 Delete Old Chats，勿编造结果。

【你的任务】

只读分析优先：
1. 跑 SUM(length(value)) 按 key 前缀称重（可能很慢）。
2. 尽量映射到占用最大的 composer/chat。
3. 在用户确认前，不要破坏性删除。
4. 所有写/移库前确保 Cursor 已完全退出；compact 前确认空闲盘 ≈ 主库量级。

先输出：A 诊断方案；B 只读 SQL；C 如何找最重 Chat；D 最安全清理路线。
```

这就是目前完整的排查上下文。

---

## 备忘：对话入口和第三方工具

- **Delete Old Chats…**：论坛 staff 常把它放在 GC 之前；**本机尚未实测**其删除量与后续 GC 回收量，本文不给出虚构数字。
- 相关论坛（含 52GB 量级与官方顺序讨论）：见 [RELATED.md](../RELATED.md)，尤其是 [macOS globalStorage 61.1GB](https://forum.cursor.com/t/macos-globalstorage-61-1gb/171211)。
- 第三方清理工具备忘（灵感 / 对照，不是本仓处方）：
  - [vilaca/cursor-chat-cleaner](https://github.com/vilaca/cursor-chat-cleaner)
  - [zhengchenliang/cursor-clean](https://github.com/zhengchenliang/cursor-clean) 以及部分 gist：常见路径是 **SQL DELETE 再 VACUUM**——与本文「勿盲删 bubble/agentKv/checkpoint」冲突，chat 仍有价值时请警惕。
- **Colima**：同机 `~/.colima` 下约有 **30GB** 量级占用，与 Cursor `state.vscdb` **无关**；仅作磁盘记账备忘，避免排障时张冠李戴。
