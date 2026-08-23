# AtomVM's :atomvm module is absent on the host; serve the frames from disk.
defmodule :atomvm do
  @assets Path.expand("../assets", __DIR__)

  def read_priv(:assets, path), do: File.read!(Path.join(@assets, List.to_string(path)))
end

ExUnit.start()
