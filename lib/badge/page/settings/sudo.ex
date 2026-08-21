defmodule Badge.Page.Settings.Sudo do
  @moduledoc """
  There are no developer controls here.
  """

  use Badge.Page

  alias Badge.Page.Settings
  alias Badge.Readout
  alias Badge.Rickroll
  alias Badge.Theme

  @dim Theme.dim()
  @bg Theme.bg()

  @caption "never gonna give you up"

  @x div(320 - Rickroll.size(), 2)
  # Nudged down off the tab rule so it does not crowd the strip.
  @y Settings.content_top() + 8
  @caption_y @y + Rickroll.size() + 8

  @frame_ms 200

  # The frame is derived from the clock rather than counted, so state changes
  # only when the picture does. A counter in state would look different on
  # every tick and repaint the panel ten times a second for five new frames.
  @impl true
  def refresh(_state), do: 100

  @impl true
  def title, do: "Sudo Mode"

  @impl true
  def init, do: 0

  @impl true
  def tick(_frame), do: frame_at(:erlang.monotonic_time(:millisecond))

  @doc "Which frame belongs to a moment in time."
  @spec frame_at(integer) :: non_neg_integer
  def frame_at(millis), do: rem(div(millis, @frame_ms), Rickroll.count())

  @doc "How long each frame is held."
  def frame_ms, do: @frame_ms

  @impl true
  def render(frame) do
    [
      Rickroll.item(frame, @x, @y),
      {:text, Readout.centre_x(@caption), @caption_y, :default16px, @dim, @bg, @caption}
    ]
  end
end
