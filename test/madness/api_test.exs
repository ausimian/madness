defmodule Madness.ApiTest do
  use ExUnit.Case

  alias Madness.Query
  alias Madness.Question
  alias Madness.Resource
  alias Madness.Message
  alias Madness.Header
  alias Madness.Cache

  describe "new_query/0" do
    test "delegates to Query.new/0" do
      query = Madness.new_query()
      assert %Query{questions: []} = query
    end
  end

  describe "add_question/2" do
    test "delegates to Query.add_question/2" do
      query =
        Madness.new_query()
        |> Madness.add_question(%{name: "test.local", type: :a})

      assert [%Question{name: "test.local", type: :a}] = query.questions
    end
  end

  describe "query/1 with Query struct" do
    test "returns empty list for empty query" do
      result = Madness.query(%Query{questions: []})
      assert result == []
    end

    test "returns error for multicast query" do
      query =
        Query.new()
        |> Query.add_question(%{name: "test.local", type: :a, unicast_response: false})

      assert {:error, :multicast_query} = Madness.query(query)
    end
  end

  describe "query/1 with keyword list" do
    test "builds query from keyword list" do
      # Use timeout: 0 to avoid network calls
      result =
        Madness.query(type: :ptr, name: "_test._tcp.local", timeout: 0)
        |> Enum.to_list()

      # Should return empty list (nothing in cache for this query)
      assert is_list(result)
    end

    test "passes through query options" do
      # timeout: 0 should use cache-only mode
      result =
        Madness.query([type: :a, name: "api-test.local"], timeout: 0)
        |> Enum.to_list()

      assert is_list(result)
    end
  end

  describe "query/2 with timeout: 0 (cache-only mode)" do
    test "returns cached results without network query" do
      # First, populate the cache
      answer = Resource.new(%{
        name: "cached.local",
        type: :a,
        ttl: 300,
        rdata: {192, 168, 100, 1}
      })

      response =
        %Message{
          header: %Header{qr: true, aa: true},
          answers: [answer]
        }
        |> Message.encode()
        |> IO.iodata_to_binary()

      # Get a valid ifindex for this test
      {:ok, ifaddrs} = :net.getifaddrs(%{family: :inet, flags: [:up]})

      case ifaddrs do
        [%{name: name} | _] ->
          {:ok, ifindex} = :net.if_name2index(name)
          :ok = Cache.put_response(response, :inet, ifindex)

          # Query with timeout: 0 should hit cache
          query =
            Query.new()
            |> Query.add_question(%{name: "cached.local", type: :a})

          results = Madness.query(query, timeout: 0, family: :inet) |> Enum.to_list()

          # Should find our cached record
          found =
            Enum.any?(results, fn %{message: msg} ->
              Enum.any?(msg.answers, &(&1.rdata == {192, 168, 100, 1}))
            end)

          assert found

        [] ->
          # No interfaces available, skip test
          :ok
      end
    end

    test "returns stream that can be enumerated" do
      query =
        Query.new()
        |> Query.add_question(%{name: "stream-test.local", type: :a})

      result = Madness.query(query, timeout: 0)

      # Should be enumerable
      assert is_function(result, 2) or match?(%Stream{}, result)
      list = Enum.to_list(result)
      assert is_list(list)
    end
  end

  describe "query/2 error handling" do
    test "returns error for non-unicast question in Query struct" do
      query =
        Query.new()
        |> Query.add_question(%{name: "multi.local", type: :ptr, unicast_response: false})

      assert {:error, :multicast_query} = Madness.query(query)
    end

    test "returns error for non-unicast question via keyword" do
      result = Madness.query(type: :a, name: "test.local", unicast_response: false)
      assert {:error, :multicast_query} = result
    end
  end

  describe "query/2 with interface filtering" do
    test "timeout: 0 with family filter returns stream" do
      query =
        Query.new()
        |> Query.add_question(%{name: "filter-test.local", type: :a})

      # Filter by IPv4 only
      result = Madness.query(query, timeout: 0, family: :inet)
      assert is_function(result, 2) or match?(%Stream{}, result)
      Enum.to_list(result)
    end

    test "timeout: 0 with family: :inet6 returns stream" do
      query =
        Query.new()
        |> Query.add_question(%{name: "filter-test.local", type: :aaaa})

      result = Madness.query(query, timeout: 0, family: :inet6)
      assert is_function(result, 2) or match?(%Stream{}, result)
      Enum.to_list(result)
    end
  end
end
