defmodule Badge.Whenwhere do
  @moduledoc """
  Asks whenwhere.nerves-project.org where the badge is.

  The service answers with the zone name, coordinates and country for the
  address the request came from. It reports no UTC offset, so the zone name
  goes to `Badge.Zone` to become one.

  Plain HTTP rather than TLS on purpose: the system clock is set by SNTP, and
  a certificate cannot be checked before the clock is right.

  `fetch/0` blocks on the network and belongs in a process of its own;
  `parse/1` is pure.
  """

  @compile {:no_warn_undefined, :ahttp_client}

  @host "whenwhere.nerves-project.org"
  @port 80
  @path "/"

  # The whole answer is under 200 bytes, so one read almost always has it.
  @chunk 512
  @reads 16

  @type place :: %{zone: binary, latitude: binary, longitude: binary, country: binary}

  @doc "Where the badge is, or an error when the service cannot be reached."
  @spec fetch() :: {:ok, place} | {:error, term}
  def fetch do
    case :ahttp_client.connect(:http, @host, @port, active: false) do
      {:ok, conn} -> request(conn)
      {:error, reason} -> {:error, reason}
    end
  end

  defp request(conn) do
    case :ahttp_client.request(conn, "GET", @path, [], nil) do
      {:ok, conn, ref} -> collect(conn, ref, <<>>, @reads)
      {:error, reason} -> close(conn, {:error, reason})
    end
  end

  # Reads until the parser says the response is done, rather than trusting one read.
  defp collect(conn, _ref, _body, 0), do: close(conn, {:error, :too_many_reads})

  defp collect(conn, ref, body, left) do
    case :ahttp_client.recv(conn, @chunk) do
      {:ok, conn, responses} ->
        {body, done} = harvest(responses, body, false)

        continue(conn, ref, body, done, left)

      {:error, reason} ->
        close(conn, {:error, reason})
    end
  end

  defp continue(conn, _ref, body, true, _left), do: close(conn, parse(body))
  defp continue(conn, ref, body, false, left), do: collect(conn, ref, body, left - 1)

  defp harvest([], body, done), do: {body, done}
  defp harvest([{:data, _ref, chunk} | rest], body, done), do: harvest(rest, body <> chunk, done)
  defp harvest([{:done, _ref} | rest], body, _done), do: harvest(rest, body, true)
  defp harvest([:done | rest], body, _done), do: harvest(rest, body, true)
  defp harvest([_other | rest], body, done), do: harvest(rest, body, done)

  defp close(conn, result) do
    :ahttp_client.close(conn)

    result
  end

  @doc "Reads a response body, or `:error` when it is not one we can use."
  @spec parse(binary) :: {:ok, place} | :error
  def parse(body) do
    case decode(body) do
      {:ok, decoded} -> place(decoded)
      :error -> :error
    end
  end

  defp decode(body) do
    {:ok, :json.decode(body)}
  catch
    _kind, _error -> :error
  end

  # A place without a zone cannot set the clock, which is the point of asking.
  defp place(%{"time_zone" => zone} = decoded) when is_binary(zone) do
    {:ok,
     %{
       zone: zone,
       latitude: text(decoded, "latitude"),
       longitude: text(decoded, "longitude"),
       country: text(decoded, "country")
     }}
  end

  defp place(_decoded), do: :error

  defp text(decoded, key) do
    case Map.get(decoded, key) do
      value when is_binary(value) -> value
      _absent -> ""
    end
  end
end
