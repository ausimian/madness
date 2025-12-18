defmodule Madness.InertialHandler do
  @behaviour :gen_event

  @impl true
  def init({pid, ref} = state) when is_pid(pid) and is_reference(ref) do
    {:ok, state}
  end

  @impl true
  def handle_event(event, {pid, ref} = state) do
    send(pid, {ref, event})
    {:ok, state}
  end

  @impl true
  def handle_call(_request, state) do
    {:ok, :ok, state}
  end

  def install do
    ref = make_ref()
    :ok = :gen_event.add_sup_handler(Inertial.event_mgr(), {__MODULE__, ref}, {self(), ref})
    ref
  end
end
