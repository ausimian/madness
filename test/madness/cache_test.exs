defmodule Madness.CacheTest do
  use ExUnit.Case, async: false

  alias Madness.Cache
  alias Madness.Question
  alias Madness.Resource
  alias Madness.Message
  alias Madness.Header

  setup do
    # Clear the cache before each test
    Cache.clear()
    :ok
  end

  # Helper to populate cache and wait for processing to complete
  defp put_and_sync(response, family, ifindex) do
    :ok = Cache.put_response(response, family, ifindex)
    :ok = Cache.sync()
  end

  # Helper to build a DNS response binary
  defp build_response(answers, opts \\ []) do
    header = %Header{
      id: Keyword.get(opts, :id, 0),
      qr: true,
      aa: true
    }

    message = %Message{
      header: header,
      questions: Keyword.get(opts, :questions, []),
      answers: answers,
      authorities: Keyword.get(opts, :authorities, []),
      additionals: Keyword.get(opts, :additionals, [])
    }

    message |> Message.encode() |> IO.iodata_to_binary()
  end

  describe "lookup/3" do
    test "returns empty tuple when cache is empty" do
      questions = [%Question{name: "nonexistent.local", type: :a, class: :in}]
      assert {[], []} == Cache.lookup(questions, :inet, 1)
    end

    test "returns cached records after put_response" do
      # Insert a record via put_response
      answer = Resource.new(%{name: "test.local", type: :a, ttl: 4500, rdata: {192, 168, 1, 1}})
      response = build_response([answer])
      put_and_sync(response, :inet, 100)

      # Look it up
      questions = [%Question{name: "test.local", type: :a, class: :in}]
      {answers, known} = Cache.lookup(questions, :inet, 100)

      assert length(answers) == 1
      assert [%Resource{name: "test.local", type: :a, rdata: {192, 168, 1, 1}}] = answers
      # With high TTL, known should also contain the record
      assert length(known) == 1
    end

    test "returns empty when querying different family" do
      answer = Resource.new(%{name: "test2.local", type: :a, ttl: 4500, rdata: {10, 0, 0, 1}})
      response = build_response([answer])
      put_and_sync(response, :inet, 101)

      # Query with different family
      questions = [%Question{name: "test2.local", type: :a, class: :in}]
      assert {[], []} == Cache.lookup(questions, :inet6, 101)
    end

    test "returns empty when querying different ifindex" do
      answer = Resource.new(%{name: "test3.local", type: :a, ttl: 4500, rdata: {10, 0, 0, 2}})
      response = build_response([answer])
      put_and_sync(response, :inet, 102)

      # Query with different ifindex
      questions = [%Question{name: "test3.local", type: :a, class: :in}]
      assert {[], []} == Cache.lookup(questions, :inet, 999)
    end

    test "follows PTR -> SRV related questions" do
      # Insert PTR record pointing to a service
      ptr = Resource.new(%{
        name: "_http._tcp.local",
        type: :ptr,
        ttl: 4500,
        rdata: "myservice._http._tcp.local"
      })

      # Insert SRV record for the service
      srv = Resource.new(%{
        name: "myservice._http._tcp.local",
        type: :srv,
        ttl: 4500,
        rdata: %{priority: 0, weight: 0, port: 80, target: "myhost.local"}
      })

      response = build_response([ptr, srv])
      put_and_sync(response, :inet, 1)

      # Query for PTR - should also return related SRV
      questions = [%Question{name: "_http._tcp.local", type: :ptr, class: :in}]
      {answers, _known} = Cache.lookup(questions, :inet, 1)

      types = answers |> Enum.map(& &1.type) |> Enum.sort()
      assert :ptr in types
      assert :srv in types
    end

    test "follows SRV -> TXT, A, AAAA related questions" do
      # Insert SRV record
      srv = Resource.new(%{
        name: "myservice._http._tcp.local",
        type: :srv,
        ttl: 4500,
        rdata: %{priority: 0, weight: 0, port: 8080, target: "server.local"}
      })

      # Insert TXT record
      txt = Resource.new(%{
        name: "myservice._http._tcp.local",
        type: :txt,
        ttl: 4500,
        rdata: ["key=value"]
      })

      # Insert A record for target
      a = Resource.new(%{
        name: "server.local",
        type: :a,
        ttl: 4500,
        rdata: {192, 168, 1, 100}
      })

      # Insert AAAA record for target
      aaaa = Resource.new(%{
        name: "server.local",
        type: :aaaa,
        ttl: 4500,
        rdata: {0x2001, 0xdb8, 0, 0, 0, 0, 0, 1}
      })

      response = build_response([srv, txt, a, aaaa])
      put_and_sync(response, :inet, 1)

      # Query for SRV - should also return related TXT, A, AAAA
      questions = [%Question{name: "myservice._http._tcp.local", type: :srv, class: :in}]
      {answers, _known} = Cache.lookup(questions, :inet, 1)

      types = answers |> Enum.map(& &1.type) |> Enum.sort()
      assert :srv in types
      assert :txt in types
      assert :a in types
      assert :aaaa in types
    end

    test "does not return expired records" do
      # Insert a record with TTL of 100 seconds
      answer = Resource.new(%{name: "expire.local", type: :a, ttl: 100, rdata: {1, 2, 3, 4}})
      response = build_response([answer])
      put_and_sync(response, :inet, 1)

      questions = [%Question{name: "expire.local", type: :a, class: :in}]

      # Query at current time - record should be present
      now = :erlang.monotonic_time(:second)
      {answers, known} = Cache.lookup(questions, :inet, 1, now)
      assert length(answers) == 1
      assert length(known) == 1

      # Query 101 seconds later - record should be expired
      {answers, known} = Cache.lookup(questions, :inet, 1, now + 101)
      assert answers == []
      assert known == []
    end

    test "record with more than half TTL remaining is in known answers" do
      # Insert a record with TTL of 100 seconds
      answer = Resource.new(%{name: "half.local", type: :a, ttl: 100, rdata: {5, 6, 7, 8}})
      response = build_response([answer])
      put_and_sync(response, :inet, 1)

      questions = [%Question{name: "half.local", type: :a, class: :in}]
      now = :erlang.monotonic_time(:second)

      # Query at 40 seconds (60 remaining > 50 half) - should be in known
      {answers, known} = Cache.lookup(questions, :inet, 1, now + 40)
      assert length(answers) == 1
      assert length(known) == 1
    end

    test "record with less than half TTL remaining is not in known answers" do
      # Insert a record with TTL of 100 seconds
      answer = Resource.new(%{name: "lowhalf.local", type: :a, ttl: 100, rdata: {9, 10, 11, 12}})
      response = build_response([answer])
      put_and_sync(response, :inet, 1)

      questions = [%Question{name: "lowhalf.local", type: :a, class: :in}]
      now = :erlang.monotonic_time(:second)

      # Query at 60 seconds (40 remaining < 50 half) - should NOT be in known
      {answers, known} = Cache.lookup(questions, :inet, 1, now + 60)
      assert length(answers) == 1
      assert known == []
    end
  end

  describe "put_response/3" do
    test "stores records from answers section" do
      answer = Resource.new(%{name: "store.local", type: :a, ttl: 4500, rdata: {1, 2, 3, 4}})
      response = build_response([answer])
      put_and_sync(response, :inet, 1)

      questions = [%Question{name: "store.local", type: :a, class: :in}]
      {answers, _known} = Cache.lookup(questions, :inet, 1)
      assert [%Resource{rdata: {1, 2, 3, 4}}] = answers
    end

    test "stores records from authorities section" do
      authority = Resource.new(%{name: "auth.local", type: :a, ttl: 4500, rdata: {5, 6, 7, 8}})
      response = build_response([], authorities: [authority])
      put_and_sync(response, :inet, 1)

      questions = [%Question{name: "auth.local", type: :a, class: :in}]
      {answers, _known} = Cache.lookup(questions, :inet, 1)
      assert [%Resource{rdata: {5, 6, 7, 8}}] = answers
    end

    test "stores records from additionals section" do
      additional = Resource.new(%{name: "add.local", type: :a, ttl: 4500, rdata: {9, 10, 11, 12}})
      response = build_response([], additionals: [additional])
      put_and_sync(response, :inet, 1)

      questions = [%Question{name: "add.local", type: :a, class: :in}]
      {answers, _known} = Cache.lookup(questions, :inet, 1)
      assert [%Resource{rdata: {9, 10, 11, 12}}] = answers
    end

    test "cache_flush replaces existing records" do
      # Insert initial record
      r1 = Resource.new(%{name: "flush.local", type: :a, ttl: 4500, rdata: {1, 1, 1, 1}})
      response1 = build_response([r1])
      put_and_sync(response1, :inet, 1)

      # Insert new record with cache_flush
      r2 = Resource.new(%{
        name: "flush.local",
        type: :a,
        ttl: 4500,
        rdata: {2, 2, 2, 2},
        cache_flush: true
      })
      response2 = build_response([r2])
      put_and_sync(response2, :inet, 1)

      questions = [%Question{name: "flush.local", type: :a, class: :in}]
      {answers, _known} = Cache.lookup(questions, :inet, 1)

      # Should only have the new record
      assert length(answers) == 1
      assert [%Resource{rdata: {2, 2, 2, 2}}] = answers
    end

    test "TTL=0 removes records" do
      # Insert initial record
      r1 = Resource.new(%{name: "remove.local", type: :a, ttl: 4500, rdata: {3, 3, 3, 3}})
      response1 = build_response([r1])
      put_and_sync(response1, :inet, 1)

      # Verify it's there
      questions = [%Question{name: "remove.local", type: :a, class: :in}]
      {answers, _known} = Cache.lookup(questions, :inet, 1)
      assert [%Resource{}] = answers

      # Send TTL=0 to remove
      r2 = Resource.new(%{name: "remove.local", type: :a, ttl: 0, rdata: {3, 3, 3, 3}})
      response2 = build_response([r2])
      put_and_sync(response2, :inet, 1)

      # Should be gone
      assert {[], []} == Cache.lookup(questions, :inet, 1)
    end

    test "updates existing record with same rdata" do
      # Insert initial record
      r1 = Resource.new(%{name: "update.local", type: :a, ttl: 4500, rdata: {4, 4, 4, 4}})
      response1 = build_response([r1])
      put_and_sync(response1, :inet, 1)

      # Update with longer TTL
      r2 = Resource.new(%{name: "update.local", type: :a, ttl: 9000, rdata: {4, 4, 4, 4}})
      response2 = build_response([r2])
      put_and_sync(response2, :inet, 1)

      questions = [%Question{name: "update.local", type: :a, class: :in}]
      {answers, _known} = Cache.lookup(questions, :inet, 1)

      # Should still be one record
      assert length(answers) == 1
    end

    test "handles malformed packets gracefully" do
      # This should not crash - malformed packets are silently dropped
      assert :ok = Cache.put_response(<<0, 1, 2, 3>>, :inet, 1)
    end

    test "stores multiple records for same name/type" do
      r1 = Resource.new(%{name: "multi.local", type: :a, ttl: 4500, rdata: {10, 0, 0, 1}})
      r2 = Resource.new(%{name: "multi.local", type: :a, ttl: 4500, rdata: {10, 0, 0, 2}})
      response = build_response([r1, r2])
      put_and_sync(response, :inet, 1)

      questions = [%Question{name: "multi.local", type: :a, class: :in}]
      {answers, _known} = Cache.lookup(questions, :inet, 1)

      assert length(answers) == 2
      rdatas = Enum.map(answers, & &1.rdata) |> Enum.sort()
      assert [{10, 0, 0, 1}, {10, 0, 0, 2}] == rdatas
    end
  end
end
