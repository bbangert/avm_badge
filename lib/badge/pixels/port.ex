defmodule Badge.Pixels.Port do
  @moduledoc "The LED chain through the VM's `leds` port driver."

  @compile {:no_warn_undefined, [:port]}

  @doc "Opens the chain on a GPIO; the driver starts it dark."
  @spec open(non_neg_integer, pos_integer) :: port
  def open(pin, count), do: :erlang.open_port({:spawn, ~c"leds"}, pin: pin, count: count)

  @doc "Sends the driver a request; see `Badge.LedEffect` for what they are."
  @spec call(port, tuple) :: :ok | :badarg
  def call(chain, request), do: :port.call(chain, request)
end
