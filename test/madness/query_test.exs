defmodule Madness.QueryTest do
  use ExUnit.Case, async: true

  alias Madness.Query
  alias Madness.Question

  describe "new/0" do
    test "returns an empty query" do
      query = Query.new()
      assert %Query{questions: []} = query
    end
  end

  describe "add_question/2" do
    test "adds a Question struct to the query" do
      question = %Question{name: "example.local", type: :a, class: :in, unicast_response: true}
      query = Query.new() |> Query.add_question(question)

      assert [^question] = query.questions
    end

    test "adds multiple questions in reverse order" do
      q1 = %Question{name: "first.local", type: :a, class: :in, unicast_response: true}
      q2 = %Question{name: "second.local", type: :aaaa, class: :in, unicast_response: true}

      query =
        Query.new()
        |> Query.add_question(q1)
        |> Query.add_question(q2)

      assert [^q2, ^q1] = query.questions
    end

    test "accepts a map and converts to Question" do
      query = Query.new() |> Query.add_question(%{name: "example.local", type: :ptr})

      assert [%Question{name: "example.local", type: :ptr, class: :in, unicast_response: true}] =
               query.questions
    end

    test "map can override defaults" do
      query =
        Query.new()
        |> Query.add_question(%{
          name: "example.local",
          type: :srv,
          class: :ch,
          unicast_response: false
        })

      assert [%Question{class: :ch, unicast_response: false}] = query.questions
    end
  end

  describe "all_unicast?/1" do
    test "returns true for empty query" do
      assert Query.all_unicast?(Query.new())
    end

    test "returns true when all questions have unicast_response: true" do
      query =
        Query.new()
        |> Query.add_question(%{name: "a.local", type: :a, unicast_response: true})
        |> Query.add_question(%{name: "b.local", type: :aaaa, unicast_response: true})

      assert Query.all_unicast?(query)
    end

    test "returns false when any question has unicast_response: false" do
      query =
        Query.new()
        |> Query.add_question(%{name: "a.local", type: :a, unicast_response: true})
        |> Query.add_question(%{name: "b.local", type: :ptr, unicast_response: false})

      refute Query.all_unicast?(query)
    end

    test "returns false when all questions have unicast_response: false" do
      query =
        Query.new()
        |> Query.add_question(%{name: "a.local", type: :a, unicast_response: false})

      refute Query.all_unicast?(query)
    end
  end
end
