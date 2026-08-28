# AtomVM badge firmware

Elixir firmware for an ESP32-S3 conference badge: ST7789 display via AtomGL,
6x13 GPIO keyboard matrix, SK6812 NeoPixels. Runs on AtomVM, not the BEAM.

## Commands

- `mix test` — 771 tests across 43 files, no board needed
- `mix atomvm.esp32.flash` — builds, checks, flashes; port auto-detects, don't
  pass `--port`
- `ls /dev/cu.usbmodem*` — board re-enumerates, path changes between sessions
- Board resets after flashing, so chain flash and read to catch boot output:
  `( mix atomvm.esp32.flash >/dev/null 2>&1; stty -f <port> 115200 raw -echo; timeout 25 cat <port> )`
- Never run unbounded `cat`/`screen` on the port — it blocks the next flash
- Reflashing does not need `erase-flash`: `nvs` is unchanged by the repartition,
  so wifi credentials, profile and peers survive
- No `flash-elixir` target in this AtomVM revision — `idf.py flash` writes
  `boot.avm` itself
- Base image rebuild (rare): `. $IDF_PATH/export.sh; idf.py build` in
  `AtomVM/src/platforms/esp32`, then flash `0x10000` only — the app lives at
  `0x2B8000` and survives. Reproducing the build is documented in
  `AtomVM/src/platforms/esp32/BADGE-BUILD.md`

## Flash layout

- Two packbeam slots: `main.avm` at `0x2B8000` and `alt.avm` at `0x35C000`, 656K
  each. NervesHub writes whichever one is not running and flips
  `atomvm`/`boot_path` in NVS
- `assets.avm` at `0x278000` holds the rickroll frames and the `.uf` fonts,
  mounted by `Badge.start/0`. `firmware/tools/flashassets.sh` packs it and
  writes it in one step, auto-detecting the port; it is **not** updated over the
  air. Run `firmware/tools/gif.py` first if the frames changed
- `python3 firmware/tools/check_partitions.py <partitions.csv> [label=path ...]`
  fails if an artifact outgrows its partition. `flashassets.sh` checks the
  assets partition itself
- If `assets.avm` is missing or unflashed, the badge boots normally and prints
  `Badge: no assets partition:` — but opening Sudo Mode kills the `Badge.UI`
  GenServer, which restarts and resets the page to Home. It does **not**
  crash-loop. What Sudo Mode should draw when frames are absent is a pending
  follow-up decision.
- `dogica` and `pixel_operator` are compiled into `main.avm`, so text survives a
  missing assets partition. `w95fa` is read from it on demand; a failed read
  logs `UI: font ~p not in assets partition` once and is not retried.

## Chat transport

- The chat rides a websocket from the `atomvm_websocket_client` ESP-IDF
  component; `Badge.Chat.Socket` wraps it, `Badge.Chat.Link` owns the port
- **wss:// works, with two hard-won constraints.** TLS terminates at Phoenix
  (`:4443`, chain in `avm_badge_server/priv/cert`, badges pin the CA from
  `assets/certs/badge-ca.pem`). Never behind ngrok's https edge: it hangs up ~1s
  after its server flight, and this hardware needs ~1.6s to verify a public
  P-384 chain. For remote access use `ngrok tcp 4443` (raw bytes, no edge TLS) -
  the cert's SAN already covers `*.tcp.eu.ngrok.io`
- Match `{:websocket, _port, ...}` messages WITHOUT pinning the port: the
  driver's port term is not the one `open_port` returned, and a pinned match
  drops every message silently
- The socket opens only after `Wifi.status()` shows `synced: true` - at the
  epoch every certificate is "not yet valid"
- Both links are page-scoped: `Badge.Chat.Link` connects on entry to the chat
  page and disconnects on the way out, and `Badge.Update.Link` does the same for
  the Update tab. A badge on the home grid holds no socket. Entering chat
  therefore costs a handshake it used not to

## Firmware updates

- `Badge.Update.Link` owns the NervesHub agent; `Badge.Page.Settings.Update`
  only renders its `status/0` map. Updates and reboots are both `manual`, so
  nothing installs or restarts without a keypress
