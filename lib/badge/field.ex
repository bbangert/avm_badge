defmodule Badge.Field do
  @moduledoc """
  A single-line text field with a capacity, for entering a passphrase.

  `Badge.TextBuffer` is a full grid editor with wrapping and scrolling, which
  is the wrong shape here. Characters accumulate as a reversed charlist for
  O(1) insertion and become a binary only in `value/1`.

  State is a plain map, not a struct.
  """

  @doc "An empty field holding at most `capacity` characters."
  @spec new(pos_integer) :: map
  def new(capacity), do: %{chars: [], count: 0, capacity: capacity}

  @doc "Appends one character, or leaves the field alone when it is full."
  @spec insert(map, integer) :: map
  def insert(%{count: count, capacity: capacity} = field, _char) when count >= capacity do
    field
  end

  def insert(field, char) do
    %{field | chars: [char | field.chars], count: field.count + 1}
  end

  @doc "Removes the last character, or leaves an empty field alone."
  @spec backspace(map) :: map
  def backspace(%{chars: []} = field), do: field

  def backspace(%{chars: [_last | rest]} = field) do
    %{field | chars: rest, count: field.count - 1}
  end

  @doc "The text entered so far."
  @spec value(map) :: binary
  def value(field), do: :erlang.list_to_binary(:lists.reverse(field.chars))

  @doc "One asterisk per character, for display."
  @spec masked(map) :: binary
  def masked(field), do: :erlang.list_to_binary(:lists.duplicate(field.count, ?*))

  @doc "How many characters have been entered."
  @spec length(map) :: non_neg_integer
  def length(field), do: field.count
end
