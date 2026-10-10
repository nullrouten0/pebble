# Security Policy

## What Pebble is (and isn't)

Pebble is a local macOS game with optional LAN multiplayer:

- **No internet, no telemetry.** The app never contacts an internet server: no telemetry, no analytics, no update checks, no accounts. The `pebble update` shell command is just `git pull` on your own checkout.
- **Network only for LAN play, and only when you ask.** Pebble opens a TCP port (25575 by default) and advertises it over Bonjour only after you click **Open to LAN** or run `/host`. It connects out only when you join a game. The Multiplayer screen browses Bonjour for `_pebble._tcp` while it's open.
- **No accounts, no credentials, no personal data.** Pebble stores worlds, settings, and keybinds under `~/Library/Application Support/Pebble/`.
- **No elevated privileges.** It's an ad-hoc-signed app running in a normal user session.

That makes the realistic threat model: **malicious files that you load into the game**, and, while you host or join a LAN game, **other machines on your local network.**

LAN games are deliberately simple. There's no password or encryption, and the host trusts what guests say about their own player (position, inventory, actions), so a modified client can cheat. Only open a world to LAN on a network where you'd let everyone in.

## Attack surface

If you're auditing Pebble, these are the interesting places — all of them parse untrusted input:

| Surface | Where | Notes |
|---|---|---|
| Texture zip (bundled Faithful) | `Sources/Pebble/ResourcePacks.swift` | custom zip central-directory parser + raw-deflate via Apple's Compression framework; PNG decode via CoreGraphics. Only the bundled archive is read, but the parser still treats it as untrusted input |
| Save database | `Sources/PebbleCore/Game/Saves.swift` | SQLite blobs in a `VCK1` container with a JSON tail; decode paths bounds-check lengths and clamp out-of-range block/item ids rather than trusting them |
| Settings/keybinds | `Sources/PebbleCore/Game/Settings.swift` | plain JSON via `Codable` |
| LAN protocol | `Sources/PebbleCore/Net/` | length-prefixed binary frames from peers; frames over 64 MB close the connection, every read is bounds-checked, chunk payloads are size-checked after decompression, and out-of-range block/item ids are dropped. Malformed messages are logged and skipped |

Hardening that already exists: chunk-blob decoding validates section lengths and clamps corrupted block ids to air; player-data loading repairs array sizes and drops out-of-range item ids; SQLite errors are surfaced and failed writes retried rather than ignored; the zip reader never writes outside its own buffers (it extracts to memory, not to disk paths from the archive).

## Reporting a vulnerability

If you find a way for a crafted save file, texture archive, or LAN message to do anything beyond crashing the game (memory corruption, code execution, file writes outside the support directory), please report it privately:

- **Email:** briangaoo2@gmail.com — subject line starting with `[pebble security]`
- Include: macOS version, a minimal reproducing file if possible, and what you observed.

Plain crashes / hangs from malformed files are ordinary bugs — file those as [regular GitHub issues](https://github.com/thebriangao/pebble/issues) with the offending file attached (the README lists what else to include). This is a beta; reports of every kind are incredibly welcome.

You can expect an acknowledgment within a few days. There's no bug bounty; you'll get credit in the changelog and my genuine thanks.

## Supported versions

Only the latest release is supported. There's no backporting; the fix ships in the next version.
