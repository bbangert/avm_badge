# Badge Firmware

Firmware for the AVM badge, an ESP32-S3 device with a 6x13 no-diode GPIO
keyboard matrix, a 320x240 ST7789 SPI display, and a 4-LED SK6812 chain. It
runs on [AtomVM](https://github.com/atomvm/AtomVM), an Erlang/Elixir VM for
microcontrollers, and is written in Elixir.

## Quickstart

    git clone https://github.com/protolux-electronics/avm_badge.git
    cd avm_badge
    mix deps.get
    mix badge.base --full      # once per board
    mix atomvm.esp32.flash

`mix test` runs 783 tests on the host, no board needed. The port is
auto-detected — do not pass `--port`.

`Badge.start/0` opens the two SPI buses the board needs (panel and LED chain)
and starts a `Supervisor` with three children: `Badge.Screen` owns the AtomGL
display port and text buffer, `Badge.Keyboard` scans the matrix and dispatches
key events, and `Badge.Pixels` drives the LED chain and runs its idle
animation. See the moduledocs in `lib/badge/` for how each part works;
`lib/badge/hardware.ex` is the single source of truth for pin assignments.

## Testing

`Badge.TextBuffer` and `Badge.Keymap` are pure and tested on the host; most of
the rest talks directly to GPIO/SPI/AtomGL and is verified on hardware
instead.

## NervesHub (optional)

Over-the-air updates need a NervesHub device key. Export both:

    export BADGE_NH_KEY=...
    export BADGE_NH_SECRET=...

then run `tools/provision.py`, which merges them into the badge's NVS and
leaves every other key alone. The tools warn and continue when these are
unset; a badge without them simply never updates.

## Flash layout

Partition table read back off the board (`esptool.py read_flash` +
`gen_esp32part.py`):

```
nvs         data  nvs      0x9000     24K
phy_init    data  phy      0xf000      4K
factory     app   factory  0x10000  1920K
boot.avm    data  phy      0x1f0000  544K
assets.avm  data  phy      0x278000  256K
main.avm    data  phy      0x2b8000  656K
alt.avm     data  phy      0x35c000  656K
```

This table is compiled into the AtomVM image. Changing it means a serial
reflash of every badge.

## Base image

The VM this firmware runs on is a fork of AtomVM, built and published by CI at
[protolux-electronics/AtomVM](https://github.com/protolux-electronics/AtomVM).
`BASE_IMAGE` names the release this firmware expects.

    mix badge.base --full   # new board: bootloader, partition table, VM, boot.avm
    mix badge.base          # existing board: the VM and boot.avm

`boot.avm` holds the standard libraries the VM starts from. It is written
alongside the VM every time, because the two must come from the same build —
a VM with no matching `boot.avm` aborts at startup with `Invalid startup
avmpack` and reboots in a loop.

Both verify the download's SHA256 before flashing and raise on a mismatch.
`mix badge.base` shells out to the [`gh`](https://cli.github.com/) CLI to
download the release, so `gh` must be installed and authenticated
(`gh auth login`) before running it.

You do not need ESP-IDF to build or flash the firmware. It is needed only to
change the VM's C code, or to run `tools/provision.py`, which borrows ESP-IDF's
NVS parser.

## Assets

Sources live in `assets/src/`. To regenerate:

    tools/mkfonts.sh                    # assets/fonts/*.uf
    python3 tools/icons.py              # assets/icons/*.rgba
    python3 tools/gif.py                # assets/rickroll/*.rgba
    mix badge.assets                    # packs assets.avm
    tools/flashassets.sh                # writes it to the assets partition

`assets.avm` is not updated over the air.
