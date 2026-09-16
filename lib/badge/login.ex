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

  @default_url "https://goatbiz.fly.dev"
  @path "/api/badge_login"

  # How long the server holds a poll open, and how long the badge keeps asking.
  @long_seconds 25
  @total_seconds 480

  # Zero takes whatever one record carries; a count blocks until that many arrive.
  @chunk 0
  @reads 32

  @roles [staff: "staff", presenter: "presenter", attendee: "attendee"]

  # The site closes the socket after each answer, which is the surest end of one.
  @headers [{"accept", "application/json"}, {"connection", "close"}]
  @connect_opts [active: false, parse_headers: ["content-length"]]

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

  @doc "A role as the name badge wears it."
  @spec role_label(atom) :: binary
  def role_label(:staff), do: "STAFF"
  def role_label(:presenter), do: "SPEAKER"
  def role_label(:attendee), do: "ATTENDEE"
  def role_label(_role), do: ""

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
    case request(
           endpoint,
           "POST",
           @path,
           [{"content-type", "application/json"}],
           start_body(email)
         ) do
      {:ok, status, body} -> parse_start(status, body)
      {:error, reason} -> {:error, reason}
    end
  end

  defp poll(endpoint, token, long) do
    case request(endpoint, "GET", poll_path(token, long), [], nil) do
      {:ok, status, body} -> parse_poll(status, body)
      {:error, reason} -> {:error, reason}
    end
  end

  defp request({scheme, host, port}, method, path, headers, body) do
    case connect(scheme, host, port) do
      {:ok, conn} -> send_request(conn, method, path, headers ++ @headers, body)
      {:error, reason} -> {:error, {:connect, reason}}
    end
  end

  # ssl has no clause for active mode, so both transports read on demand.
  defp connect(:https, host, port) do
    :ssl.start()
    :ahttp_client.connect(:https, host, port, @connect_opts ++ [verify: :verify_none])
  end

  defp connect(:http, host, port) do
    :ahttp_client.connect(:http, host, port, @connect_opts)
  end

  defp send_request(conn, method, path, headers, body) do
    case :ahttp_client.request(conn, method, path, headers, body) do
      {:ok, conn, _ref} -> collect(conn, reply(), @reads)
      {:error, reason} -> close(conn, {:error, {:request, reason}})
    end
  end

  defp collect(conn, _reply, 0), do: close(conn, {:error, :too_many_reads})

  defp collect(conn, reply, left) do
    case :ahttp_client.recv(conn, @chunk) do
      {:ok, conn, responses} -> continue(conn, absorb(responses, reply), left)
      {:error, reason} -> close(conn, settle(reply, {:error, {:recv, reason}}))
    end
  end

  defp continue(conn, reply, left) do
    case complete?(reply) do
      true -> close(conn, settle(reply, {:error, :bad_response}))
      false -> collect(conn, reply, left - 1)
    end
  end

  @doc "An answer with nothing read yet."
  @spec reply() :: map
  def reply, do: %{status: nil, body: <<>>, length: nil, done: false}

  @doc """
  Folds what one read produced into the answer so far.

  The driver only recognises `Content-Length` spelled that way, and the site
  spells it in lower case, so the length is tracked here as well.
  """
  @spec absorb([tuple | atom], map) :: map
  def absorb([], reply), do: reply

  def absorb([{:status, _ref, code} | rest], reply), do: absorb(rest, %{reply | status: code})

  def absorb([{:header, _ref, {"content-length", value}} | rest], reply) do
    absorb(rest, %{reply | length: declared(value)})
  end

  def absorb([{:data, _ref, chunk} | rest], reply) do
    absorb(rest, %{reply | body: reply.body <> chunk})
  end

  def absorb([{:done, _ref} | rest], reply), do: absorb(rest, %{reply | done: true})
  def absorb([:done | rest], reply), do: absorb(rest, %{reply | done: true})
  def absorb([_other | rest], reply), do: absorb(rest, reply)

  defp declared(value) do
    :erlang.binary_to_integer(value)
  catch
    _kind, _error -> nil
  end

  @doc "Whether the whole answer has arrived."
  @spec complete?(map) :: boolean
  def complete?(%{done: true}), do: true
  def complete?(%{length: nil}), do: false
  def complete?(%{length: length, body: body}), do: byte_size(body) >= length

  @doc """
  The answer as `{:ok, status, body}`, or `otherwise` when it never became one.

  A socket the server closed after a whole answer is still a whole answer.
  """
  @spec settle(map, term) :: {:ok, integer, binary} | term
  def settle(%{status: status} = reply, _otherwise) when is_integer(status) do
    case complete?(reply) or (reply.length == nil and reply.body != <<>>) do
      true -> {:ok, status, reply.body}
      false -> {:error, :bad_response}
    end
  end

  def settle(_reply, otherwise), do: otherwise

  defp close(conn, result) do
    :ahttp_client.close(conn)

    result
  end
end
