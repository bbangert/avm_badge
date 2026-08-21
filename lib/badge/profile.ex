defmodule Badge.Profile do
  @moduledoc """
  What the name badge says about its owner.

  Field definitions live here rather than in the page, so the editor, the
  display and the stored keys cannot drift apart. Values are binaries;
  absent and empty mean the same thing.
  """

  alias Badge.Nvs

  # {key, label, capacity, icon shown beside it on the badge}
  @fields [
    {:name, "Name", 18, nil},
    {:company, "Company", 30, :company},
    {:email, "Email", 32, :email},
    {:github, "GitHub", 26, :github},
    {:mastodon, "Mastodon", 30, :mastodon},
    {:bluesky, "Bluesky", 30, :bluesky},
    {:links, "Link", 32, :link}
  ]

  @required :name
  @placeholder "Nameless"

  @doc "Every field, in the order they are edited and shown."
  def fields, do: @fields

  @doc "Field keys, in order."
  def keys, do: for({key, _label, _capacity, _prefix} <- @fields, do: key)

  @doc "How many characters a field holds."
  @spec capacity(atom) :: pos_integer
  def capacity(key), do: lookup(@fields, key, 3, 20)

  @doc "The label shown beside a field in the editor."
  @spec label(atom) :: binary
  def label(key), do: lookup(@fields, key, 1, "")

  @doc "The icon shown beside a value on the badge, or nil for a plain line."
  @spec icon(atom) :: atom | nil
  def icon(key), do: lookup(@fields, key, 3, nil)

  @doc "The one field that must be filled in."
  def required, do: @required

  @doc "An empty profile."
  @spec blank() :: map
  def blank, do: for(key <- keys(), into: %{}, do: {key, ""})

  @doc "The name to show when none was entered."
  def placeholder, do: @placeholder

  @doc "Whether a profile has everything it needs."
  @spec complete?(map) :: boolean
  def complete?(profile), do: present?(Map.get(profile, @required))

  @doc "Whether a value is worth showing."
  @spec present?(binary | nil) :: boolean
  def present?(nil), do: false
  def present?(""), do: false
  def present?(_value), do: true

  @doc "The name to display, falling back when it was left empty."
  @spec display_name(map) :: binary
  def display_name(profile) do
    case Map.get(profile, @required) do
      value when value in [nil, ""] -> @placeholder
      value -> value
    end
  end

  @doc """
  The lines the badge shows under the rule, as `{icon, text}`.

  Links are split on spaces, so one field can hold several and each gets a
  line of its own, all carrying the same icon.
  """
  @spec lines(map) :: [{atom | nil, binary}]
  def lines(profile) do
    :lists.append(for key <- keys(), key != @required, do: field_lines(profile, key))
  end

  @doc "Reads the stored profile."
  @spec load() :: map
  def load, do: for(key <- keys(), into: %{}, do: {key, Nvs.get(key) || ""})

  @doc "Stores a profile."
  @spec save(map) :: :ok
  def save(profile) do
    for key <- keys(), do: Nvs.put(key, Map.get(profile, key) || "")

    :ok
  end

  defp field_lines(profile, :links) do
    for link <- split_words(Map.get(profile, :links, "")), do: {icon(:links), link}
  end

  defp field_lines(profile, key) do
    value = Map.get(profile, key, "")

    case present?(value) do
      true -> [{icon(key), value}]
      false -> []
    end
  end

  # Hand-rolled: AtomVM has no String module at runtime.
  defp split_words(value), do: split_words(value, <<>>, [])

  defp split_words(<<>>, <<>>, acc), do: :lists.reverse(acc)
  defp split_words(<<>>, word, acc), do: :lists.reverse([word | acc])

  defp split_words(<<?\s, rest::binary>>, <<>>, acc), do: split_words(rest, <<>>, acc)
  defp split_words(<<?\s, rest::binary>>, word, acc), do: split_words(rest, <<>>, [word | acc])

  defp split_words(<<char, rest::binary>>, word, acc) do
    split_words(rest, word <> <<char>>, acc)
  end

  defp lookup([], _key, _position, fallback), do: fallback

  defp lookup([entry | _rest], key, position, _fallback) when elem(entry, 0) == key do
    elem(entry, position)
  end

  defp lookup([_entry | rest], key, position, fallback), do: lookup(rest, key, position, fallback)
end
