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

## 十四、Cursor 自己提供了 `GC Agent KV Blobs`

在 Cursor Command Palette 中存在一个维护命令：

```text
Developer: GC Agent KV Blobs
```

Cursor 社区支持人员建议使用它清理不再被聊天引用的 Agent KV blobs。

但是需要注意两个问题。

### 1. GC 不一定能清掉所有内容

如果数据已经没有任何 Chat 引用：

```text
orphaned KV blobs
```

GC 可以回收。

但如果几十 GB 数据仍然被某几个超长 Chat 认为是：

```text
live
```

那么 GC 不会删除它们。

一个 96 GB 案例中，GC 最终只回收了大约 18%，原因正是大量 transcript copy 仍然属于 live data。

所以：

```text
GC Agent KV Blobs
```

不是：

```text
一键把 52 GB 变成 500 MB
```

它是一个相对保守的垃圾回收工具。

---

## 十五、为什么 GC / VACUUM 需要很多额外磁盘空间？

对于几十 GB 的 SQLite 数据库，这一点非常重要。

Cursor 社区支持人员解释过，数据库 compact 过程中可能需要写出接近完整的新数据库副本，所以额外空间需求可能接近数据库本身体积，极端情况下接近两倍。

社区里已经有人：

```text
state.vscdb = 30 GB
```

即使额外清出了几十 GB，依然在：

```text
Compacting Storage
```

阶段遇到 Disk Full。

因此：

> 不要在磁盘只剩几 GB 时对一个几十 GB 的 `state.vscdb` 运行 VACUUM 或 GC compact。

尤其不要直接执行：

```sql
VACUUM;
```

然后期待它原地缩小。

SQLite 的 VACUUM 本质上需要重新构造数据库。

---

## 十六、如果只是想马上恢复 Cursor，最安全的方法是什么？

如果：

```text
Cursor 已经无法使用
```

而数据库又几十 GB，可以采用我这次验证过的方法：

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

到其他目录。

Cursor Community Forum 的支持回复实际上也给出了类似方案：如果数据库过大导致 compaction 无法完成，可以先完整退出 Cursor，把 oversized database 移走，让 Cursor 创建新的小数据库。

### 第三步：重新打开 Cursor

Cursor 会创建：

```text
新的 state.vscdb
```

这样至少可以立即恢复工作。

代价是：

> 原来的本地 Chat history 索引可能不会直接显示在新数据库中。

所以不要急着删除旧数据库。

---

## 十七、如果还想保留旧 Chat，处理顺序应该更保守

如果磁盘空间足够，我认为比较合理的顺序是：

```text
完整退出 Cursor
        ↓
保留旧 state.vscdb
        ↓
确认 ~/.cursor/projects/agent-transcripts 存在
        ↓
必要 Chat 使用 Export Chat
        ↓
Developer: GC Agent KV Blobs
        ↓
完全 Cmd+Q
        ↓
重新检查 DB 大小和 Cursor 性能
```

如果 GC 之后数据库依然几十 GB，那么问题很可能不只是 orphaned data。

Cursor 社区支持针对超大数据库给出的进一步思路是：

```text
Export 重要 Chat
        ↓
删除异常巨大的长 Chat
        ↓
GC Agent KV Blobs
        ↓
完全退出 Cursor
```

因为某些非常长、经历大量 Agent self-fork 的聊天，本身可能就是几十 GB live data 的来源。

---

## 十八、不建议直接手工删除这些 SQL 记录

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

这种操作确实可能瞬间解决磁盘问题。

但风险同样非常明显：

> 它可能直接破坏或者删除旧 Agent Chat 所需要的数据。

已经有 Cursor 用户明确报告过通过这类方式缩小数据库，但同时丢失聊天。

所以如果 Chat history 有价值：

> 不应该把暴力 SQL DELETE 当第一方案。

---

## 十九、这次排查得到的完整证据链

最终可以把整个过程浓缩成下面这条链：

