defmodule Badge.Clock do
  @moduledoc """
  Formats a number of seconds as a clock face.

  The badge has no RTC and no time sync, so what the title bar shows is
  uptime. Swapping in a real wall clock is a change of argument, not a
  change here.
  """

  @day 86_400
  @hour 3_600
  @minute 60

  @doc "Formats seconds as HH:MM:SS, wrapping after a day."
  @spec format(integer) :: binary
  def format(seconds) when seconds < 0, do: format(0)

  def format(seconds) do
    within_day = rem(seconds, @day)

    pad(div(within_day, @hour)) <>
      ":" <> pad(div(rem(within_day, @hour), @minute)) <> ":" <> pad(rem(within_day, @minute))
  end

  defp pad(value) when value < 10, do: "0" <> :erlang.integer_to_binary(value)
  defp pad(value), do: :erlang.integer_to_binary(value)
end
