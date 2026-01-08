defmodule Madness.Events do
  @moduledoc false

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {:gen_event, :start_link, [{:local, __MODULE__}]}
    }
  end

  def subscribe(alias, filter) do
    :gen_event.add_sup_handler(__MODULE__, {Madness.Events.Handler, alias}, {alias, filter})
  end

  def unsubscribe(alias) do
    Process.unalias(alias)
    :gen_event.delete_handler(__MODULE__, {Madness.Events.Handler, alias}, :unsubscribe)

    receive do
      {:gen_event_EXIT, {Madness.Events.Handler, ^alias}, _reason} -> :ok
    after
      0 -> :ok
    end

    drain(alias)
  end

  defp drain(alias) do
    receive do
      {^alias, %{}} -> drain(alias)
    after
      0 -> :ok
    end
  end

  def notify({name, type, class, family, ifindex}) do
    event = %{name: name, type: type, class: class, family: family, ifindex: ifindex}
    :gen_event.notify(__MODULE__, event)
  end
end
