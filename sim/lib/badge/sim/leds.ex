defmodule Badge.Sim.Leds do
  @moduledoc """
  Stands in for the `leds` port driver: accepts what the real one would and
  keeps the last request of each kind, for tests to read with `last/1`.
  """

  @doc "A chain handle; the simulator has no LEDs to open."
  def open(_pin, _count), do: :sim_leds

  def call(:sim_leds, request) do
    :persistent_term.put({__MODULE__, elem(request, 0)}, request)
    :ok
  end

  @doc "The last `:effect`, `:flash`, `:raw` or `:order` request, or nil."
  def last(kind), do: :persistent_term.get({__MODULE__, kind}, nil)

  @doc "Forgets every request, for a test that starts clean."
  def reset do
    for kind <- [:effect, :flash, :raw, :order], do: :persistent_term.erase({__MODULE__, kind})
    :ok
  end
end
