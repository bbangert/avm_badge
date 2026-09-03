defmodule Mix.Tasks.Badge.Assets do
  @shortdoc "Packs assets.avm from the frames and fonts the device reads at runtime"

  @moduledoc """
  Writes `assets.avm` at the repo root, ready for `tools/flashassets.sh`.

      mix badge.assets
  """

  use Mix.Task

  @out "assets.avm"

  @impl Mix.Task
  def run(_args) do
    stage = Path.join(System.tmp_dir!(), "badge-assets-#{System.unique_integer([:positive])}")
    rickroll = Path.join(stage, "assets/priv/rickroll")
    fonts = Path.join(stage, "assets/priv/fonts")

    try do
      File.mkdir_p!(rickroll)
      File.mkdir_p!(fonts)
      copy("assets/rickroll/*.rgba", rickroll)
      copy("assets/fonts/*.uf", fonts)

      out = Path.expand(@out)
      # Names inside the archive are relative to the staging directory.
      File.cd!(stage, fn ->
        inputs =
          (Path.wildcard("assets/priv/rickroll/*.rgba") ++
             Path.wildcard("assets/priv/fonts/*.uf"))
          |> Enum.map(&to_charlist/1)

        :ok = :packbeam_api.create(to_charlist(out), inputs, %{lib: true})
      end)

      Mix.shell().info("#{@out}: #{File.stat!(out).size} bytes")
    after
      File.rm_rf!(stage)
    end
  end

  defp copy(glob, dest) do
    for path <- Path.wildcard(glob), do: File.cp!(path, Path.join(dest, Path.basename(path)))
  end
end
