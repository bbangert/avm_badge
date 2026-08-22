defmodule Badge.Page.Sensors do
  @moduledoc """
  What the board can measure, as a carousel moved between with left and right.

  Sub-pages are ordinary `Badge.Page` modules. Keys reach the active one
  first; only what it ignores becomes carousel movement, which is what lets
  a sub-page own the arrows when it needs them.

  Only the visible sub-page ticks, so the badge never reads a sensor nobody
  is looking at. Sub-page state persists while you slide sideways, because
  moving between them is not leaving the page.
  """

  use Badge.Page

  alias Badge.Page.Temp
  alias Badge.Page.Tilt
  alias Badge.Theme

  @fg Theme.fg()
  @dim Theme.dim()

  @subpages [Tilt, Temp]
  @count length(@subpages)

  # Below the readout, which is the lowest thing either sub-page draws.
  @dot_y 234
  @dot 6
  @dot_gap 10

  @impl true
  def title, do: "Sensors"

  @impl true
  def icon, do: :triangle

  @doc "The sub-pages, in carousel order."
  def subpages, do: @subpages

  @impl true
  def init do
    %{index: 0, states: for(module <- @subpages, do: module.init())}
  end

  # A sub-page sets its own rate; the carousel has none of its own.
  @impl true
  def refresh(state), do: active(state).refresh(active_state(state))

  @impl true
  def handle_key(event, state) do
    case active(state).handle_key(event, active_state(state)) do
      {:ok, sub_state} -> {:ok, put_active(state, sub_state)}
      :ignore -> carousel(event, state)
    end
  end

  @impl true
  def tick(state) do
    put_active(state, active(state).tick(active_state(state)))
  end

  @impl true
  def render(state) do
    active(state).render(active_state(state)) ++ dots(state.index)
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

  # Which sub-page you are on, so sliding sideways is discoverable without a label.
  defp dots(current) do
    left = div(Theme.width() - (@count * @dot + (@count - 1) * (@dot_gap - @dot)), 2)

    for index <- 0..(@count - 1) do
      colour = if index == current, do: @fg, else: @dim

      {:rect, left + index * @dot_gap, @dot_y, @dot, @dot, colour}
    end
  end
end
