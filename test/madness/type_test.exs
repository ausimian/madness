defmodule Madness.TypeTest do
  use ExUnit.Case, async: true

  alias Madness.Type

  describe "to_int/1" do
    test "converts :a to 1" do
      assert Type.to_int(:a) == 1
    end

    test "converts :ns to 2" do
      assert Type.to_int(:ns) == 2
    end

    test "converts :cname to 5" do
      assert Type.to_int(:cname) == 5
    end

    test "converts :ptr to 12" do
      assert Type.to_int(:ptr) == 12
    end

    test "converts :txt to 16" do
      assert Type.to_int(:txt) == 16
    end

    test "converts :aaaa to 28" do
      assert Type.to_int(:aaaa) == 28
    end

    test "converts :srv to 33" do
      assert Type.to_int(:srv) == 33
    end

    test "converts :nsec to 47" do
      assert Type.to_int(:nsec) == 47
    end

    test "converts :any to 255" do
      assert Type.to_int(:any) == 255
    end

    test "passes through integers unchanged" do
      assert Type.to_int(6) == 6
      assert Type.to_int(100) == 100
    end
  end

  describe "from_int/1" do
    test "converts 1 to :a" do
      assert Type.from_int(1) == :a
    end

    test "converts 2 to :ns" do
      assert Type.from_int(2) == :ns
    end

    test "converts 5 to :cname" do
      assert Type.from_int(5) == :cname
    end

    test "converts 12 to :ptr" do
      assert Type.from_int(12) == :ptr
    end

    test "converts 16 to :txt" do
      assert Type.from_int(16) == :txt
    end

    test "converts 28 to :aaaa" do
      assert Type.from_int(28) == :aaaa
    end

    test "converts 33 to :srv" do
      assert Type.from_int(33) == :srv
    end

    test "converts 47 to :nsec" do
      assert Type.from_int(47) == :nsec
    end

    test "converts 255 to :any" do
      assert Type.from_int(255) == :any
    end

    test "passes through unknown integers unchanged" do
      assert Type.from_int(6) == 6
      assert Type.from_int(100) == 100
    end
  end

  describe "round-trip" do
    test "to_int and from_int are inverses for known types" do
      for type <- [:a, :ns, :cname, :ptr, :txt, :aaaa, :srv, :nsec, :any] do
        assert type |> Type.to_int() |> Type.from_int() == type
      end
    end

    test "to_int and from_int are inverses for unknown integers" do
      for n <- [3, 4, 6, 100, 254] do
        assert n |> Type.from_int() |> Type.to_int() == n
      end
    end
  end
end
