defmodule Histlog.Application do
  @moduledoc """
  OTP application entrypoint for histlog.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = []
    Supervisor.start_link(children, strategy: :one_for_one, name: Histlog.Supervisor)
  end
end
