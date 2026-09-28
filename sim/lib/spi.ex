defmodule :spi do
  @moduledoc false

  # Set `:spi_fails` in the app env to act out a badge with no DMA buffer to spare.
  def write(_spi, :pixels, %{write_data: data}) when is_binary(data) do
    case Application.get_env(:avm_badge, :spi_fails, false) do
      true -> {:error, 257}
      false -> :ok
    end
  end
end
