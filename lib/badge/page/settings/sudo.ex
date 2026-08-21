defmodule Badge.Page.Settings.Sudo do
  @moduledoc """
  Developer and diagnostic controls.

  Nothing is wired up yet; the tab exists so the shape of Settings is
  visible while the behaviour is decided.
  """

  use Badge.Page

  alias Badge.Page.Settings
  alias Badge.Readout
  alias Badge.Theme

  @dim Theme.dim()
  @bg Theme.bg()

  @impl true
  def title, do: "Sudo Mode"

  @impl true
  def init, do: :ok

  @impl true
  def render(:ok) do
    [
      centred("Sudo Mode", Settings.content_top() + 40),
      centred("not built yet", Settings.content_top() + 66)
    ]
  end

  defp centred(text, y) do
    {:text, Readout.centre_x(text), y, :default16px, @dim, @bg, text}
  end
end
