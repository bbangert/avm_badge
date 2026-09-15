defmodule Badge.Alisp do
  @moduledoc """
  Line-at-a-time front end to AtomVM's `alisp`.

  A session holds the tokens of a form whose parentheses have not closed
  yet, so a form can be typed over several lines. `feed/2` says whether
  a line completed one. Evaluation runs in a worker from `start/1`, which
  owns the Lisp variables and answers the process that started it with
  `{:alisp, worker, {:ok, text} | {:error, text}}`, so a form that never
  returns can be killed without touching `Badge.UI`.
  """

  @max_output 240

  @doc "A session with nothing pending."
  def new, do: %{tokens: [], depth: 0}

  @doc "Whether a form is waiting for more lines."
  def pending?(session), do: session.depth > 0

  @doc """
  Adds a line to the session.

  Returns `{:eval, session, form}` when the line closed a form, `{:pending,
  session}` when more lines are needed or the line was empty, and `{:error,
  session, text}` when it could not be read; the session is then reset.
  """
  def feed(session, line) do
    case tokenize(line) do
      {:error, text} -> {:error, new(), text}
      [] -> {:pending, session}
      tokens -> feed_tokens(session, tokens)
    end
  end

  defp feed_tokens(session, tokens) do
    depth = balance(tokens, session.depth)
    all = session.tokens ++ tokens

    cond do
      depth < 0 -> {:error, new(), "unbalanced )"}
      depth > 0 -> {:pending, %{tokens: all, depth: depth}}
      true -> parsed(all)
    end
  end

  defp parsed(tokens) do
    case parse(tokens) do
      {:ok, form} -> {:eval, new(), form}
      {:error, text} -> {:error, new(), text}
    end
  end

  @doc "Spawns a worker that evaluates for `owner`."
  def start(owner), do: spawn(fn -> boot(owner) end)

  @doc "Asks the worker to evaluate a parsed form."
  def eval(worker, form), do: send(worker, {:eval, form})

  @doc "Kills the worker, and every variable it held."
  def stop(worker), do: :erlang.exit(worker, :kill)

  @doc "Evaluates a form in the calling process, as text."
  def run(form) do
    try do
      {:ok, format(:alisp.eval(form))}
    catch
      kind, reason -> {:error, format({kind, reason})}
    end
  end

  @doc "A term as alisp would print it, clipped to a screenful."
  def format(term) do
    try do
      clip(:erlang.iolist_to_binary(:sexp_serializer.serialize(term)))
    catch
      _kind, _reason -> "(unprintable)"
    end
  end

  defp boot(owner) do
    # Forces the library to load, as arepl does before its first eval.
    :alisp_stdlib.car([[:hack]])
    loop(owner)
  end

  defp loop(owner) do
    receive do
      {:eval, form} ->
        send(owner, {:alisp, self(), run(form)})
        loop(owner)
    end
  end

  defp tokenize(line) do
    try do
      :sexp_lexer.string(line)
    catch
      _kind, _reason -> {:error, "cannot read line"}
    end
  end

  defp balance([], depth), do: depth
  defp balance([{:"(", _line} | rest], depth), do: balance(rest, depth + 1)
  defp balance([{:")", _line} | rest], depth), do: balance(rest, depth - 1)
  defp balance([_token | rest], depth), do: balance(rest, depth)

  # A lone literal is its own value; the parser only reads lists.
  defp parse([{:integer, _line, int}]), do: {:ok, int}
  defp parse([{:binary, _line, bin}]), do: {:ok, bin}
  defp parse([{:symbol, _line, sym}]), do: {:ok, :erlang.list_to_atom(sym)}

  defp parse(tokens) do
    try do
      case :sexp_parser.parse(tokens) do
        form when is_list(form) -> {:ok, form}
        {_rest, _form} -> {:error, "one form at a time"}
      end
    catch
      _kind, _reason -> {:error, "cannot parse form"}
    end
  end

  defp clip(text) when byte_size(text) <= @max_output, do: text
  defp clip(text), do: :binary.part(text, 0, @max_output - 3) <> "..."
end
