defmodule Badge.Pages do
  @moduledoc """
  Which shape key opens which page.

  Ordered to match the physical button row on the badge, so `all/0` is also
  the reading order of the home grid. A slot may be `nil`: its button does
  nothing and the home grid leaves its cell empty.
  """

  @pages [
    {:square, Badge.Page.Text},
    {:triangle, Badge.Page.Sensors},
    {:cross, Badge.Page.Soon},
    {:circle, Badge.Page.Settings},
    {:clover, Badge.Page.Led},
    {:diamond, Badge.Page.Name}
  ]

  @doc "Every slot, in button order."
  def all, do: @pages

  @doc "The page module for a shape key, or nil when the slot is unassigned."
  def for_key(key) do
    case :lists.keyfind(key, 1, @pages) do
      {_key, module} -> module
      false -> nil
    end
  end
end
