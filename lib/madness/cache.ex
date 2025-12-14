defmodule Madness.Cache do
  use GenServer
  use TypedStruct

  alias Madness.Resource
  alias Madness.Message
  alias Madness.Class
  alias Madness.Type

  @multicast_addr {224, 0, 0, 251}
  @mdns_port 5353

  @resources __MODULE__.Resources
  @instances __MODULE__.Instances

  @type rkey() :: {String.t(), Type.t(), Class.t()}
  @type ikey() :: {rkey, any()}

  @spec resources() :: [tuple()]
  def resources, do: :ets.tab2list(@resources)
  def instances, do: :ets.tab2list(@instances)

  def lookup(name, type, class \\ :in) do
    rkey = {name, type, class}
    ikeys = :ets.lookup(@resources, rkey)
    now = :erlang.monotonic_time()

    filter =
      for ikey <- ikeys do
        {{ikey, :_, :"$1"}, [{:>, :"$1", now}], [elem(ikey, 1)]}
      end

    :ets.select(@instances, filter)
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    :ets.new(@resources, [:bag, :protected, :named_table])
    :ets.new(@instances, [:set, :protected, :named_table])
    {:ok, nil, {:continue, :listen}}
  end

  @impl true
  def handle_continue(:listen, nil) do
    {:ok, sock} =
      :gen_udp.open(@mdns_port, [
        :binary,
        active: true,
        add_membership: {@multicast_addr, {0, 0, 0, 0}},
        reuseport: true,
        multicast_loop: false,
        multicast_ttl: 255
      ])

    {:noreply, sock}
  end

  @impl true
  def handle_info({:udp, sock, _, _, pkt}, sock) do
    {:ok, %Message{} = msg, <<>>} = Message.decode(pkt)
    iat = :erlang.monotonic_time()
    :ok = process_resources(msg.answers, iat)
    :ok = process_resources(msg.authorities, iat)
    :ok = process_resources(msg.additionals, iat)
    {:noreply, sock}
  end

  defp process_resources([], _iat), do: :ok

  defp process_resources([%Resource{} = res | rest], iat) do
    if res.cache_flush, do: flush_cache(res)

    # Insert the entry into the resources table
    rkey = {res.name, res.type, res.class}
    ikey = {rkey, res.rdata}
    :ets.insert(@resources, ikey)

    # Insert (or update) the instances table
    xat = iat + :erlang.convert_time_unit(res.ttl, :second, :native)
    entry = {ikey, iat, xat}
    props = [{2, iat}, {3, xat}]

    :ets.update_element(@instances, ikey, props, entry)

    process_resources(rest, iat)
  end

  defp flush_cache(%Resource{name: name, type: type, class: class}) do
    rkey = {name, type, class}
    ikeys = :ets.lookup(@resources, rkey)

    filter =
      for ikey <- ikeys do
        {{ikey, :_, :_}, [], [true]}
      end

    :ets.select_delete(@instances, filter)
    :ets.delete(@resources, rkey)
    :ok
  end
end
