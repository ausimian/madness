defmodule Madness.EventsTest do
  use ExUnit.Case, async: false

  alias Madness.Cache
  alias Madness.Resource
  alias Madness.Message
  alias Madness.Header

  setup do
    Cache.clear()
    :ok
  end

  # Helper to wait for gen_event to process notifications
  defp sync_events do
    :gen_event.sync_notify(Madness.Events, :sync)
  end

  defp build_response(answers) do
    %Message{
      header: %Header{qr: true, aa: true},
      answers: answers
    }
    |> Message.encode()
    |> IO.iodata_to_binary()
  end

  describe "subscribe/1" do
    test "receives events matching empty filter" do
      {:ok, ref} = Madness.subscribe(%{})

      answer = Resource.new(%{name: "test.local", type: :a, ttl: 100, rdata: {1, 2, 3, 4}})
      response = build_response([answer])
      Cache.put_response(response, :inet, 1)
      Cache.sync()
      sync_events()

      assert_receive {^ref,
                      %{name: "test.local", type: :a, class: :in, family: :inet, ifindex: 1}}

      Madness.unsubscribe(ref)
    end

    test "receives events matching name filter" do
      {:ok, ref} = Madness.subscribe(%{name: "match.local"})

      # This should match
      answer1 = Resource.new(%{name: "match.local", type: :a, ttl: 100, rdata: {1, 1, 1, 1}})
      response1 = build_response([answer1])
      Cache.put_response(response1, :inet, 1)
      Cache.sync()
      sync_events()

      # This should not match
      answer2 = Resource.new(%{name: "other.local", type: :a, ttl: 100, rdata: {2, 2, 2, 2}})
      response2 = build_response([answer2])
      Cache.put_response(response2, :inet, 1)
      Cache.sync()
      sync_events()

      assert_receive {^ref, %{name: "match.local"}}
      refute_receive {^ref, %{name: "other.local"}}, 10

      Madness.unsubscribe(ref)
    end

    test "receives events matching type filter" do
      {:ok, ref} = Madness.subscribe(%{type: :aaaa})

      # This should not match
      answer1 = Resource.new(%{name: "test.local", type: :a, ttl: 100, rdata: {1, 1, 1, 1}})
      response1 = build_response([answer1])
      Cache.put_response(response1, :inet, 1)
      Cache.sync()
      sync_events()

      # This should match
      answer2 =
        Resource.new(%{
          name: "test.local",
          type: :aaaa,
          ttl: 100,
          rdata: {0, 0, 0, 0, 0, 0, 0, 1}
        })

      response2 = build_response([answer2])
      Cache.put_response(response2, :inet, 1)
      Cache.sync()
      sync_events()

      assert_receive {^ref, %{type: :aaaa}}
      refute_receive {^ref, %{type: :a}}, 10

      Madness.unsubscribe(ref)
    end

    test "receives events matching multiple filter keys" do
      {:ok, ref} = Madness.subscribe(%{name: "multi.local", type: :a, family: :inet})

      # Should match
      answer1 = Resource.new(%{name: "multi.local", type: :a, ttl: 100, rdata: {1, 1, 1, 1}})
      response1 = build_response([answer1])
      Cache.put_response(response1, :inet, 1)
      Cache.sync()
      sync_events()

      # Should not match (wrong family)
      answer2 = Resource.new(%{name: "multi.local", type: :a, ttl: 100, rdata: {2, 2, 2, 2}})
      response2 = build_response([answer2])
      Cache.put_response(response2, :inet6, 1)
      Cache.sync()
      sync_events()

      assert_receive {^ref, %{name: "multi.local", family: :inet}}
      refute_receive {^ref, %{family: :inet6}}, 10

      Madness.unsubscribe(ref)
    end

    test "receives events matching name filter with regex" do
      {:ok, ref} = Madness.subscribe(%{name: ~r/^_http\._tcp/})

      # This should match
      answer1 = Resource.new(%{name: "_http._tcp.local", type: :ptr, ttl: 100, rdata: "service._http._tcp.local"})
      response1 = build_response([answer1])
      Cache.put_response(response1, :inet, 1)
      Cache.sync()
      sync_events()

      # This should also match
      answer2 = Resource.new(%{name: "_http._tcp.example.local", type: :ptr, ttl: 100, rdata: "other._http._tcp.example.local"})
      response2 = build_response([answer2])
      Cache.put_response(response2, :inet, 1)
      Cache.sync()
      sync_events()

      # This should not match
      answer3 = Resource.new(%{name: "_https._tcp.local", type: :ptr, ttl: 100, rdata: "secure._https._tcp.local"})
      response3 = build_response([answer3])
      Cache.put_response(response3, :inet, 1)
      Cache.sync()
      sync_events()

      assert_receive {^ref, %{name: "_http._tcp.local"}}
      assert_receive {^ref, %{name: "_http._tcp.example.local"}}
      refute_receive {^ref, %{name: "_https._tcp.local"}}, 10

      Madness.unsubscribe(ref)
    end

    test "notifies on record removal (TTL=0)" do
      # First insert a record
      answer1 = Resource.new(%{name: "remove.local", type: :a, ttl: 100, rdata: {1, 1, 1, 1}})
      response1 = build_response([answer1])
      Cache.put_response(response1, :inet, 1)
      Cache.sync()
      sync_events()

      {:ok, ref} = Madness.subscribe(%{name: "remove.local"})

      # Remove it with TTL=0
      answer2 = Resource.new(%{name: "remove.local", type: :a, ttl: 0, rdata: {1, 1, 1, 1}})
      response2 = build_response([answer2])
      Cache.put_response(response2, :inet, 1)
      Cache.sync()
      sync_events()

      assert_receive {^ref, %{name: "remove.local"}}

      Madness.unsubscribe(ref)
    end
  end

  describe "unsubscribe/1" do
    test "stops receiving events after unsubscribe" do
      {:ok, ref} = Madness.subscribe(%{})

      # Should receive this
      answer1 = Resource.new(%{name: "before.local", type: :a, ttl: 100, rdata: {1, 1, 1, 1}})
      response1 = build_response([answer1])
      Cache.put_response(response1, :inet, 1)
      Cache.sync()
      sync_events()

      assert_receive {^ref, %{name: "before.local"}}

      Madness.unsubscribe(ref)

      # Should not receive this
      answer2 = Resource.new(%{name: "after.local", type: :a, ttl: 100, rdata: {2, 2, 2, 2}})
      response2 = build_response([answer2])
      Cache.put_response(response2, :inet, 1)
      Cache.sync()
      sync_events()

      refute_receive {^ref, _}, 10
    end

    test "drains pending events from mailbox" do
      {:ok, ref} = Madness.subscribe(%{})

      # Send multiple events
      for i <- 1..5 do
        answer = Resource.new(%{name: "drain#{i}.local", type: :a, ttl: 100, rdata: {i, i, i, i}})
        response = build_response([answer])
        Cache.put_response(response, :inet, 1)
      end

      Cache.sync()
      sync_events()

      Madness.unsubscribe(ref)

      # Mailbox should be empty of events for this ref
      refute_receive {^ref, _}, 10
    end
  end

  describe "multiple subscribers" do
    test "each subscriber receives matching events independently" do
      {:ok, ref1} = Madness.subscribe(%{type: :a})
      {:ok, ref2} = Madness.subscribe(%{type: :aaaa})
      {:ok, ref3} = Madness.subscribe(%{})

      answer_a = Resource.new(%{name: "test.local", type: :a, ttl: 100, rdata: {1, 1, 1, 1}})
      response_a = build_response([answer_a])
      Cache.put_response(response_a, :inet, 1)
      Cache.sync()
      sync_events()

      answer_aaaa =
        Resource.new(%{
          name: "test.local",
          type: :aaaa,
          ttl: 100,
          rdata: {0, 0, 0, 0, 0, 0, 0, 1}
        })

      response_aaaa = build_response([answer_aaaa])
      Cache.put_response(response_aaaa, :inet, 1)
      Cache.sync()
      sync_events()

      # ref1 should only get :a
      assert_receive {^ref1, %{type: :a}}
      refute_receive {^ref1, %{type: :aaaa}}, 10

      # ref2 should only get :aaaa
      assert_receive {^ref2, %{type: :aaaa}}
      refute_receive {^ref2, %{type: :a}}, 10

      # ref3 should get both
      assert_receive {^ref3, %{type: :a}}
      assert_receive {^ref3, %{type: :aaaa}}

      Madness.unsubscribe(ref1)
      Madness.unsubscribe(ref2)
      Madness.unsubscribe(ref3)
    end
  end
end
