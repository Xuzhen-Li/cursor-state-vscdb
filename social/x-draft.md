# X draft for @jasonlixuzhen (English-only; do not post until Jason signs off)

## Suggested single post (≤280 chars preferred; thread OK if needed)

**Option A — single post**

Cursor stuck on “Loading chats” after a Mac reboot — even “hello” spun forever. Looked like network. Real cause: local `state.vscdb` ≈ 52 GB, `cursorDiskKV` ≈ 2.73M rows (almost no SQLite freelist). Moved the DB aside → fresh DB → hello answered instantly. Full write-up: https://github.com/Xuzhen-Li/cursor-state-vscdb

**Option B — short thread**

1/ After reboot, Cursor opened but chat stayed on Loading chats. New Chat “hello” spun forever. Many force-quits failed; one relaunch suddenly felt fine. Easy to blame the network.

2/ Local surprise: `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` ≈ 52 GB. `cursorDiskKV` ≈ 2.73M rows. Freelist only ~8.6 MB — real data, not empty-page bloat. On-disk agent JSONL was only ~728 MB.

3/ A/B: quit fully, move `state.vscdb` (+wal/shm) aside, relaunch. Fresh DB → hello almost instant. Same Mac/network/account. Forum has 30–96 GB cases; GC Agent KV Blobs helps orphans, not live mega-chats.

4/ Write-up + read-only diagnostics + agent handoff: https://github.com/Xuzhen-Li/cursor-state-vscdb

## Notes for the X bot

- English only.
- Do not attach secrets / `ps` with `--api-key`.
- Wait for Jason to approve before posting.
- Prefer Option A if one post; Option B if threading.
