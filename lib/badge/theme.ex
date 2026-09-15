defmodule Badge.Theme do
  @moduledoc """
  Colours, chrome and geometry for every page.

  Colours, the title bar and rules come from whichever `Badge.Skin` the
  rendering process has activated, so they must be read when drawing, not
  captured in a module attribute. Geometry is fixed, and may be read at
  compile time: `Badge.Page.Text` derives its row count from `content_top/0`.

  `ok/0` and `alert/0` carry meaning rather than decoration: a page uses them
  when the reader should notice a state, not to brighten a layout.

  Depends only on `Badge.Hardware` and `Badge.Skin`, so nothing that reads
  it can cycle.
  """

  alias Badge.Hardware
  alias Badge.Skin

  def bg, do: Skin.current().bg()
  def fg, do: Skin.current().fg()

  # Secondary text: clearly below the primary line, still comfortably readable.
  def muted, do: Skin.current().muted()

  def dim, do: Skin.current().dim()
  def accent, do: Skin.current().accent()

  # Status colours, for state that reads as good or wrong at a glance.
  def ok, do: Skin.current().ok()
  def warn, do: Skin.current().warn()
  def alert, do: Skin.current().alert()

  # Whatever the cursor is currently on.
  def select, do: Skin.current().select()

  # What monochrome icons are drawn in.
  def glyph, do: Skin.current().glyph()

  @doc "The title bar and background for a page, in the active skin."
  @spec chrome(binary, map) :: [tuple]
  def chrome(title, status), do: Skin.current().chrome(title, status)

  @doc "A horizontal rule `w` wide from `x, y`, in the active skin."
  @spec rule(integer, integer, integer) :: [tuple]
  def rule(x, y, w), do: Skin.current().rule(x, y, w)

  def width, do: Hardware.display_width()
  def height, do: Hardware.display_height()

  # Title bar, with its rule on the last row.
  def bar_h, do: 22

  # First y a page may draw on.
  def content_top, do: 26
end
