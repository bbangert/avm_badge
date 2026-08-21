defmodule Badge.Page.Settings do
  @moduledoc """
  Board status, as a carousel of sub-pages moved between with left and right.

  Sub-pages are ordinary `Badge.Page` modules. Keys reach the active one
  first; only what it ignores becomes carousel movement, which is what lets
  a sub-page own the arrows when it needs them.

  Sub-page state persists while you slide sideways, because moving between
  sub-pages is not leaving the page. Leaving Settings entirely still resets
  everything, since `Badge.UI` calls `init/0` on every entry.
  """

  use Badge.Page

  alias Badge.Page.Settings.Display
  alias Badge.Page.Settings.Sudo
  alias Badge.Page.Settings.Update
  alias Badge.Page.Settings.Wifi
  alias Badge.Theme

  @dim Theme.dim()
  @bg Theme.bg()
  @select Theme.select()

  @separator " | "

  @subpages [Display, Wifi, Update, Sudo]
  @count length(@subpages)

  @char_w 8
  @strip_y Theme.content_top()
  @rule_y @strip_y + 22

  # First y a sub-page may draw on, below the tab strip and its rule.
  @content_top @rule_y + 8

  @impl true
  def title, do: "Settings"

  @impl true
  def icon, do: :circle

  # Nothing here moves fast enough to be worth a full repaint ten times a second.
  @impl true
  def refresh, do: 333

  @doc "First y a sub-page may draw on."
  def content_top, do: @content_top

  @doc "The sub-pages, in carousel order."
  def subpages, do: @subpages

  @impl true
  def init do
    %{index: 0, states: for(module <- @subpages, do: module.init())}
  end

  @impl true
  def handle_key(event, state) do
    case active(state).handle_key(event, active_state(state)) do
      {:ok, sub_state} -> {:ok, put_active(state, sub_state)}
      :ignore -> carousel(event, state)
    end
  end

  # Only the visible sub-page ticks; a hidden one would poll sensors nobody is looking at.
  @impl true
  def tick(state) do
    put_active(state, active(state).tick(active_state(state)))
  end

  @impl true
  def render(state) do
    strip(state) ++ active(state).render(active_state(state))
  end

  defp carousel({:move, :right}, state), do: {:ok, step(state, 1)}
  defp carousel({:move, :left}, state), do: {:ok, step(state, -1)}
  defp carousel(_event, _state), do: :ignore

  defp step(state, delta) do
    %{state | index: rem(state.index + delta + @count, @count)}
  end

  defp active(%{index: index}), do: :lists.nth(index + 1, @subpages)

  defp active_state(%{index: index, states: states}), do: :lists.nth(index + 1, states)

  defp put_active(%{index: index, states: states} = state, sub_state) do
    %{state | states: replace(states, index, sub_state, [])}
  end

  defp replace([_old | rest], 0, value, acc), do: :lists.reverse([value | acc]) ++ rest
  defp replace([keep | rest], n, value, acc), do: replace(rest, n - 1, value, [keep | acc])

  # Colour marks the active tab; the separators stay dim throughout.
  defp strip(state) do
    titles = for module <- @subpages, do: module.title()
    left = div(Theme.width() - @char_w * strip_width(titles), 2)

    tab_items(titles, 0, state.index, left, []) ++
      [{:rect, 8, @rule_y, Theme.width() - 16, 1, @dim}]
  end

  defp strip_width(titles) do
    names = :lists.foldl(fn title, total -> total + byte_size(title) end, 0, titles)

    names + byte_size(@separator) * (length(titles) - 1)
  end

  defp tab_items([], _position, _index, _x, acc), do: :lists.reverse(acc)

  # The last tab has nothing after it, so it contributes no separator.
  defp tab_items([title], position, index, x, acc) do
    :lists.reverse([tab(title, position, index, x) | acc])
  end

  defp tab_items([title | rest], position, index, x, acc) do
    next = x + @char_w * byte_size(title)
    separator = {:text, next, @strip_y, :default16px, @dim, @bg, @separator}

    tab_items(rest, position + 1, index, next + @char_w * byte_size(@separator), [
      separator,
      tab(title, position, index, x) | acc
    ])
  end

  defp tab(title, position, index, x) do
    {:text, x, @strip_y, :default16px, tab_colour(position, index), @bg, title}
  end

  defp tab_colour(position, position), do: @select
  defp tab_colour(_position, _index), do: @dim
end
