defmodule Madness.ResourceTest do
  use ExUnit.Case, async: true

  alias Madness.Resource

  describe "encode/3" do
    test "encodes a simple A record resource" do
      resource = %Resource{
        name: "example.com",
        type: :a,
        class: :in,
        ttl: 300,
        rdata: {192, 168, 1, 1}
      }

      {encoded, _map} = Resource.encode(resource)

      # Name: 13 bytes, Type: 2, Class: 2, TTL: 4, RDLength: 2, RData: 4
      # Total: 27 bytes
      assert byte_size(encoded) == 27
    end

    test "encodes with cache_flush=false" do
      resource = %Resource{
        name: "example.com",
        type: :a,
        class: :in,
        cache_flush: false,
        ttl: 300,
        rdata: {1, 2, 3, 4}
      }

      {encoded, _map} = Resource.encode(resource)

      # Extract class field (after name + type)
      name_size = 13
      <<_name::binary-size(name_size), _type::16, class::16, _rest::binary>> = encoded

      # Top bit should not be set
      assert Bitwise.band(class, 0x8000) == 0
    end

    test "encodes with cache_flush=true" do
      resource = %Resource{
        name: "example.com",
        type: :a,
        class: :in,
        cache_flush: true,
        ttl: 300,
        rdata: {1, 2, 3, 4}
      }

      {encoded, _map} = Resource.encode(resource)

      name_size = 13
      <<_name::binary-size(name_size), _type::16, class::16, _rest::binary>> = encoded

      # Top bit should be set
      assert Bitwise.band(class, 0x8000) == 0x8000
    end

    test "encodes TTL correctly" do
      resource = %Resource{
        name: "test.local",
        type: :a,
        class: :in,
        ttl: 4500,
        rdata: {10, 0, 0, 1}
      }

      {encoded, _map} = Resource.encode(resource)

      name_size = 12
      <<_name::binary-size(name_size), _type::16, _class::16, ttl::32, _rest::binary>> = encoded

      assert ttl == 4500
    end

    test "encodes rdlength based on rdata size" do
      rdata = ["test", "data"]

      resource = %Resource{
        name: "test.local",
        type: :txt,
        class: :in,
        ttl: 100,
        rdata: rdata
      }

      {encoded, _map} = Resource.encode(resource)

      name_size = 12

      <<_name::binary-size(name_size), _type::16, _class::16, _ttl::32, rdlength::16,
        _rest::binary>> = encoded

      assert rdlength == 10
    end
  end

  describe "decode/2" do
    test "decodes a simple A record resource" do
      # example.com + type A + class IN + TTL 300 + rdlength 4 + rdata
      data = <<7, "example", 3, "com", 0, 0, 1, 0, 1, 0, 0, 1, 44, 0, 4, 192, 168, 1, 1>>

      assert {:ok, resource, <<>>} = Resource.decode(data)
      assert resource.name == "example.com"
      assert resource.type == :a
      assert resource.class == :in
      assert resource.ttl == 300
      assert resource.rdata == {192, 168, 1, 1}
    end

    test "decodes cache_flush flag when set" do
      # class with top bit set: 0x8001
      data = <<7, "example", 3, "com", 0, 0, 1, 0x80, 0x01, 0, 0, 0, 60, 0, 4, 1, 2, 3, 4>>

      assert {:ok, resource, <<>>} = Resource.decode(data)
      assert resource.cache_flush == true
      assert resource.class == :in
    end

    test "decodes cache_flush flag when not set" do
      data = <<7, "example", 3, "com", 0, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 1, 2, 3, 4>>

      assert {:ok, resource, <<>>} = Resource.decode(data)
      assert resource.cache_flush == false
    end

    test "returns remaining data after resource" do
      data = <<7, "example", 3, "com", 0, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 1, 2, 3, 4, "extra">>

      assert {:ok, resource, rest} = Resource.decode(data)
      assert resource.name == "example.com"
      assert rest == "extra"
    end

    test "returns error for insufficient data - missing type/class" do
      # Name only, no type/class/ttl/rdlength/rdata
      data = <<7, "example", 3, "com", 0>>

      assert {:error, msg} = Resource.decode(data)
      assert msg =~ "insufficient data"
    end

    test "returns error for insufficient data - truncated rdata" do
      # rdlength says 10 bytes but only 4 provided
      data = <<7, "example", 3, "com", 0, 0, 1, 0, 1, 0, 0, 0, 60, 0, 10, 1, 2, 3, 4>>

      assert {:error, msg} = Resource.decode(data)
      assert msg =~ "insufficient data"
    end
  end

  describe "round-trip encoding and decoding" do
    test "round-trips a resource with all fields" do
      original =
        Resource.new(%{
          name: "myhost.local",
          type: :a,
          class: :in,
          cache_flush: true,
          ttl: 120,
          rdata: {10, 0, 0, 5}
        })

      {encoded, _map} = Resource.encode(original)
      assert {:ok, decoded, <<>>} = Resource.decode(encoded)

      assert decoded.name == original.name
      assert decoded.type == original.type
      assert decoded.class == original.class
      assert decoded.cache_flush == original.cache_flush
      assert decoded.ttl == original.ttl
      assert decoded.rdata == {10, 0, 0, 5}
    end

    test "round-trips all common record types" do
      test_data = [
        {:a, {1, 2, 3, 4}},
        {:aaaa, {1, 2, 3, 4, 5, 6, 7, 8}},
        {:ns, "ns.test.local"},
        {:cname, "alias.test.local"},
        {:ptr, "target.test.local"},
        {:txt, ["text1", "text2"]},
        {:srv, %{priority: 10, weight: 20, port: 80, target: "server.test.local"}},
        {:nsec, %{name: "next.test.local", types: [:a, :aaaa, :srv]}}
      ]

      for {type, rdata} <- test_data do
        original =
          Resource.new(%{
            name: "test.local",
            type: type,
            class: :in,
            ttl: 300,
            rdata: rdata
          })

        {encoded, _map} = Resource.encode(original)
        assert {:ok, decoded, <<>>} = Resource.decode(encoded)

        assert decoded.type == original.type
      end
    end
  end
end
