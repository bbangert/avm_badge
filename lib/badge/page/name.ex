defmodule Badge.Page.Name do
  @moduledoc """
  A name tag to leave on screen.

  Edit `@name` and `@tagline` to make the badge yours. AtomGL cannot scale
  text, so the name is capped at `dogica`'s native size.
  """

  use Badge.Page

  alias Badge.Theme

  @name "AtomVM"
  @tagline "Elixir on ESP32-S3"

  @accent Theme.accent()
  @fg Theme.fg()
  @dim Theme.dim()
  @bg Theme.bg()

  @char_w 8

  @name_x 16
  @name_y 90
  @rule_y 132
  @rule_w 200
  @tagline_y 152

  # Only default16px has known metrics, so only it can be centred.
  @tagline_x div(Theme.width() - @char_w * byte_size(@tagline), 2)

  @impl true
  def title, do: "Name"

  @impl true
  def icon, do: :diamond

  @impl true
  def init, do: :ok

  @doc "The name on the tag."
  def name, do: @name

  @doc "The line under the name."
  def tagline, do: @tagline

  @impl true
  def render(:ok) do
    [
      {:text, @name_x, @name_y, :dogica, @fg, @bg, @name},
      {:text, @tagline_x, @tagline_y, :default16px, @dim, @bg, @tagline},
      {:rect, @name_x, @rule_y, @rule_w, 2, @accent}
    ]
  end
end
