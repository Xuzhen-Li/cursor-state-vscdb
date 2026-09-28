# Reddit draft (do not post until Jason signs off)

## Suggested subreddits (pick one; bot should confirm rules)

- r/cursor
- r/ChatGPTCoding or r/LocalLLaMA only if Cursor-specific posts are off-topic there — prefer r/cursor first

## Title

Cursor stuck on “Loading chats” after reboot — root cause was a 52 GB `state.vscdb` (`cursorDiskKV` ≈ 2.7M rows)

## Body (Markdown)

After a Mac reboot, Cursor itself opened fine, but chat sat on **Loading chats**. Even when the list appeared, a New Chat with just `hello` spun forever. Force-quit / relaunch failed many times; once it suddenly recovered and felt fast. Classic “must be the network / API” pattern.

It was not (at least not primarily).

### What I found

Path:

`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`

- **~52 GB** SQLite file (`globalStorage` ~58 GB total)
- Tables: `ItemTable`, `cursorDiskKV`, `composerHeaders`
- Rows: ItemTable **976**, **cursorDiskKV 2,731,416**, composerHeaders **1,048**
- `page_size=4096`, `page_count=13,551,257`, `freelist_count=2,208` → ~51.7 GiB of pages in use; freelist only ~8.6 MB. **Not** “deleted rows, never VACUUMed empty fat.”
- Largest `ItemTable` values were under ~1 MB → cannot explain 52 GB.
- `~/.cursor/projects` still had ~1015 `agent-transcripts/*.jsonl` totaling only **~728 MB** (~70× smaller than the DB).

### A/B test

Fully quit Cursor, **move** (don’t delete) `state.vscdb` + `-wal` + `-shm` aside, relaunch so Cursor creates a new DB. New Chat → `hello` → **near-instant**. Same machine, network, install, account, project. Restoring the old DB later also started quickly again — so the failure mode looks intermittent / cache-or-init dependent — but **52 GB is still abnormal** and still needs a cleanup plan.

### Community / maintenance notes

Forum reports of 30–96 GB `state.vscdb` with heavy `bubbleId` / `agentKv` / `checkpointId`. **Developer: GC Agent KV Blobs** helps orphaned KV; it will not shrink data still referenced by huge live chats. Compaction / VACUUM can need free space on the order of the DB size (sometimes approaching 2×). Prefer Export Chat → delete a few monster threads → GC over raw `DELETE FROM cursorDiskKV` + `VACUUM`.

### Write-up

Full case study, diagnostic commands, and a paste-ready read-only agent handoff:

https://github.com/Xuzhen-Li/cursor-state-vscdb

Happy to answer questions. Do not paste `ps` lines that include API keys.

## Notes for the Reddit bot

- Draft only; Jason presses send / signs off.
- Prefer r/cursor; check subreddit rules (self-promo / link limits).
- No API keys, tokens, or private paths beyond the standard Application Support path above.