```text
Mac 重启
    ↓
Cursor Loading Chats
    ↓
Agent 发消息一直转圈
    ↓
最初怀疑网络 / HTTP2 / Cursor 服务
    ↓
检查本地 globalStorage
    ↓
发现 state.vscdb = 52 GB
    ↓
SQLite 有 13,551,257 pages
    ↓
freelist 只有 2208 pages
    ↓
证明 52 GB 基本不是空闲页造成的虚胖
    ↓
ItemTable 只有 976 rows
    ↓
最大 value < 1 MB
    ↓
cursorDiskKV = 2,731,416 rows
    ↓
成为主要嫌疑
    ↓
~/.cursor/projects 中仍有
1015 个 Agent transcript
总大小仅 728 MB
    ↓
说明 52 GB 不能简单用“聊天很多”解释
    ↓
移动旧 state.vscdb
    ↓
Cursor 自动建立新 DB
    ↓
New Chat → hello
    ↓
秒回
```

对我而言，最后这个 A/B 实验是最关键的。

---

## 二十、目前我的判断

这次问题并不是传统意义上的：

```text
Cursor 安装坏了
```

也不像单纯：

```text
网络连不上 Cursor API
```

更加符合：

> **Cursor 本地 Agent / Composer 状态数据长期积累，使 `state.vscdb` 和 `cursorDiskKV` 膨胀到异常规模，最终在某些冷启动、历史恢复或者 Agent 初始化路径上造成严重性能问题。**

对于我的机器来说：

```text
state.vscdb
≈ 52 GB

cursorDiskKV
≈ 273 万条

composerHeaders
≈ 1048 条

agent transcript
≈ 1015 个 / 728 MB
```

而一个干净的 DB 可以立即让 Cursor 恢复秒回。

因此至少在这个案例里：

> 当 Cursor 出现 `Loading chats`、Agent 无限转圈，并且反复重启偶尔又突然恢复时，除了网络之外，非常值得检查 `state.vscdb`。

---

## 二十一、建议的日常监控方法

以后我会偶尔运行：

```bash
du -h "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
```

同时看看：

```bash
sqlite3 "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
"SELECT COUNT(*) FROM cursorDiskKV;"
```

如果出现：

```text
几 GB
→ 十几 GB
→ 几十 GB
```

的快速增长，就应该尽早处理，而不是等它增长到 50 GB 以后再排查。

对于长期 Agent 工作流，我也会尽量避免无限延长同一个 Chat。

根据 Cursor 社区支持人员对 96 GB 案例的分析，某些长 Chat 中反复的 Agent self-fork 可能复制完整 transcript；新建 Chat 或采用不会复制父 transcript 的工作方式，可以避免这种增长模式持续放大。

---

## 二十二、一个安全细节：不要把 API Key 发到网上

在排查过程中，我运行过：

```bash
ps aux | grep -i "[C]ursor"
```

Cursor Agent worker 的进程参数中可能包含：

```text
--api-key ...
```

所以如果准备把终端输出发到：

```text
GitHub
Cursor Forum
Blog
Reddit
```

一定要先把：

```text
API key
token
用户名
项目私有路径
```

全部打码。

如果已经公开过完整 token，最好重新登录 Cursor 或刷新相关凭证，而不是继续使用旧 token。

---

## 总结

这次排查最让我意外的并不是 Cursor 有一个 52 GB 的 SQLite 数据库。

而是：

> 一个本地数据库问题，可以表现得如此像网络问题。

它的表现不是简单的：

```text
Cursor 启动慢
```

而是：

```text
Loading chats
Agent 不回复
连续重启无效
某一次突然恢复
恢复以后又异常流畅
```

如果只盯着：

```text
网络
代理
模型
Cursor API
```

很容易一直排错方向。

最终真正让我确定方向的是：

```text
52 GB state.vscdb
+
273 万 cursorDiskKV
+
几乎为零的 SQLite freelist
+
全新 DB 后 Agent 秒回
```

如果以后有人遇到类似问题，我认为第一批值得检查的命令就是：

```bash
du -h "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"

sqlite3 "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
"SELECT COUNT(*) FROM cursorDiskKV;"

sqlite3 "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
"PRAGMA page_size; PRAGMA page_count; PRAGMA freelist_count;"
```

这几条命令可能比反复重装 Cursor 有用得多。

---

## 附录：我准备直接交给 Cursor Agent 的自修复上下文

下面这段可以直接复制给 Cursor，让它在本机继续分析。

