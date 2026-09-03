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
end
