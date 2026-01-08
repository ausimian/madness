defmodule Madness.ClientTest do
  use ExUnit.Case

  alias Madness.Client

  describe "init/1" do
    test "returns :ignore for IPv6 address with scope_id 0" do
      args = [
        ifaddr: %{addr: %{family: :inet6, scope_id: 0}},
        caller: self(),
        caller_alias: Process.alias(),
        questions: []
      ]

      assert :ignore = Client.init(args)
    end

    test "returns {:ok, nil, {:continue, ...}} for valid IPv4 address" do
      args = [
        ifaddr: %{addr: %{family: :inet, addr: {127, 0, 0, 1}}, name: ~c"lo0"},
        caller: self(),
        caller_alias: Process.alias(),
        questions: []
      ]

      assert {:ok, nil, {:continue, {:init, ^args}}} = Client.init(args)
    end

    test "returns {:ok, nil, {:continue, ...}} for IPv6 address with non-zero scope_id" do
      args = [
        ifaddr: %{addr: %{family: :inet6, scope_id: 1}},
        caller: self(),
        caller_alias: Process.alias(),
        questions: []
      ]

      assert {:ok, nil, {:continue, {:init, ^args}}} = Client.init(args)
    end
  end

  describe "handle_info/2" do
    test ":stop message stops the server" do
      state = %Client{
        ifindex: 1,
        sock: nil,
        family: :inet,
        caller_alias: make_ref(),
        caller_ref: make_ref(),
        recv_ref: nil
      }

      assert {:stop, :normal, ^state} = Client.handle_info(:stop, state)
    end

    test "caller DOWN stops the server" do
      caller_ref = make_ref()

      state = %Client{
        ifindex: 1,
        sock: nil,
        family: :inet,
        caller_alias: make_ref(),
        caller_ref: caller_ref,
        recv_ref: nil
      }

      down_msg = {:DOWN, caller_ref, :process, self(), :normal}
      assert {:stop, :normal, ^state} = Client.handle_info(down_msg, state)
    end
  end
end
