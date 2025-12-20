defmodule Madness.Client do
  use GenServer, restart: :temporary
  use TypedStruct

  alias Madness.Message
  alias Madness.Cache

  @mdns_port 5353
  @mdns_ipv4 {224, 0, 0, 251}
  @mdns_ipv6 {0xFF02, 0, 0, 0, 0, 0, 0, 0x00FB}

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  typedstruct do
    field :ifindex, non_neg_integer()
    field :sock, :socket.socket()
    field :family, :inet | :inet6
    field :caller_alias, reference()
    field :caller_ref, reference()
    field :recv_ref, reference() | nil, default: nil
  end

  @impl true
  def init(args) do
    case Keyword.fetch!(args, :ifaddr) do
      %{addr: %{family: :inet6, scope_id: 0}} ->
        :ignore

      _ ->
        {:ok, nil, {:continue, {:init, args}}}
    end
  end

  @impl true
  def handle_continue({:init, args}, nil) do
    ifaddr = Keyword.fetch!(args, :ifaddr)

    ifindex =
      case ifaddr do
        %{addr: %{family: :inet}, name: name} ->
          {:ok, ifindex} = :net.if_name2index(name)
          ifindex

        %{addr: %{family: :inet6, scope_id: ifindex}} ->
          ifindex
      end

    case bind_socket(ifaddr) do
      {:ok, sock} ->
        questions = Keyword.fetch!(args, :questions)
        caller = Keyword.fetch!(args, :caller)
        caller_alias = Keyword.fetch!(args, :caller_alias)

        caller_ref = Process.monitor(caller)

        state = %__MODULE__{
          ifindex: ifindex,
          sock: sock,
          caller_alias: caller_alias,
          caller_ref: caller_ref,
          family: ifaddr.addr.family
        }

        {:noreply, state, {:continue, {:send_request, questions}}}

      {:error, reason} ->
        {:stop, reason, nil}
    end
  end

  @impl true
  def handle_continue({:send_request, questions}, %__MODULE__{} = state) do
    known = Cache.lookup(questions, state.family, state.ifindex)
    query = Message.encode(%{Message.new() | questions: questions, answers: known})

    if Enum.any?(known) do
      notify(IO.iodata_to_binary(query), state)
    end

    dest =
      case state.family do
        :inet6 ->
          %{family: :inet6, addr: @mdns_ipv6, port: @mdns_port}

        :inet ->
          %{family: :inet, addr: @mdns_ipv4, port: @mdns_port}
      end

    case :socket.sendto(state.sock, query, dest) do
      :ok ->
        {:noreply, state, {:continue, :recvmsg}}

      {:error, reason} ->
        {:stop, reason, nil}
    end
  end

  def handle_continue(:recvmsg, %__MODULE__{recv_ref: nil} = state) do
    case :socket.recvmsg(state.sock, 65536, 0) do
      {:ok, %{iov: [data]}} when is_binary(data) ->
        process_packet(data, state)
        {:noreply, state, {:continue, :recvmsg}}

      {:select, {_, _, handle}} ->
        {:noreply, %{state | recv_ref: handle}}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  @impl true
  def handle_info({:"$socket", sock, :select, handle}, %__MODULE__{} = state)
      when sock == state.sock and handle == state.recv_ref do
    {:noreply, %{state | recv_ref: nil}, {:continue, :recvmsg}}
  end

  def handle_info(:stop, %__MODULE__{} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %__MODULE__{caller_ref: ref} = state) do
    {:stop, :normal, state}
  end

  defp process_packet(data, %__MODULE__{} = state) do
    Cache.put_response(data, state.family, state.ifindex)
    notify(data, state)
  end

  defp notify(data, %__MODULE__{} = state) do
    send(state.caller_alias, {state.caller_alias, state.family, state.ifindex, data})
    :ok
  end

  defp bind_socket(%{addr: %{family: family} = ifaddr}) when family in [:inet, :inet6] do
    with {:ok, sock} <- :socket.open(family, :dgram, :udp) do
      case bind_socket(sock, ifaddr) do
        :ok ->
          {:ok, sock}

        error ->
          :socket.close(sock)
          error
      end
    end
  end

  defp bind_socket(sock, %{family: :inet} = ifaddr) do
    with :ok <- :socket.setopt(sock, {:socket, :reuseaddr}, true),
         :ok <- :socket.setopt(sock, {:ip, :multicast_if}, ifaddr.addr),
         :ok <- :socket.setopt(sock, {:ip, :multicast_ttl}, 255) do
      :socket.bind(sock, %{family: :inet, addr: ifaddr.addr, port: 0})
    end
  end

  defp bind_socket(sock, %{family: :inet6} = ifaddr) do
    with :ok <- :socket.setopt(sock, {:socket, :reuseaddr}, true),
         :ok <- :socket.setopt(sock, {:ipv6, :multicast_if}, ifaddr.scope_id) do
      :socket.bind(sock, ifaddr)
    end
  end
end
