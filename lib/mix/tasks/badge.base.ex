defmodule Mix.Tasks.Badge.Base do
  @shortdoc "Downloads and flashes the AtomVM base image this firmware expects"

  @moduledoc """
  Fetches the release named in `BASE_IMAGE` and writes it to the board.

      mix badge.base          # the VM only, at 0x10000
      mix badge.base --full   # bootloader, partition table and VM, for a new board

  The application at 0x2B8000 survives a VM-only flash.
  """

  use Mix.Task

  @repo "protolux-electronics/AtomVM"
  @cache ".base"
  @vm {"atomvm-esp32s3-badge.bin", "0x10000"}
  @bootloader {"bootloader.bin", "0x0"}
  @table {"partition-table.bin", "0x8000"}
  @sums "SHA256SUMS"

  @impl Mix.Task
  def run(args) do
    tag = "BASE_IMAGE" |> File.read!() |> String.trim()
    dir = Path.join(@cache, tag)
    parts = if "--full" in args, do: [@bootloader, @table, @vm], else: [@vm]

    download(tag, dir)
    flash(dir, parts)
  end

  defp download(tag, dir) do
    if File.dir?(dir) do
      Mix.shell().info("base image #{tag} already downloaded")
    else
      File.mkdir_p!(dir)
      Mix.shell().info("downloading base image #{tag}")
      cmd!("gh", ["release", "download", tag, "--repo", @repo, "-D", dir])
      verify!(dir)
    end
  end

  defp verify!(dir) do
    for line <- dir |> Path.join(@sums) |> File.read!() |> String.split("\n", trim: true) do
      [expected, name] = String.split(line, "  ", parts: 2)
      file = Path.basename(name)
      actual = dir |> Path.join(file) |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
      if actual != expected, do: Mix.raise("#{file}: checksum mismatch, download is corrupt")
    end
  end

  defp flash(dir, parts) do
    args = Enum.flat_map(parts, fn {file, offset} -> [offset, Path.join(dir, file)] end)
    cmd!("esptool.py", ["--chip", "esp32s3", "--baud", "921600", "write_flash"] ++ args)
  end

  defp cmd!(bin, args) do
    case System.cmd(bin, args, into: IO.stream(:stdio, :line), stderr_to_stdout: true) do
      {_, 0} -> :ok
      {_, code} -> Mix.raise("#{bin} exited #{code}")
    end
  end
end
