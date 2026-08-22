defmodule Badge.Page.Soon do
  @moduledoc """
  A key waiting for a page.

  Nothing is wired up yet; the slot exists so the shape of the home grid is
  visible while what belongs here is decided.
  """

  use Badge.Page

  alias Badge.Readout
  alias Badge.Theme

  @dim Theme.dim()
  @bg Theme.bg()

  @title_y Theme.content_top() + 60
  @note_y Theme.content_top() + 86

  @impl true
  def title, do: "Soon"

  @impl true
  def icon, do: :cross

  @impl true
  def init, do: :ok

  @impl true
  def render(:ok) do
    [centred("Soon", @title_y), centred("not built yet", @note_y)]
  end

  defp centred(text, y) do
    {:text, Readout.centre_x(text), y, :default16px, @dim, @bg, text}
  end
end
