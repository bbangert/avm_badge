defmodule Badge.Ir do
  @moduledoc """
  The IR beam, as a link any page can use.

  `send/1` puts bytes on the beam; frames that arrive reach the page on
  screen through its `handle_ir/3` callback:

      Badge.Ir.send("hello")

  Nothing is transmitted unless a page asks for it. The payload is opaque
  and the sender's chip id travels in the frame header, so a page never has
  to put its own identity in its bytes.
  """

  alias Badge.Ir.Frame
  alias Badge.Ir.Link

  # A guard cannot call a function, and module attributes run on the host compiler.
  @max_payload Frame.max_payload()

  @doc """
  Puts a payload on the beam.

  Returns without waiting: the frame goes out on the link's next pass,
  at most one read window away.
  """
  @spec send(binary) :: :ok | {:error, :too_long}
  def send(payload) when byte_size(payload) > @max_payload, do: {:error, :too_long}
  def send(payload) when is_binary(payload), do: Link.transmit(payload)

  @doc "The largest payload a frame carries."
  @spec max_payload() :: pos_integer
  def max_payload, do: @max_payload
end
