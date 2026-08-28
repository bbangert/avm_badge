defmodule Badge.MixProject do
  use Mix.Project

  def project do
    [
      app: :badge,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # ExAtomVM writes no application.bin, and NervesHub cannot identify
      # firmware without one.
      aliases: ["atomvm.packbeam": ["atomvm.application_bin", "atomvm.packbeam"]],
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
    [
      {:exatomvm, git: "https://github.com/atomvm/ExAtomVM/", runtime: false},
      # The Erlang side of the port driver built into the VM. A rebar3
      # project, so mix is told which manager to use.
      {:atomvm_websocket_client, path: "../atomvm_websocket_client", manager: :rebar3},
      # The NervesHub agent, and its Elixir face. The override stops the
      # wrapper fetching its own copy of the agent from GitHub.
      {:nerves_hub_link_atomvm_esp32_ex, path: "../nerves_hub_link_atomvm_esp32_ex"},
      {:nerves_hub_link_atomvm_esp32,
       path: "../nerves_hub_link_atomvm_esp32", manager: :rebar3, override: true}
    ]
  end
end
