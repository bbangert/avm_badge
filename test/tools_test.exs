defmodule ToolsTest do
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)

  test "every tool with a shebang is executable in git" do
    {listing, 0} = System.cmd("git", ["ls-files", "-s", "tools/"], cd: @root)

    offenders =
      for line <- String.split(listing, "\n", trim: true),
          [meta, path] = String.split(line, "\t", parts: 2),
          [mode | _] = String.split(meta, " "),
          File.read!(Path.join(@root, path)) |> String.starts_with?("#!"),
          mode != "100755",
          do: {path, mode}

    assert offenders == [],
           "a script with a shebang must be mode 100755: #{inspect(offenders)}"
  end
end
