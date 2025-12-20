defmodule Madness do
  @moduledoc """
  Documentation for `Madness`.
  """

  use TypedStruct

  alias Madness.Message
  alias Madness.Query

  defdelegate new_query, to: Query, as: :new
  defdelegate add_question(query, question), to: Query

  @spec stream(Query.t()) :: Enumerable.t()
  @spec stream(Query.t(), keyword()) :: Enumerable.t()
  def stream(query, opts \\ [])

  def stream(%Query{questions: []}, _opts), do: []

  def stream(%Query{} = query, opts) do
    if Query.all_unicast?(query) do
      Stream.resource(fn -> send_query(query, opts) end, &recv_responses/1, &stop/1)
    else
      {:error, :multicast_query}
    end
  end

  defp send_query(%Query{} = query, opts) do
    family = Keyword.get(opts, :family)
    ifindex = Keyword.get(opts, :ifindex)
    timeout = Keyword.get(opts, :timeout, 5_000)

    palias = Process.alias()

    args = [caller: self(), caller_alias: palias, questions: query.questions]

    with {:ok, ifaddrs} <- :net.getifaddrs(net_filter(family, ifindex)) do
      pids =
        Enum.reduce(ifaddrs, [], fn ifaddr, pids ->
          client_args = [{:ifaddr, ifaddr} | args]

          case Madness.Application.start_client(client_args) do
            {:ok, pid} ->
              [pid | pids]

            _ ->
              pids
          end
        end)

      deadline = :erlang.monotonic_time(:millisecond) + timeout
      {palias, pids, deadline}
    end
  end

  defp recv_responses({palias, _pids, deadline} = state) do
    remaining = max(0, deadline - :erlang.monotonic_time(:millisecond))

    receive do
      {^palias, family, ifindex, iov} ->
        {:ok, message, <<>>} = Message.decode(IO.iodata_to_binary(iov))
        {[%{family: family, ifindex: ifindex, message: message}], state}
    after
      remaining ->
        {:halt, state}
    end
  end

  defp stop({palias, pids, _deadline}) do
    Process.unalias(palias)
    drop(palias)
    Enum.each(pids, &send(&1, :stop))
  end

  defp drop(palias) do
    receive do
      {^palias, _, _, _} ->
        drop(palias)
    after
      0 ->
        :ok
    end
  end

  defp net_filter(filter_family, filter_name) do
    fn
      %{name: name, addr: %{family: family}} when is_nil(filter_family) and is_nil(filter_name) ->
        family in [:inet, :inet6] && matches_prefix?(name)

      %{name: ^filter_name, addr: %{family: family}} when is_nil(filter_family) ->
        family in [:inet, :inet6] && matches_prefix?(filter_name)

      %{name: name, addr: %{family: ^filter_family}} when is_nil(filter_name) ->
        filter_family in [:inet, :inet6] && matches_prefix?(name)

      %{name: ^filter_name, addr: %{family: ^filter_family}} ->
        filter_family in [:inet, :inet6] && matches_prefix?(filter_name)

      _ ->
        false
    end
  end

  defp matches_prefix?(ifname) do
    case Application.get_env(:madness, :interface_prefixes, []) do
      [] ->
        true

      prefixes ->
        ifname = to_string(ifname)
        Enum.any?(prefixes, &String.starts_with?(ifname, &1))
    end
  end
end
