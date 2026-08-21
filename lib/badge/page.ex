defmodule Badge.Page do
  @moduledoc """
  Behaviour every page implements.

  A page is a module, not a process: `Badge.UI` holds its state and calls
  these functions. `render/1` returns content items only — the router adds
  the title bar and the background rect, so no page can get the z-order
  wrong or forget the background.

  `use Badge.Page` supplies `handle_key/2`, `tick/1` and a 100 ms
  `refresh/0` for pages that need none of them, all overridable.
  """

  @type state :: term
  @type event :: {:char, integer} | {:edit, atom} | {:move, atom}
  @type item :: tuple

  @doc "Label for the home grid."
  @callback title() :: binary

  @doc "Icon name for the home grid, from `Badge.Icons.names/0`."
  @callback icon() :: atom

  @doc "Fresh state; runs on every entry to the page."
  @callback init() :: state

  @doc "Content display items, without chrome. Cursor first, background never."
  @callback render(state) :: [item]

  @doc "Applies an event, or returns `:ignore` if the page has no use for it."
  @callback handle_key(event, state) :: {:ok, state} | :ignore

  @doc "Refreshes state from the outside world; returning the same state means nothing to draw."
  @callback tick(state) :: state

  @doc """
  Shortest gap between frames, in milliseconds.

  A frame is a full-panel repaint, so a page whose data changes constantly
  should ask for a slower rate than one that only redraws on a keypress.
  """
  @callback refresh() :: pos_integer

  defmacro __using__(_opts) do
    quote do
      @behaviour Badge.Page

      @impl true
      def handle_key(_event, _state), do: :ignore

      @impl true
      def tick(state), do: state

      @impl true
      def refresh, do: 100

      defoverridable handle_key: 2, tick: 1, refresh: 0
    end
  end
end
