defmodule Badge.MixProject do
  use Mix.Project

  def project do
    [
      app: :badge,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      atomvm: [
        start: Badge,
        flash_offset: 0x2B8000,
        chip: "esp32s3",
        port: "auto"
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [{:exatomvm, git: "https://github.com/atomvm/ExAtomVM/", runtime: false}]
  end
end
