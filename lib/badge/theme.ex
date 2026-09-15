defmodule Badge.Theme do
  @moduledoc """
  Colours and chrome geometry for every page.

  `ok/0` and `alert/0` carry meaning rather than decoration: a page uses them
  when the reader should notice a state, not to brighten a layout.

  Exposed as functions rather than attributes so they can be read from a
  module attribute at compile time: `Badge.Icons` bakes colours into its
  binaries during compilation, and `Badge.Page.Lisp` derives its row count
  from `content_top/0`.

  Depends only on `Badge.Hardware`, so nothing that reads it can cycle.
  """

  alias Badge.Hardware

  def bg, do: 0x000000
  def fg, do: 0xFFFFFF

  # Secondary text: clearly below the primary line, still comfortably readable.
  def muted, do: 0xA8A8A8

  def dim, do: 0x606060
  def accent, do: 0x00E5A0

  # Status colours, for state that reads as good or wrong at a glance.
  def ok, do: 0x4CD964
  def warn, do: 0xFFCC00
  def alert, do: 0xFF3B30

  # Whatever the cursor is currently on.
  def select, do: 0x5AC8FA

  def width, do: Hardware.display_width()
  def height, do: Hardware.display_height()

  # Title bar, with its rule on the last row.
  def bar_h, do: 22

  # First y a page may draw on.
  def content_top, do: 26
end
