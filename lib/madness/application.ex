defmodule Madness.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Madness.Cache, []},
      {DynamicSupervisor, strategy: :one_for_one, name: Madness.ClientSupervisor}
      # Starts a worker by calling: Madness.Worker.start_link(arg)
      # {Madness.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Madness.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def start_client(args) do
    DynamicSupervisor.start_child(Madness.ClientSupervisor, {Madness.Client, args})
  end
end
