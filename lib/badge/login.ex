defmodule Badge.Login do
  @moduledoc """
  Signs the badge in to Goatmire as a ticket holder.

  The badge posts an email to the conference site, which mails the holder a
  link, and the badge long-polls until the link is opened. What comes back
  is the email and a role, kept in NVS so the badge stays signed in across
  reboots. The site never logs a user in on the strength of this; it only
  confirms the badge.

  `flow/3` runs the whole exchange and blocks on the network, so it belongs
  in a process of its own; `Badge.Page.Login` spawns one and takes the
  answers as messages. Everything that parses or formats is pure.

  The server is the `login_url` NVS key, falling back to the compiled
  default. AtomVM's `ssl` pins TLS 1.2 and offers no certificate
  verification, so an `https://` server is encrypted but unauthenticated; a
  server on the bench is reached over `http://<lan-ip>:4000`.
  """

  alias Badge.Nvs

  @compile {:no_warn_undefined, :ahttp_client}
  @compile {:no_warn_undefined, :ssl}

  @default_url "https://goatmire.com"
  @path "/api/badge_login"

  # How long the server holds a poll open, and how long the badge keeps asking.
  @long_seconds 25
  @total_seconds 480

  # Answers run to a few hundred bytes; a slow link needs several reads.
  @chunk 512
  @reads 32

  @roles [staff: "staff", presenter: "presenter", attendee: "attendee"]

  @type account :: %{email: binary, role: atom}

  @doc "The server a badge talks to when nothing is provisioned."
  @spec default_url() :: binary
  def default_url, do: @default_url

  @doc "The provisioned server, or the compiled default when there is none."
  @spec base_url(binary | nil) :: binary
  def base_url(nil), do: @default_url
  def base_url(""), do: @default_url
  def base_url(url), do: url

  @doc "The provisioned server, read from NVS."
  @spec server() :: binary
  def server, do: base_url(Nvs.get(:login_url))

  @doc "How long the badge waits for the link to be opened, in seconds."
  def total_seconds, do: @total_seconds

  ## Storage

  @doc "The signed-in account, or nil when the badge is signed out."
  @spec load() :: account | nil
  def load, do: account(Nvs.get(:login_email), Nvs.get(:login_role))

  @doc "Keeps an account across reboots."
  @spec save(account) :: :ok
  def save(%{email: email, role: role}) do
    Nvs.put(:login_email, email)
    Nvs.put(:login_role, role_name(role))

    :ok
  end

  @doc "Signs the badge out."
  @spec clear() :: :ok
  def clear do
    Nvs.delete(:login_email)
    Nvs.delete(:login_role)

    :ok
  end

  @doc "An account from its stored parts, or nil when either is missing or unknown."
  @spec account(binary | nil, binary | nil) :: account | nil
  def account(email, role_name) when is_binary(email) and is_binary(role_name) do
    case role(role_name) do
      nil -> nil
      role -> %{email: email, role: role}
    end
  end

  def account(_email, _role), do: nil

  @doc "The role an API answer names, or nil for one this firmware does not know."
  @spec role(binary) :: atom | nil
  def role(name) do
    case :lists.keyfind(name, 2, @roles) do
      {role, _name} -> role
      false -> nil
    end
  end

  @doc "How a role is spelled, on the wire and on the panel."
  @spec role_name(atom) :: binary
  def role_name(role) do
    case :lists.keyfind(role, 1, @roles) do
      {_role, name} -> name
      false -> "unknown"
    end
  end

  ## Wire

  @doc "Scheme, host and port from a base URL, or `:error` when it is not one."
  @spec endpoint(binary) :: {:ok, :http | :https, binary, integer} | :error
  def endpoint(<<"https://", rest::binary>>), do: host_port(:https, rest, 443)
  def endpoint(<<"http://", rest::binary>>), do: host_port(:http, rest, 80)
  def endpoint(_url), do: :error

  defp host_port(scheme, rest, default) do
    authority = hd(:binary.split(rest, "/"))

    case :binary.split(authority, ":") do
      [""] -> :error
      [host] -> {:ok, scheme, host, default}
      [host, port] -> port(scheme, host, port)
    end
  end

  defp port(scheme, host, port) do
    {:ok, scheme, host, :erlang.binary_to_integer(port)}
  catch
    _kind, _error -> :error
  end

  @doc "The JSON the site expects when a login starts."
  @spec start_body(binary) :: binary
  def start_body(email) do
    :erlang.iolist_to_binary(:json.encode(%{"email" => email}))
  end

  @doc "The path that starts a login."
  def start_path, do: @path

  @doc "The path that asks after a login, holding the answer up to `long` seconds."
  @spec poll_path(binary, non_neg_integer) :: binary
  def poll_path(token, 0), do: @path <> "/" <> token

  def poll_path(token, long) do
    @path <> "/" <> token <> "?long=" <> :erlang.integer_to_binary(long)
  end

  @doc "Reads the answer to a start: the token to poll with."
  @spec parse_start(integer, binary) :: {:ok, binary} | {:error, term}
  def parse_start(200, body) do
    case decode(body) do
      {:ok, %{"request_token" => token}} when is_binary(token) -> {:ok, token}
      _other -> {:error, :bad_response}
    end
  end

  def parse_start(status, _body), do: {:error, {:http, status}}

  @doc "Reads the answer to a poll: still pending, verified, or forgotten by the server."
  @spec parse_poll(integer, binary) ::
          {:ok, :pending} | {:ok, {:verified, account}} | {:error, term}
  def parse_poll(200, body) do
    case decode(body) do
      {:ok, %{"status" => "pending"}} -> {:ok, :pending}
      {:ok, %{"status" => "verified", "email" => email, "role" => role}} -> verified(email, role)
      _other -> {:error, :bad_response}
    end
  end

  def parse_poll(404, _body), do: {:error, :unknown_token}
  def parse_poll(status, _body), do: {:error, {:http, status}}

  defp verified(email, role) when is_binary(email) and is_binary(role) do
    case account(email, role) do
      nil -> {:error, {:role, role}}
      account -> {:ok, {:verified, account}}
    end
  end

  defp verified(_email, _role), do: {:error, :bad_response}

  defp decode(body) do
    {:ok, :json.decode(body)}
  catch
    _kind, _error -> :error
  end

  @doc "What went wrong, in words that fit the panel."
  @spec describe(term) :: binary
  def describe(:no_wifi), do: "no wifi connection"
  def describe(:timeout), do: "no confirmation in time"
  def describe(:unknown_token), do: "the link has expired"
  def describe(:bad_url), do: "login server misconfigured"
  def describe(:bad_response), do: "the server made no sense"
  def describe({:http, status}), do: "server said " <> :erlang.integer_to_binary(status)
  def describe({:role, _role}), do: "unknown ticket role"
  def describe({:connect, _reason}), do: "could not reach the server"
  def describe(_reason), do: "network error"

  ## Flow

  @doc """
  Starts a login for `email` at `base` and polls until it is verified.

  Every step is reported through `notify`, which is handed `{:login, event}`:
  `{:sent, token}` once the site has taken the email, then either
  `{:verified, account}` or `{:failed, reason}`. Blocks for as long as the
  exchange takes, up to `total_seconds/0`.
  """
  @spec flow(binary, binary, (term -> any)) :: :ok
  def flow(base, email, notify) do
    case endpoint(base) do
      {:ok, scheme, host, port} -> run(email, notify, {scheme, host, port})
      :error -> report(notify, {:failed, :bad_url})
    end
  end

  defp run(email, notify, endpoint) do
    case start(endpoint, email) do
      {:ok, token} ->
        report(notify, {:sent, token})
        deadline = now() + @total_seconds

        report(notify, poll_until(endpoint, token, deadline))

      {:error, reason} ->
        report(notify, {:failed, reason})
    end
  end

  defp poll_until(endpoint, token, deadline) do
    remaining = deadline - now()

    case remaining > 0 do
      true ->
        settle(poll(endpoint, token, min(@long_seconds, remaining)), endpoint, token, deadline)

      false ->
        {:failed, :timeout}
    end
  end

  defp settle({:ok, :pending}, endpoint, token, deadline),
    do: poll_until(endpoint, token, deadline)

  defp settle({:ok, {:verified, account}}, _endpoint, _token, _deadline), do: {:verified, account}
  defp settle({:error, reason}, _endpoint, _token, _deadline), do: {:failed, reason}

  defp report(notify, event) do
    notify.({:login, event})

    :ok
  end

  defp now, do: :erlang.monotonic_time(:second)

  defp start(endpoint, email) do
    headers = [{"content-type", "application/json"}, {"accept", "application/json"}]

    case request(endpoint, "POST", @path, headers, start_body(email)) do
      {:ok, status, body} -> parse_start(status, body)
      {:error, reason} -> {:error, reason}
    end
  end

  defp poll(endpoint, token, long) do
    case request(endpoint, "GET", poll_path(token, long), [{"accept", "application/json"}], nil) do
      {:ok, status, body} -> parse_poll(status, body)
      {:error, reason} -> {:error, reason}
    end
  end

  defp request({scheme, host, port}, method, path, headers, body) do
    case connect(scheme, host, port) do
      {:ok, conn} -> send_request(conn, method, path, headers, body)
      {:error, reason} -> {:error, {:connect, reason}}
    end
  end

  # ssl has no clause for active mode, so both transports read on demand.
  defp connect(:https, host, port) do
    :ssl.start()
    :ahttp_client.connect(:https, host, port, active: false, verify: :verify_none)
  end

  defp connect(:http, host, port) do
    :ahttp_client.connect(:http, host, port, active: false)
  end

  defp send_request(conn, method, path, headers, body) do
    case :ahttp_client.request(conn, method, path, headers, body) do
      {:ok, conn, _ref} -> collect(conn, nil, <<>>, @reads)
      {:error, reason} -> close(conn, {:error, {:request, reason}})
    end
  end

  defp collect(conn, _status, _body, 0), do: close(conn, {:error, :too_many_reads})

  defp collect(conn, status, body, left) do
    case :ahttp_client.recv(conn, @chunk) do
      {:ok, conn, responses} ->
        {status, body, done} = harvest(responses, status, body, false)

        continue(conn, status, body, done, left)

      {:error, reason} ->
        close(conn, {:error, {:recv, reason}})
    end
  end

  defp continue(conn, nil, _body, true, _left), do: close(conn, {:error, :bad_response})
  defp continue(conn, status, body, true, _left), do: close(conn, {:ok, status, body})
  defp continue(conn, status, body, false, left), do: collect(conn, status, body, left - 1)

  defp harvest([], status, body, done), do: {status, body, done}

  defp harvest([{:status, _ref, code} | rest], _status, body, done),
    do: harvest(rest, code, body, done)

  defp harvest([{:data, _ref, chunk} | rest], status, body, done),
    do: harvest(rest, status, body <> chunk, done)

  defp harvest([{:done, _ref} | rest], status, body, _done), do: harvest(rest, status, body, true)
  defp harvest([:done | rest], status, body, _done), do: harvest(rest, status, body, true)
  defp harvest([_other | rest], status, body, done), do: harvest(rest, status, body, done)

  defp close(conn, result) do
    :ahttp_client.close(conn)

    result
  end
end
