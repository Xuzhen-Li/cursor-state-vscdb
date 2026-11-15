# Daily / weekly care

A two-minute weekly check to keep the file from growing into tens of GB. For emergency recovery see [02-how-to.md](02-how-to.md); the full incident write-up is in [CASE_STUDY.md](CASE_STUDY.md).

## Weekly (two minutes)

```bash
./scripts/diagnose.sh | tee -a ~/cursor-state-diagnose.log   # prints the size too; works on macOS and Linux
```

Watch for sudden jumps: a few GB, into the teens, then tens of GB.

## Work habits that slow growth

1. Prefer new chats for new tasks instead of one endless Agent thread (self-fork and resume can copy large transcripts).
2. Export anything you might need later before bulk cleanup.
3. Run GC Agent KV Blobs after deleting large chats, then fully quit.
4. Do not leave the machine on a nearly full disk if you plan to compact or VACUUM — reserve free space roughly equal to the main DB size (the WAL during GC can reach ~`state.vscdb`).
5. Keep `~/.cursor/projects/**/agent-transcripts` as a secondary copy, though it is not a complete UI index.

## What “healthy enough” looks like

- The chat list opens in seconds after a reboot.
- A New Chat `hello` responds promptly.
- `state.vscdb` is not growing week over week without bound.
- The freelist fraction stays small and the absolute file size stays moderate (small freelist + 50 GB still means real data).

## When to open an incident

If chats take forever to load, the Agent spins on trivial messages, or the DB passes ~30 GB and causes slowdowns, follow [02-how-to.md](02-how-to.md), then read [CASE_STUDY.md](CASE_STUDY.md).
