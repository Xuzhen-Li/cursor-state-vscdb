# Daily / weekly care

> **Door:** Daily care · **Use when:** you want a two-minute weekly habit so the DB never reaches tens of GB.  
> **Not this page:** emergency recovery → [02-how-to.md](02-how-to.md). Full incident → [CASE_STUDY.md](CASE_STUDY.md).

## Weekly (two minutes)

```bash
du -h "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
./scripts/diagnose.sh | tee -a ~/cursor-state-diagnose.log
```

Watch for jumps: a few GB → teens → tens of GB.

## Work habits that slow growth

1. **Prefer new chats** for new tasks instead of one eternal Agent thread (self-fork / resume can copy large transcripts).
2. **Export** anything you might need later before mass cleanup.
3. Run **GC Agent KV Blobs** after deleting large chats, then fully quit.
4. Do not leave the machine on a nearly full disk if you plan compact / VACUUM — **reserve ~main-DB free space** (WAL during GC can ≈ `state.vscdb`).
5. Keep `~/.cursor/projects/**/agent-transcripts` as a secondary copy — still not a full UI index.

## What “healthy enough” looks like

- Chat list opens in seconds after reboot.
- New Chat `hello` returns promptly.
- `state.vscdb` not climbing week over week without bound.
- Freelist fraction stays small **and** absolute size stays moderate (small freelist + 50 GB still means real data).

## When to open an incident

Loading chats forever, Agent spin on trivial messages, or DB past ~30 GB with pain — follow [02-how-to.md](02-how-to.md), then read [CASE_STUDY.md](CASE_STUDY.md).
