defmodule Badge.Chat.Wire do
  @moduledoc """
  The Phoenix channel wire format, at vsn 2.0.0.

  Over a websocket each frame is one message, the five element array
  `[join_ref, ref, topic, event, payload]`:

      ["1","1","chat:lobby","phx_reply",{"status":"ok","response":{}}]

  Broadcasts carry no refs, and JSON null decodes to the atom `null` rather
  than `nil`, so refs are normalised here and callers only ever see `nil`.

  Everything in this module is pure; `Badge.Chat.Link` owns the socket.
  """

  @type message :: %{
          join_ref: binary | nil,
          ref: binary | nil,
          topic: binary,
          event: binary,
          payload: map
        }

  @doc "Reads one websocket text frame."
  @spec decode_frame(binary) :: {:ok, message} | :error
  def decode_frame(frame) do
    case json(frame) do
      {:ok, [join_ref, ref, topic, event, payload]} when is_binary(topic) and is_binary(event) ->
        {:ok,
         %{
           join_ref: plain(join_ref),
           ref: plain(ref),
           topic: topic,
           event: event,
           payload: payload
         }}

      _other ->
        :error
    end
  end

  @doc "A message ready to send."
  @spec encode(binary | nil, binary | nil, binary, binary, map) :: binary
  def encode(join_ref, ref, topic, event, payload) do
    # json:encode answers iodata, not a binary.
    :erlang.iolist_to_binary(:json.encode([json_null(join_ref), json_null(ref), topic, event, payload]))
  end

  defp json(body) do
    {:ok, :json.decode(body)}
  catch
    _kind, _error -> :error
  end

  # JSON null decodes to the atom null, which is not Elixir's nil.
  defp plain(:null), do: nil
  defp plain(value), do: value

  defp json_null(nil), do: :null
  defp json_null(value), do: value
end
