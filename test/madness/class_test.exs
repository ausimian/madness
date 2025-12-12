defmodule Madness.ClassTest do
  use ExUnit.Case, async: true

  alias Madness.Class

  describe "to_int/1" do
    test "converts :in to 1" do
      assert Class.to_int(:in) == 1
    end

    test "converts :any to 255" do
      assert Class.to_int(:any) == 255
    end

    test "passes through integers unchanged" do
      assert Class.to_int(3) == 3
      assert Class.to_int(254) == 254
    end
  end

  describe "from_int/1" do
    test "converts 1 to :in" do
      assert Class.from_int(1) == :in
    end

    test "converts 255 to :any" do
      assert Class.from_int(255) == :any
    end

    test "passes through unknown integers unchanged" do
      assert Class.from_int(3) == 3
      assert Class.from_int(254) == 254
    end
  end

  describe "round-trip" do
    test "to_int and from_int are inverses for known classes" do
      for class <- [:in, :any] do
        assert class |> Class.to_int() |> Class.from_int() == class
      end
    end

    test "to_int and from_int are inverses for unknown integers" do
      for n <- [2, 3, 100, 254] do
        assert n |> Class.from_int() |> Class.to_int() == n
      end
    end
  end
end
