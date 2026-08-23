# Badge Firmware

Firmware for the AVM badge, an ESP32-S3 device with a 6x13 no-diode GPIO
keyboard matrix, a 320x240 ST7789 SPI display, and a 4-LED SK6812 chain. It
runs on [AtomVM](https://github.com/atomvm/AtomVM), an Erlang/Elixir VM for
microcontrollers, and is written in Elixir.

`Badge.start/0` opens the two SPI buses the board needs (panel and LED chain)
and starts a `Supervisor` with three children: `Badge.Screen` owns the AtomGL
display port and text buffer, `Badge.Keyboard` scans the matrix and dispatches
key events, and `Badge.Pixels` drives the LED chain and runs its idle
animation. See the moduledocs in `lib/badge/` for how each part works;
`lib/badge/hardware.ex` is the single source of truth for pin assignments.

## Building and flashing

This is a standard [ExAtomVM](https://github.com/atomvm/ExAtomVM) Mix project.
With the board connected over USB:

```
mix atomvm.esp32.flash
```

No `--port` is needed — the port is configured as `"auto"` in `mix.exs` and is
auto-detected. Run `mix test` to run the unit tests (`Badge.TextBuffer` and
`Badge.Keymap` are pure and tested on the host; most of the rest talks
directly to GPIO/SPI/AtomGL and is verified on hardware instead).

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

## Base image dependency

**`display_rotation` of 3 (`lib/badge/hardware.ex`) only works with a patched
AtomGL.** The badge's panel is mounted rotated relative to the ST7789's native
orientation, and the upstream AtomGL ST7789 descriptor shipped `0xFF`
(unsupported) in that rotation slot. The fix is a local patch living in the
**AtomVM** repository, not this one: revision `4319810` on branch
`badge/st7789-rotation-3`, under
`src/platforms/esp32/components/atomgl`. Any base image this firmware is
flashed onto must include that patch.

The failure mode if it's missing is silent — no crash, no error printed
anywhere in Elixir. `display_init` returns before its render task is created,
but the port context is already live, so `open_port` succeeds and
`:port.call` still gets its pre-ack. Frames from `Badge.Screen` queue up with
nothing ever draining them, and the panel just stays black.
