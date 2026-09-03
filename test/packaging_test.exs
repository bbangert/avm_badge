defmodule PackagingTest do
  use ExUnit.Case, async: true

  test "no dependency is resolved from a local path" do
    offenders =
      for {name, opts} <- Mix.Project.config()[:deps],
          is_list(opts),
          Keyword.has_key?(opts, :path),
          do: name

    assert offenders == [],
           "path deps do not exist on a collaborator's machine: #{inspect(offenders)}"
  end

  test "every git dependency is pinned to a full SHA" do
    unpinned =
      for {name, opts} <- Mix.Project.config()[:deps],
          is_list(opts),
          Keyword.has_key?(opts, :git) or Keyword.has_key?(opts, :github),
          not (is_binary(Keyword.get(opts, :ref)) and byte_size(Keyword.get(opts, :ref)) == 40),
          do: name

    assert unpinned == [],
           "a floating ref makes builds irreproducible: #{inspect(unpinned)}"
  end

  @root Path.expand("..", __DIR__)

  test "every generated font is one the firmware actually loads" do
    generated =
      Path.wildcard(Path.join(@root, "assets/fonts/*.uf"))
      |> Enum.map(&Path.basename(&1, ".uf"))
      |> Enum.sort()

    assert generated == ["dogica", "pixel_operator", "w95fa"]
  end

  test "asset sources live in the repo" do
    for path <- ["assets/src/fonts", "assets/src/icons"] do
      assert File.dir?(Path.join(@root, path)), "#{path} is missing"
    end

    assert File.exists?(Path.join(@root, "assets/src/icons/rickroll-roll.gif"))
  end
end
