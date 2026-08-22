defmodule Badge.Chat.Wire do
  @moduledoc """
  The Phoenix long poll wire format, at vsn 2.0.0.

  A poll answers with an envelope whose `messages` are themselves JSON
  *strings*, so everything inside is decoded twice:

      {"status":200,"messages":["[\\"1\\",\\"1\\",\\"chat:lobby\\",\\"phx_reply\\",{}]"]}

  A message is the five element array `[join_ref, ref, topic, event, payload]`.
  Broadcasts carry no refs, and JSON null decodes to the atom `null` rather
  than `nil`, so refs are normalised here and callers only ever see `nil`.

  Everything in this module is pure; `Badge.Chat.Link` does the polling.
  """

  @type message :: %{
          join_ref: binary | nil,
          ref: binary | nil,
          topic: binary,
          event: binary,
          payload: map
        }

  @doc "Reads a poll response, or `:error` for anything that is not one."
  @spec decode(binary) :: {:ok, %{status: integer, token: binary | nil, messages: [message]}} | :error
  def decode(body) do
    case json(body) do
      {:ok, %{"status" => status} = envelope} when is_integer(status) ->
        {:ok, %{status: status, token: token(envelope), messages: harvest(envelope)}}

      _other ->
        :error
    end
  end

  @doc "Reads one message array out of its own JSON."
  @spec decode_message(binary) :: {:ok, list} | :error
  def decode_message(binary) do
    case json(binary) do
      {:ok, [join_ref, ref, topic, event, payload]} ->
        {:ok, [plain(join_ref), plain(ref), topic, event, payload]}

      _other ->
        :error
    end
  end

  @doc "A message ready to POST."
  @spec encode(binary | nil, binary | nil, binary, binary, map) :: binary
  def encode(join_ref, ref, topic, event, payload) do
    # json:encode answers iodata, not a binary.
    :erlang.iolist_to_binary(:json.encode([json_null(join_ref), json_null(ref), topic, event, payload]))
  end

  @doc """
  Builds a query string, escaping anything outside the unreserved set.

  A profile name reaches here verbatim, and names have spaces in them.
  """
  @spec query([{binary, binary}]) :: binary
  def query(pairs), do: query(pairs, <<>>)

  defp query([], acc), do: acc

  defp query([{key, value} | rest], <<>>) do
    query(rest, key <> "=" <> escape(value, <<>>))
  end

  defp query([{key, value} | rest], acc) do
    query(rest, acc <> "&" <> key <> "=" <> escape(value, <<>>))
  end

  defp escape(<<>>, acc), do: acc

  defp escape(<<char, rest::binary>>, acc) when char >= ?a and char <= ?z,
    do: escape(rest, acc <> <<char>>)

  defp escape(<<char, rest::binary>>, acc) when char >= ?A and char <= ?Z,
    do: escape(rest, acc <> <<char>>)

  defp escape(<<char, rest::binary>>, acc) when char >= ?0 and char <= ?9,
    do: escape(rest, acc <> <<char>>)

  defp escape(<<char, rest::binary>>, acc)
       when char == ?- or char == ?_ or char == ?. or char == ?~,
       do: escape(rest, acc <> <<char>>)

  defp escape(<<char, rest::binary>>, acc) do
    escape(rest, acc <> "%" <> <<hex(div(char, 16)), hex(rem(char, 16))>>)
  end

  defp hex(value) when value < 10, do: ?0 + value
  defp hex(value), do: ?A + value - 10

  defp json(body) do
    {:ok, :json.decode(body)}
  catch
    _kind, _error -> :error
  end

  defp token(%{"token" => token}) when is_binary(token), do: token
  defp token(_envelope), do: nil

  defp harvest(%{"messages" => messages}) when is_list(messages), do: messages(messages, [])
  defp harvest(_envelope), do: []

  # A message that will not decode is dropped: one bad frame must not cost the poll.
  defp messages([], acc), do: :lists.reverse(acc)

  defp messages([raw | rest], acc) when is_binary(raw) do
    case decode_message(raw) do
      {:ok, [join_ref, ref, topic, event, payload]} ->
        message = %{join_ref: join_ref, ref: ref, topic: topic, event: event, payload: payload}

        messages(rest, [message | acc])

      :error ->
        messages(rest, acc)
    end
  end

  defp messages([_raw | rest], acc), do: messages(rest, acc)

  # JSON null decodes to the atom null, which is not Elixir's nil.
  defp plain(:null), do: nil
  defp plain(value), do: value

  defp json_null(nil), do: :null
  defp json_null(value), do: value
end
