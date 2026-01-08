defmodule Madness do
  @moduledoc """
  Documentation for `Madness`.
  """

  use TypedStruct

  alias Madness.Message
  alias Madness.Query

  defdelegate new_query, to: Query, as: :new
  defdelegate add_question(query, question), to: Query

  def subscribe(filter \\ %{}) do
    alias = Process.alias()

    with :ok <- Madness.Events.subscribe(alias, filter) do
      {:ok, alias}
    end
  end

  def unsubscribe(alias) do
    Madness.Events.unsubscribe(alias)
  end

  @spec query(Query.t() | binary()) :: Enumerable.t()
  @spec query(Query.t() | binary(), keyword() | atom()) :: Enumerable.t()
  @spec query(binary(), atom(), keyword()) :: Enumerable.t()
  def query(query_or_name, type_or_opts \\ [])

  def query(%Query{questions: []}, _opts), do: []

  def query(%Query{} = query, opts) do
    if Query.all_unicast?(query) do
      case Keyword.get(opts, :timeout, 5_000) do
        0 ->
          cache_only_stream(query, opts)

        _timeout ->
          Stream.resource(fn -> send_query(query, opts) end, &recv_responses/1, &stop/1)
      end
    else
      {:error, :multicast_query}
    end
  end

  def query(name, type) when is_binary(name) and is_atom(type) do
    query(name, type, [])
  end

  def query(name, type, opts) when is_binary(name) and is_atom(type) and is_list(opts) do
    {timeout_opts, question_opts} = Keyword.split(opts, [:timeout])

    question_attrs =
      [name: name, type: type]
      |> Keyword.merge(question_opts)
      |> Keyword.take([:name, :type, :class, :unicast_response])

    query =
      Query.new()
      |> Query.add_question(Map.new(question_attrs))

    query(query, timeout_opts)
  end

  defp cache_only_stream(%Query{} = query, opts) do
    family = Keyword.get(opts, :family)
    ifindex = Keyword.get(opts, :ifindex)

    Stream.resource(
      fn ->
        case :net.getifaddrs(net_filter(family, ifindex)) do
          {:ok, ifaddrs} -> ifaddrs
          _ -> []
        end
      end,
      fn
        [] ->
          {:halt, []}

        [%{name: name, addr: %{family: fam}} = ifaddr | rest] ->
          idx =
            case ifaddr do
              %{addr: %{family: :inet6, scope_id: scope_id}} -> scope_id
              %{addr: %{family: :inet}} -> elem(:net.if_name2index(name), 1)
            end

          {answers, _known} = Madness.Cache.lookup(query.questions, fam, idx)

          if answers == [] do
            {[], rest}
          else
            message = %{Message.new() | answers: answers}
            {[%{family: fam, ifindex: idx, message: message}], rest}
          end
      end,
      fn _ -> :ok end
    )
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
        case Message.decode(IO.iodata_to_binary(iov)) do
          {:ok, message, <<>>} ->
            {[%{family: family, ifindex: ifindex, message: message}], state}

          _ ->
            {[], state}
        end
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
