defmodule Badge.Page.Home do
  @moduledoc """
  The 3x2 legend of which button opens which page.

  Purely informational: there is no cursor and no selection. Pressing a
  shape key navigates from anywhere, so this page never handles input.
  """

  use Badge.Page

  alias Badge.Icons
  alias Badge.Pages
  alias Badge.Theme

  @fg Theme.fg()
  @dim Theme.dim()
  @bg Theme.bg()

  @top Theme.content_top()
  @bottom Theme.height() - 2

  @cell_w 106
  @cell_h 105
  @cols_x [0, 107, 214]
  @rows_y [@top, @top + @cell_h + 2]

  @icon_size Icons.size()
  @icon_dx div(@cell_w - @icon_size, 2)
  @icon_dy 22
  @label_dy 64
  @char_w 8

  # Same order as Badge.Pages.all/0, so the two lists walk together.
  @cell_origins for y <- @rows_y, x <- @cols_x, do: {x, y}

  @rule_items [
    {:rect, 106, @top, 1, @bottom - @top, @dim},
    {:rect, 213, @top, 1, @bottom - @top, @dim},
    {:rect, 0, @top + @cell_h, Theme.width(), 1, @dim}
  ]

  @impl true
  def title, do: "Badge"

  # Required by the behaviour; Home is not in the registry, so nothing draws this.
  @impl true
  def icon, do: :square

  @impl true
  def init, do: :ok

  @impl true
  def render(:ok) do
    cell_items(Pages.all(), @cell_origins, []) ++ @rule_items
  end

  # Pages and origins threaded together so a label always sits under its own icon.
  defp cell_items([], [], acc), do: :lists.reverse(acc)

  defp cell_items([{_key, nil} | pages], [_origin | origins], acc) do
    cell_items(pages, origins, acc)
  end

  defp cell_items([{_key, module} | pages], [{x, y} | origins], acc) do
    label = module.title()

    icon = Icons.item(module.icon(), x + @icon_dx, y + @icon_dy)

    text =
      {:text, x + div(@cell_w - @char_w * byte_size(label), 2), y + @label_dy, :default16px, @fg,
       @bg, label}

    cell_items(pages, origins, [text, icon | acc])
  end
end