```text
我正在排查 Cursor 自己的本地状态数据库异常，请基于以下已经确认的信息继续分析和修复，不要从头猜测网络问题。

【故障表现】

Mac 重启之后：
1. Cursor 可以启动，但 Chat 长时间显示 Loading chats。
2. 即使 Chat UI 加载出来，New Chat 输入 hello 也一直转圈，没有回复。
3. 多次强制退出重新启动后，某一次曾突然完全恢复，之后加载很快。
4. 目前 Cursor 又可以正常快速启动和使用，但旧数据库仍然异常巨大，所以不要认为问题已经永久消失。

【已经确认的 Cursor 本地数据库】

路径：

~/Library/Application Support/Cursor/User/globalStorage/state.vscdb

曾检查到：

state.vscdb      ≈ 52 GB
globalStorage    ≈ 58 GB
workspaceStorage ≈ 294 MB
Cursor Cache     ≈ 41 MB

SQLite 表：

ItemTable
cursorDiskKV
composerHeaders

记录数量：

ItemTable          = 976
cursorDiskKV        = 2,731,416
composerHeaders     = 1,048

cursorDiskKV schema：

key   TEXT
value BLOB

SQLite 页面：

page_size      = 4096
page_count     = 13,551,257
freelist_count = 2,208

计算：

总页面约 51.69 GiB。

freelist 只有约 8.6 MiB，约占整个数据库 0.016%。

因此 52 GB 并不是单纯 SQLite 删除数据后没有 VACUUM 造成的空文件膨胀；绝大部分页面实际处于使用状态。

【ItemTable 检查结果】

ItemTable 最大的单条 value 只有约 759 KB。

因此 ItemTable 不可能解释 52 GB。

主要嫌疑是 cursorDiskKV 的 273 万条 BLOB。

【Agent transcript】

~/.cursor/projects 中：

agent-transcripts/*.jsonl = 1015 个

整个：

~/.cursor/projects

只有约：

728 MB

所以 Agent transcript 文件总量与 52 GB state.vscdb 相差约 70 倍。

不要假设 52 GB 单纯是因为正常聊天内容很多。

【最关键的 A/B 测试】

我曾：

1. 完全 Cmd+Q 退出 Cursor。
2. 把 state.vscdb / state.vscdb-wal / state.vscdb-shm 移出 globalStorage。
3. 保留旧数据库，没有删除。
4. 重新启动 Cursor，让 Cursor 创建一个新的 state.vscdb。
5. New Chat 输入 hello。

结果：

立即回复，Cursor 完全恢复正常。

所以旧 state.vscdb / cursorDiskKV 与 Loading Chats 和 Agent 卡死高度相关。

随后我又恢复了旧数据库。目前 Cursor 暂时也能够快速启动和正常使用。

因此问题可能具有 cache / initialization / long-chat state / KV lookup 等状态依赖，但 52 GB DB 本身仍然需要处理。

【已经知道的同类问题】

Cursor Community Forum 中已经存在 state.vscdb 增长到：

30 GB
42 GB
96 GB

的案例。

其中 cursorDiskKV 会出现大量：

bubbleId
agentKv
checkpointId

相关数据。

Cursor 社区支持人员还提到某些 Agent self-fork / resume:self 场景可能产生完整 transcript copy，导致少数长 Chat 占据大量数据库空间。

【你的任务】

请首先只进行分析，不要直接破坏性删除数据。

目标：

1. 找出 52 GB state.vscdb 中 cursorDiskKV 的 key 类型分布。
2. 统计 bubbleId、agentKv、checkpointId、composerData 等 key 的数量和大致空间占用。
3. 判断是否是少数 Composer / Chat 导致绝大多数数据。
4. 尽可能建立 composer/chat ID 与 cursorDiskKV 数据量之间的对应关系。
5. 优先使用 Cursor 自己支持的 GC Agent KV Blobs 或其他官方维护机制。
6. 如果必须删除 Chat，先识别占用最大的 Chat，并让我选择。
7. 保留 ~/.cursor/projects/agent-transcripts 下已有的 1015 个 transcript。
8. 不要直接执行：
   DELETE FROM cursorDiskKV ...
   rm state.vscdb
   VACUUM
   除非已经明确说明影响并获得确认。
9. 所有数据库操作前确保 Cursor 已完全退出。
10. 如果 compact / VACUUM，需要先确认剩余磁盘空间足够。
11. 不要破坏当前仍可正常启动的 Cursor 状态。

请先输出：
A. 当前数据库诊断方案；
B. 准备执行的只读 SQL；
C. 根据结果如何识别占空间最大的 Chat；
D. 最安全的清理路线。

未经确认不要执行破坏性删除。
```

这就是目前完整的排查上下文。
