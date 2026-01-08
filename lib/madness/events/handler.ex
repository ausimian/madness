defmodule Madness.Events.Handler do
  @moduledoc false
  @behaviour :gen_event

  @impl true
  def init({alias, filter}) do
    {:ok, {alias, filter}}
  end

  @impl true
  def handle_event(event, {alias, filter} = state) when is_map(event) do
    if matches?(event, filter) do
      send(alias, {alias, event})
    end

    {:ok, state}
  end

  def handle_event(_event, state) do
    {:ok, state}
  end

  defp matches?(event, filter) do
    Enum.all?(filter, fn
      {:name, %Regex{} = regex} -> Regex.match?(regex, Map.get(event, :name, ""))
      {key, value} -> Map.get(event, key) == value
    end)
  end

  @impl true
  def handle_call(_request, state) do
    {:ok, :ok, state}
  end

  @impl true
  def handle_info(_info, state) do
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end
end