- Credentials are NVS keys `nh_key`, `nh_secret` and optional `nh_host` in the
  `:badge` namespace, written by `tools/provision_nerves_hub.py`. That tool
  replaces the whole partition, so it takes the wifi credentials too and the
  display name and peer list are lost
- **ExAtomVM writes no `priv/application.bin`**, and `firmware: boot` needs one.
  Without it the agent refuses to start and NervesHub cannot parse an upload.
  `mix atomvm.application_bin` writes it and is aliased onto `atomvm.packbeam`
- There is **no automatic rollback**. `:nh_ota.revert/0` is reached from the
  Update tab; firmware that will not boot needs a cable
- The agent commits a pending update when it joins, so opening the Update tab
  is what takes new firmware off trial
- `atomvm.check` flags `json:encode/1` and `json:decode/1` falsely - AtomVM
  ships `libs/estdlib/src/json.erl`. `erlang:--/2` and `erlang:phash2/2` come
  from the wrapper's Mix tasks, which are packed but never run

## AtomVM is not the BEAM

- **No `String` module.** Only the `String.Chars` protocol. Text is charlists or
  binaries.
- **`Enum` is a subset.** No `with_index`, `take`, `drop`, `sort`, `zip`,
  `uniq`, `sum`, `max`, `min`. `count/1` exists; **`count/2` does not**. Use
  `:lists` (complete) for anything missing.
- **Module attributes run on the host compiler** — full Elixir is legal inside
  them; only runtime code is constrained.
- **`Process.send_after/3` costs ~6.6 ms per call** (spawns two processes plus a
  synchronous `gen_server:call` to a singleton). Loop with `Process.sleep/1` in
  a process that receives nothing else.
- **`:port.call/2` blocks** waiting for a reply even when the driver pre-acks.
- **FreeRTOS tick is 10 ms** (`CONFIG_FREERTOS_HZ=100`) — the floor for any
  sleep or timer.
- **SPI `peripheral:` must be a string** (`"spi2"`), not an atom, or
  `:spi.open/1` throws `{bardarg,...}`.
- **`:erlang.get/1` returns `:undefined`**, not `nil` — `||` defaults don't
  work.
- **Charlists cost 2 machine words per character.** Large ones in messages cause
  OOM reboots; prefer binaries.
- Use plain maps, not structs.
- `mix atomvm.check` is the real compatibility gate and runs during flash. Host
  tests passing proves nothing.

## AtomGL display

- `{:update, list}` **repaints the entire screen** — no damage rect. Cost is per
  frame, not per change.
- Updates are pre-acked at enqueue; the render queue is 32 deep and drops
  oldest.
- Z-order is tail-to-head: background rect **last**, cursor **first**.
- `:default16px` (8x16) is the only built-in font.
- Rotation 3 needs AtomGL branch `led-modes` (`11be5f9`) in the base image.
  Without it the panel is **silently black** — no error anywhere in Elixir.

## Testing

- Pure modules (`Keymap`, `TextBuffer`, `KeyRepeat`) are host-tested; hardware
  modules are not.
- Warnings that `:spi`, `:port`, `:gpio`, `GPIO` are undefined are expected on
  host — not defects.
- `@impl true` goes on the **first clause only** of a multi-clause callback; a
  lint hook false-positives here.
- Visual and interactive behaviour (panel content, typing feel, LED colour)
  needs a human.
- Measure on hardware before optimising — several plausible theories were wrong
  this session.

## Conventions

- Commit subjects: capitalised, one line, no body, no `Co-Authored-By`.
- Comments: at most one line, local clarification only. No rationale, no
  measurements.
- Docstrings: may be multi-line but concise — how to use it, not why it was
  built that way.
- Design rationale lives in `../docs/` (outside this repo), not in code.
- Never discard uncommitted changes; report them instead.
- Always use the superpowers skills for brainstorming, writing plans, etc. But
  the superpower artifacts should not be committed to the repo
- Always use /i-have-adhd skill to format output to the user
