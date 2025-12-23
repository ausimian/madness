defmodule Madness.Cache do
  use GenServer
  use TypedStruct
  import Record, only: [defrecordp: 2]

  alias Madness.Resource
  alias Madness.Message
  alias Madness.Class
  alias Madness.Type
  alias Madness.Question

  @typep key() :: {String.t(), Type.t(), Class.t(), :inet | :inet6, integer()}
  @typep rec() :: {any(), non_neg_integer(), integer()}
  # @typep entry() :: {:entry, key(), [rec()]}

  defrecordp :entry, key: nil, recs: []

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @spec lookup([Question.t()], :inet | :inet6, non_neg_integer()) :: [Resource.t()]
  def lookup(questions, family, ifindex) do
    now = :erlang.monotonic_time(:second)

    {questions, MapSet.new()}
    |> Stream.unfold(&rlookup(&1, family, ifindex, now))
    |> Enum.to_list()
    |> List.flatten()
  end

  defp rlookup({[], _}, _family, _ifindex, _now), do: nil

  defp rlookup({[q | qs], asked}, family, ifindex, now) do
    if MapSet.member?(asked, q) do
      # Already asked this question, skip it
      rlookup({qs, asked}, family, ifindex, now)
    else
      asked = MapSet.put(asked, q)

      key = {q.name, q.type, q.class, family, ifindex}

      case :ets.lookup(__MODULE__, key) do
        [entry(recs: recs)] ->
          {new_qs, new_ans} =
            for {data, ttl, xat} <- recs, xat - now > div(ttl, 2), reduce: {MapSet.new(), []} do
              {new_qs, new_ans} ->
                rem = xat - now
                attrs = %{name: q.name, type: q.type, class: q.class, ttl: rem, rdata: data}
                answer = Resource.new(attrs)

                related =
                  answer
                  |> related_questions()
                  |> Enum.reject(&MapSet.member?(asked, &1))
                  |> MapSet.new()

                {MapSet.union(related, new_qs), [answer | new_ans]}
            end

          {new_ans, {Enum.to_list(new_qs) ++ qs, asked}}

        [] ->
          rlookup({qs, asked}, family, ifindex, now)
      end
    end
  end

  defp related_questions(%Resource{type: :ptr} = resrc) do
    [%Question{name: resrc.rdata, type: :srv, class: resrc.class}]
  end

  defp related_questions(%Resource{type: :srv, rdata: %{target: host}} = resrc) do
    txt = %Question{name: resrc.name, type: :txt, class: resrc.class}
    a = %Question{name: host, type: :a, class: resrc.class}
    aaaa = %Question{name: host, type: :aaaa, class: resrc.class}
    [txt, a, aaaa]
  end

  defp related_questions(%Resource{}), do: []

  @doc false
  def put_response(data, family, ifindex)
      when is_binary(data) and family in [:inet, :inet6] and is_integer(ifindex) do
    GenServer.call(__MODULE__, {:put_response, data, family, ifindex})
  end

  @multicast_addr {224, 0, 0, 251}
  @mdns_port 5353

  @recvpktinfo 19

  typedstruct enforce: true do
    field :sock_ipv4, :socket.socket()
    field :sock_ipv6, :socket.socket()
    field :sub, reference()
    field :ipv4_idxs, %{String.t() => {integer(), :inet.ip4_address()}}, default: %{}
    field :ipv6_idxs, %{String.t() => integer()}, default: %{}
  end

  @impl true
  def init(_args) do
    # Create the ETS table for cache
    :ets.new(__MODULE__, [:set, :protected, :named_table, keypos: entry(:key) + 1])

    # Subscribe to interface events
    ref = Inertial.subscribe()

    # Create IPv4 and IPv6 sockets and send self messages to listen on them
    {:ok, sock_ipv4} = :socket.open(:inet, :dgram, :udp)
    send(self(), {:listen, sock_ipv4})

    {:ok, sock_ipv6} = :socket.open(:inet6, :dgram, :udp)
    send(self(), {:listen, sock_ipv6})

    {:ok, %__MODULE__{sub: ref, sock_ipv4: sock_ipv4, sock_ipv6: sock_ipv6}}
  end

  @impl true
  def handle_call({:put_response, data, family, ifindex}, from, %__MODULE__{} = state) do
    # Reply immediately to the caller, then process the packet
    GenServer.reply(from, :ok)
    process_packet(data, family, ifindex)
    {:noreply, state}
  end

  @impl true
  def handle_continue({:recvmsg, sock} = cont, %__MODULE__{} = state) do
    # Do a non-blocking recvmsg on the socket
    case :socket.recvmsg(sock, 65535, 0, :nowait) do
      {:ok, %{addr: %{family: :inet}, iov: iov, ctrl: [%{value: %{ifindex: ifindex}}]}} ->
        process_packet(iov, :inet, ifindex)
        {:noreply, state, {:continue, cont}}

      {:ok, %{addr: %{family: :inet6, scope_id: ifindex}, iov: iov}} ->
        process_packet(iov, :inet6, ifindex)
        {:noreply, state, {:continue, cont}}

      {:select, _} ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:"$socket", sock, :select, _}, %__MODULE__{} = state) do
    # Socket is ready, continue receiving messages
    {:noreply, state, {:continue, {:recvmsg, sock}}}
  end

  def handle_info({ref, %{ifname: ifname} = event}, %__MODULE__{sub: ref} = state) do
    prefixes = Application.get_env(:madness, :interface_prefixes, [ifname])

    if Enum.any?(prefixes, &String.starts_with?(ifname, &1)) do
      case event do
        %{type: :link_up} ->
          {:noreply, maybe_add_ipv6_membership(ifname, state)}

        %{type: :link_down} ->
          {:noreply, maybe_drop_ipv6_membership(ifname, state)}

        %{type: :new_addr, addr: {_, _, _, _} = addr} ->
          {:noreply, maybe_add_ipv4_membership(ifname, addr, state)}

        %{type: :del_addr, addr: {_, _, _, _} = addr} ->
          {:noreply, maybe_drop_ipv4_membership(ifname, addr, state)}

        _other ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info({:listen, sock}, %__MODULE__{sock_ipv4: sock} = state) do
    # Join the multicast group on ipv4 interfaces
    [
      {:socket, :reuseaddr, true},
      {:socket, :reuseport, true},
      {:ip, :multicast_loop, false},
      {:ip, :multicast_ttl, 1},
      {:ip, :pktinfo, true}
    ]
    |> Enum.each(fn {level, opt, val} -> :ok = :socket.setopt(sock, level, opt, val) end)

    :ok = :socket.bind(sock, %{family: :inet, port: @mdns_port})

    {:noreply, join_ipv4(state), {:continue, {:recvmsg, sock}}}
  end

  def handle_info({:listen, sock}, %__MODULE__{sock_ipv6: sock} = state) do
    # Join the multicast group on ipv6 interfaces
    [
      {:socket, :reuseaddr, true},
      {:socket, :reuseport, true},
      {:ipv6, :multicast_loop, false},
      {:ipv6, :multicast_hops, 1},
      {{:ipv6, @recvpktinfo}, true}
    ]
    |> Enum.each(fn
      {level, opt, val} -> :ok = :socket.setopt(sock, level, opt, val)
      {{level, opt}, val} -> :ok = :socket.setopt_native(sock, {level, opt}, val)
    end)

    :ok = :socket.bind(sock, %{family: :inet6, port: @mdns_port})

    {:noreply, join_ipv6(state), {:continue, {:recvmsg, sock}}}
  end

  defp join_ipv4(%__MODULE__{} = state) do
    # For ipv4, we join per address
    {:ok, ifaddrs} = :net.getifaddrs(%{family: :inet, flags: [:up, :multicast]})

    ifaddrs
    |> Enum.filter(&matches_iface/1)
    |> Enum.reduce(state, fn %{name: name, addr: %{addr: addr}}, state ->
      maybe_add_ipv4_membership(name, addr, state)
    end)
  end

  defp join_ipv6(%__MODULE__{} = state) do
    # For ipv6, we join per interface
    {:ok, ifaddrs} = :net.getifaddrs(%{family: :inet6, flags: [:up, :multicast]})

    ifaddrs
    |> Enum.filter(&matches_iface/1)
    |> Enum.map(& &1.name)
    |> Enum.uniq()
    |> Enum.reduce(state, &maybe_add_ipv6_membership/2)
  end

  defp matches_iface(%{name: name}), do: supported_iface?(to_string(name))

  defp supported_iface?(name) when is_binary(name) do
    # TODO: Expand to other interface name prefixes as needed
    Enum.any?(["en"], &String.starts_with?(name, &1))
  end

  defp maybe_add_ipv4_membership(name, addr, %__MODULE__{} = state) when is_binary(name) do
    # Try to add the ipv4 address to the multicast group
    case :net.if_name2index(to_charlist(name)) do
      {:ok, ifindex} ->
        case add_ipv4_membership(state.sock_ipv4, addr) do
          :ok ->
            ipv4_idxs = Map.put(state.ipv4_idxs, name, {ifindex, addr})
            %{state | ipv4_idxs: ipv4_idxs}

          _ ->
            state
        end

      {:error, _} ->
        state
    end
  end

  defp maybe_add_ipv4_membership(name, addr, %__MODULE__{} = state) when is_list(name) do
    maybe_add_ipv4_membership(to_string(name), addr, state)
  end

  defp add_ipv4_membership(sock, addr) do
    member = %{multiaddr: @multicast_addr, interface: addr}
    :socket.setopt(sock, {:ip, :add_membership}, member)
  end

  defp maybe_drop_ipv4_membership(name, addr, %__MODULE__{} = state) when is_binary(name) do
    # Try to drop the ipv4 address from the multicast group
    case Map.pop(state.ipv4_idxs, name) do
      {{ifindex, ^addr}, updated} ->
        drop_ipv4_membership(state.sock_ipv4, addr)

        :ets.select_delete(__MODULE__, [{{:entry, {:_, :_, :_, :inet4, ifindex}, :_}, [], [true]}])

        %{state | ipv4_idxs: updated}

      _ ->
        state
    end
  end

  defp drop_ipv4_membership(sock, addr) do
    member = %{multiaddr: @multicast_addr, interface: addr}
    :ok = :socket.setopt(sock, {:ip, :drop_membership}, member)
  end

  defp maybe_add_ipv6_membership(name, %__MODULE__{} = state) when is_binary(name) do
    case :net.if_name2index(to_charlist(name)) do
      {:ok, ifindex} ->
        case add_ipv6_membership(state.sock_ipv6, ifindex) do
          :ok ->
            ipv6_idxs = Map.put(state.ipv6_idxs, name, ifindex)
            %{state | ipv6_idxs: ipv6_idxs}

          _ ->
            state
        end

      {:error, _} ->
        state
    end
  end

  defp maybe_add_ipv6_membership(name, %__MODULE__{} = state) when is_list(name) do
    maybe_add_ipv6_membership(to_string(name), state)
  end

  defp add_ipv6_membership(sock, ifindex) do
    raw = <<0xFF02::16, 0::96, 0xFB::16, ifindex::32-native>>
    :socket.setopt_native(sock, {41, 12}, raw)
  end

  defp maybe_drop_ipv6_membership(name, %__MODULE__{} = state) when is_binary(name) do
    # Try to drop the interface from the ipv6 multicast group
    case Map.pop(state.ipv6_idxs, name) do
      {ifindex, updated} when is_integer(ifindex) ->
        drop_ipv6_membership(state.sock_ipv6, ifindex)

        :ets.select_delete(__MODULE__, [{{:entry, {:_, :_, :_, :inet6, ifindex}, :_}, [], [true]}])

        %{state | ipv6_idxs: updated}

      _ ->
        state
    end
  end

  defp drop_ipv6_membership(sock, ifindex) do
    raw = <<0xFF02::16, 0::96, 0xFB::16, ifindex::32-native>>
    :ok = :socket.setopt_native(sock, {41, 13}, raw)
  end

  defp process_packet(packet, family, ifindex) do
    # Decode the DNS message
    {:ok, %Message{} = msg, <<>>} =
      packet
      |> IO.iodata_to_binary()
      |> Message.decode()

    process_message(msg, family, ifindex)
  end

  defp process_message(%Message{} = msg, family, ifindex) do
    # Process all resource records in the message
    iat = :erlang.monotonic_time(:second)
    :ok = process_resources(msg.answers, family, ifindex, iat)
    :ok = process_resources(msg.authorities, family, ifindex, iat)
    :ok = process_resources(msg.additionals, family, ifindex, iat)
  end

  defp process_resources([], _family, _ifindex, _iat), do: :ok

  defp process_resources([%Resource{type: type} = res | rest], family, ifindex, iat)
       when is_atom(type) do
    key = {res.name, res.type, res.class, family, ifindex}

    recs = if res.cache_flush, do: [], else: lookup_recs(key)

    if res.ttl == 0 do
      remove_recs(key, recs, res.rdata)
    else
      rec = {res.rdata, res.ttl, iat + res.ttl}
      update_recs(key, recs, rec)
    end

    process_resources(rest, family, ifindex, iat)
  end

  defp process_resources([_res | rest], family, ifindex, iat) do
    process_resources(rest, family, ifindex, iat)
  end

  @spec lookup_recs(key()) :: [rec()]
  defp lookup_recs(key) do
    case :ets.lookup(__MODULE__, key) do
      [entry(recs: recs)] -> recs
      [] -> []
    end
  end

  @spec remove_recs(key(), [rec()], any()) :: :ok
  defp remove_recs(key, recs, rdata) do
    updated = for {data, _} = rec <- recs, data != rdata, do: rec
    :ets.insert(__MODULE__, entry(key: key, recs: updated))
    :ok
  end

  @spec update_recs(key(), [rec()], rec()) :: :ok
  defp update_recs(key, recs, {rdata, _, _} = rec) do
    updated =
      if index = Enum.find_index(recs, fn {data, _, _} -> data == rdata end) do
        List.replace_at(recs, index, rec)
      else
        [rec | recs]
      end

    :ets.insert(__MODULE__, entry(key: key, recs: updated))
    :ok
  end
end
