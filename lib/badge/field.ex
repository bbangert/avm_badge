defmodule Badge.Field do
  @moduledoc """
  A single-line text field with a capacity and a cursor.

  `Badge.TextBuffer` is a full grid editor with wrapping and scrolling, which
  is the wrong shape here. The text is split around the cursor: `left` holds
  what precedes it, reversed, so insertion stays O(1); `right` holds what
  follows, in order.

  State is a plain map, not a struct.
  """

  @doc "An empty field holding at most `capacity` characters."
  @spec new(pos_integer) :: map
  def new(capacity), do: %{left: [], right: [], count: 0, cursor: 0, capacity: capacity}

  @doc "Inserts one character at the cursor, or leaves the field alone when it is full."
  @spec insert(map, integer) :: map
  def insert(%{count: count, capacity: capacity} = field, _char) when count >= capacity do
    field
  end

  def insert(field, char) do
    %{field | left: [char | field.left], count: field.count + 1, cursor: field.cursor + 1}
  end

  @doc "Removes the character before the cursor, or leaves the field alone at the start."
  @spec backspace(map) :: map
  def backspace(%{left: []} = field), do: field

  def backspace(%{left: [_last | rest]} = field) do
    %{field | left: rest, count: field.count - 1, cursor: field.cursor - 1}
  end

  @doc "Moves the cursor one character towards the start."
  @spec left(map) :: map
  def left(%{left: []} = field), do: field

  def left(%{left: [char | rest]} = field) do
    %{field | left: rest, right: [char | field.right], cursor: field.cursor - 1}
  end

  @doc "Moves the cursor one character towards the end."
  @spec right(map) :: map
  def right(%{right: []} = field), do: field

  def right(%{right: [char | rest]} = field) do
    %{field | left: [char | field.left], right: rest, cursor: field.cursor + 1}
  end

  @doc "The text entered so far."
  @spec value(map) :: binary
  def value(field), do: :erlang.list_to_binary(:lists.reverse(field.left) ++ field.right)

  @doc "Where the cursor sits, counted from the start."
  @spec cursor(map) :: non_neg_integer
  def cursor(field), do: field.cursor

  @doc "How many characters may still be entered."
  @spec remaining(map) :: non_neg_integer
  def remaining(field), do: max(field.capacity - field.count, 0)

  @doc "How many characters the field accepts in total."
  @spec capacity(map) :: non_neg_integer
  def capacity(field), do: field.capacity

  @doc "Changes the capacity, keeping whatever has already been entered."
  @spec resize(map, non_neg_integer) :: map
  def resize(field, capacity), do: %{field | capacity: capacity}

  @doc "One asterisk per character, for display."
  @spec masked(map) :: binary
  def masked(field), do: :erlang.list_to_binary(:lists.duplicate(field.count, ?*))

  @doc "How many characters have been entered."
  @spec length(map) :: non_neg_integer
  def length(field), do: field.count
end
