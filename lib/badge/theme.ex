defmodule Badge.Theme do
  @moduledoc """
  Colours and chrome geometry for every page.

  Exposed as functions rather than attributes so they can be read from a
  module attribute at compile time: `Badge.Icons` bakes colours into its
  binaries during compilation, and `Badge.Page.Text` derives its row count
  from `content_top/0`.

  Depends only on `Badge.Hardware`, so nothing that reads it can cycle.
  """

  alias Badge.Hardware

  def bg, do: 0x000000
  def fg, do: 0xFFFFFF
  def dim, do: 0x606060
  def accent, do: 0x00E5A0

  def width, do: Hardware.display_width()
  def height, do: Hardware.display_height()

  # Title bar, with its rule on the last row.
  def bar_h, do: 22

  # First y a page may draw on.
  def content_top, do: 26
end
