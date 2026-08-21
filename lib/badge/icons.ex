defmodule Badge.Icons do
  @moduledoc """
  Converted artwork from `priv/icons`, baked into the module at compile time.

  Files are named `<name>@<width>x<height>.rgba` and hold raw `rgba8888`
  already composited onto black, every pixel fully opaque. That keeps AtomGL
  on its no-blend fast path and costs nothing visually because the panel
  background is black.

  Shapes are 32x32 and status icons are 16x16, so read `size/1` rather than
  assuming. Regenerate the files with `tools/icons.py`.
  """

  alias Badge.Theme

  @bg Theme.bg()

  @dir Path.expand("../../priv/icons", __DIR__)
  @shapes [:square, :triangle, :cross, :circle, :clover, :diamond]

  File.dir?(@dir) || raise "no icon directory at #{@dir} — run tools/icons.py"

  # The directory itself, so adding or removing an icon recompiles this module.
  # Per-file @external_resource cannot track a file that does not exist yet.
  @external_resource @dir

  @files Enum.sort(Path.wildcard(Path.join(@dir, "*.rgba")))

  @files != [] || raise "no .rgba files in #{@dir} — run tools/icons.py"

  for file <- @files do
    @external_resource file
  end

  # Parsed and checked on the host, where the full standard library is available.
  @icons (for path <- @files, into: %{} do
            base = Path.basename(path, ".rgba")

            # Host-only: the names come from a directory in this repo, not from input.
            {name, width, height} =
              case String.split(base, "@") do
                [name, dimensions] ->
                  case String.split(dimensions, "x") do
                    [width, height] ->
                      {String.to_atom(name), String.to_integer(width), String.to_integer(height)}

                    _ ->
                      raise "icon #{base}: expected <name>@<width>x<height>.rgba"
                  end

                _ ->
                  raise "icon #{base}: expected <name>@<width>x<height>.rgba"
              end

            data = File.read!(path)
            expected = width * height * 4

            byte_size(data) == expected ||
              raise "icon #{base}: #{byte_size(data)} bytes, expected #{expected}"

            {name, {width, height, data}}
          end)

  case @shapes -- Map.keys(@icons) do
    [] -> :ok
    missing -> raise "missing shape icons: #{Enum.join(missing, ", ")}"
  end

  @names Enum.sort(Map.keys(@icons))

  @doc "Every icon name, sorted."
  def names, do: @names

  @doc "The raw `rgba8888` binary for one icon, or nil if there is no such icon."
  def binary(name)

  for {name, {_width, _height, data}} <- @icons do
    def binary(unquote(name)), do: unquote(data)
  end

  def binary(_name), do: nil

  @doc "The icon's `{width, height}` in pixels, or nil if there is no such icon."
  def size(name)

  for {name, {width, height, _data}} <- @icons do
    def size(unquote(name)), do: {unquote(width), unquote(height)}
  end

  def size(_name), do: nil

  @doc "A display item drawing `name` at native size, top-left corner at `x, y`."
  def item(name, x, y) do
    {width, height} = size(name)

    {:image, x, y, @bg, {:rgba8888, width, height, binary(name)}}
  end
end
