defmodule Madness.RdataTest do
  use ExUnit.Case, async: true

  alias Madness.Rdata

  describe "round-trip A records" do
    test "encodes and decodes an IPv4 address" do
      original_binary = <<192, 168, 1, 1>>
      expected_tuple = {192, 168, 1, 1}

      {encoded, _map} = Rdata.encode(:a, original_binary, %{}, 0)
      decoded = Rdata.decode(:a, encoded, encoded)

      assert encoded == original_binary
      assert decoded == expected_tuple
    end

    test "encodes and decodes various IPv4 addresses" do
      test_cases = [
        {<<0, 0, 0, 0>>, {0, 0, 0, 0}},
        {<<127, 0, 0, 1>>, {127, 0, 0, 1}},
        {<<192, 168, 1, 1>>, {192, 168, 1, 1}},
        {<<10, 0, 0, 5>>, {10, 0, 0, 5}},
        {<<255, 255, 255, 255>>, {255, 255, 255, 255}}
      ]

      for {binary, tuple} <- test_cases do
        {encoded, _map} = Rdata.encode(:a, binary, %{}, 0)
        decoded = Rdata.decode(:a, encoded, encoded)
        assert encoded == binary
        assert decoded == tuple
      end
    end

    test "encoded A record is exactly 4 bytes" do
      {encoded, _map} = Rdata.encode(:a, <<192, 168, 1, 1>>, %{}, 0)
      assert byte_size(encoded) == 4
    end
  end

  describe "round-trip AAAA records" do
    test "encodes and decodes an IPv6 address" do
      original_binary = <<0x2001::16, 0x0db8::16, 0x85a3::16, 0x0000::16, 0x0000::16, 0x8a2e::16, 0x0370::16, 0x7334::16>>
      expected_tuple = {0x2001, 0x0db8, 0x85a3, 0x0000, 0x0000, 0x8a2e, 0x0370, 0x7334}

      {encoded, _map} = Rdata.encode(:aaaa, original_binary, %{}, 0)
      decoded = Rdata.decode(:aaaa, encoded, encoded)

      assert encoded == original_binary
      assert decoded == expected_tuple
    end

    test "encodes and decodes various IPv6 addresses" do
      test_cases = [
        {<<0::16, 0::16, 0::16, 0::16, 0::16, 0::16, 0::16, 0::16>>, {0, 0, 0, 0, 0, 0, 0, 0}},
        {<<0::16, 0::16, 0::16, 0::16, 0::16, 0::16, 0::16, 1::16>>, {0, 0, 0, 0, 0, 0, 0, 1}},
        {<<0x2001::16, 0x0db8::16, 0x85a3::16, 0x0000::16, 0x0000::16, 0x8a2e::16, 0x0370::16, 0x7334::16>>, {0x2001, 0x0db8, 0x85a3, 0x0000, 0x0000, 0x8a2e, 0x0370, 0x7334}},
        {<<0xfe80::16, 0::16, 0::16, 0::16, 0::16, 0::16, 0::16, 1::16>>, {0xfe80, 0, 0, 0, 0, 0, 0, 1}},
        {<<0xffff::16, 0xffff::16, 0xffff::16, 0xffff::16, 0xffff::16, 0xffff::16, 0xffff::16, 0xffff::16>>, {0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff}}
      ]

      for {binary, tuple} <- test_cases do
        {encoded, _map} = Rdata.encode(:aaaa, binary, %{}, 0)
        decoded = Rdata.decode(:aaaa, encoded, encoded)
        assert encoded == binary
        assert decoded == tuple
      end
    end

    test "encoded AAAA record is exactly 16 bytes" do
      {encoded, _map} = Rdata.encode(:aaaa, <<1::16, 2::16, 3::16, 4::16, 5::16, 6::16, 7::16, 8::16>>, %{}, 0)
      assert byte_size(encoded) == 16
    end
  end

  describe "round-trip CNAME records" do
    test "encodes and decodes a simple CNAME" do
      original = "example.com"

      {encoded, _map} = Rdata.encode(:cname, original, %{}, 0)
      decoded = Rdata.decode(:cname, encoded, encoded)

      assert decoded == original
    end

    test "encodes and decodes various domain names" do
      names = [
        "example.com",
        "foo.bar.baz.example.com",
        "local",
        "_http._tcp.local"
      ]

      for name <- names do
        {encoded, _map} = Rdata.encode(:cname, name, %{}, 0)
        decoded = Rdata.decode(:cname, encoded, encoded)
        assert decoded == name
      end
    end

    test "round-trips CNAME with compression" do
      # Build a message with a suffix map
      {name1_encoded, map1} = Madness.Name.encode("example.com", %{}, 0)

      # Encode CNAME that shares suffix
      offset = byte_size(name1_encoded)
      {cname_encoded, _map2} = Rdata.encode(:cname, "foo.example.com", map1, offset)

      # Build full message
      message = name1_encoded <> cname_encoded

      # Decode CNAME (skip the first name)
      cname_data = binary_part(message, offset, byte_size(cname_encoded))
      decoded = Rdata.decode(:cname, cname_data, message)

      assert decoded == "foo.example.com"
    end
  end

  describe "round-trip PTR records" do
    test "encodes and decodes a simple PTR" do
      original = "host.local"

      {encoded, _map} = Rdata.encode(:ptr, original, %{}, 0)
      decoded = Rdata.decode(:ptr, encoded, encoded)

      assert decoded == original
    end

    test "encodes and decodes reverse DNS PTR names" do
      names = [
        "1.1.168.192.in-addr.arpa",
        "host.example.com",
        "service._http._tcp.local"
      ]

      for name <- names do
        {encoded, _map} = Rdata.encode(:ptr, name, %{}, 0)
        decoded = Rdata.decode(:ptr, encoded, encoded)
        assert decoded == name
      end
    end

    test "round-trips PTR with compression" do
      # Build a message with a suffix map
      {name1_encoded, map1} = Madness.Name.encode("local", %{}, 0)

      # Encode PTR that shares suffix
      offset = byte_size(name1_encoded)
      {ptr_encoded, _map2} = Rdata.encode(:ptr, "myhost.local", map1, offset)

      # Build full message
      message = name1_encoded <> ptr_encoded

      # Decode PTR (skip the first name)
      ptr_data = binary_part(message, offset, byte_size(ptr_encoded))
      decoded = Rdata.decode(:ptr, ptr_data, message)

      assert decoded == "myhost.local"
    end
  end

  describe "round-trip SRV records" do
    test "encodes and decodes a simple SRV record" do
      original = %{priority: 10, weight: 20, port: 8080, target: "server.example.com"}

      {encoded, _map} = Rdata.encode(:srv, original, %{}, 0)
      decoded = Rdata.decode(:srv, encoded, encoded)

      assert decoded == original
    end

    test "encodes and decodes various SRV records" do
      records = [
        %{priority: 0, weight: 0, port: 80, target: "web.example.com"},
        %{priority: 10, weight: 5, port: 443, target: "secure.example.com"},
        %{priority: 20, weight: 100, port: 5060, target: "sip.local"},
        %{priority: 65535, weight: 65535, port: 65535, target: "max.values.test"}
      ]

      for record <- records do
        {encoded, _map} = Rdata.encode(:srv, record, %{}, 0)
        decoded = Rdata.decode(:srv, encoded, encoded)
        assert decoded == record
      end
    end

    test "SRV encoding includes priority, weight, and port before target" do
      srv = %{priority: 10, weight: 20, port: 8080, target: "server.local"}

      {encoded, _map} = Rdata.encode(:srv, srv, %{}, 0)

      # First 6 bytes should be priority (2), weight (2), port (2)
      <<prio::16, weight::16, port::16, _target::binary>> = encoded

      assert prio == 10
      assert weight == 20
      assert port == 8080
    end

    test "round-trips SRV with target compression" do
      # Build a message with a suffix map
      {name1_encoded, map1} = Madness.Name.encode("local", %{}, 0)

      # Encode SRV with target that shares suffix
      offset = byte_size(name1_encoded)
      srv = %{priority: 10, weight: 20, port: 8080, target: "server.local"}
      {srv_encoded, _map2} = Rdata.encode(:srv, srv, map1, offset)

      # Build full message
      message = name1_encoded <> srv_encoded

      # Decode SRV (skip the first name)
      srv_data = binary_part(message, offset, byte_size(srv_encoded))
      decoded = Rdata.decode(:srv, srv_data, message)

      assert decoded == srv
    end
  end

  describe "round-trip TXT records" do
    test "encodes and decodes a single TXT string" do
      original = ["hello world"]

      {encoded, _map} = Rdata.encode(:txt, original, %{}, 0)
      decoded = Rdata.decode(:txt, encoded, encoded)

      assert decoded == original
    end

    test "encodes and decodes multiple TXT strings" do
      original = ["key=value", "foo=bar", "version=1.0"]

      {encoded, _map} = Rdata.encode(:txt, original, %{}, 0)
      decoded = Rdata.decode(:txt, encoded, encoded)

      assert decoded == original
    end

    test "encodes and decodes empty TXT string" do
      original = [""]

      {encoded, _map} = Rdata.encode(:txt, original, %{}, 0)
      decoded = Rdata.decode(:txt, encoded, encoded)

      assert decoded == original
    end

    test "encodes and decodes various TXT records" do
      records = [
        ["single"],
        ["one", "two", "three"],
        ["", "empty", ""],
        ["txtvers=1", "key=value with spaces", "multiple=words here"]
      ]

      for record <- records do
        {encoded, _map} = Rdata.encode(:txt, record, %{}, 0)
        decoded = Rdata.decode(:txt, encoded, encoded)
        assert decoded == record
      end
    end

    test "TXT encoding prefixes each string with length" do
      txt = ["hello", "world"]

      {encoded, _map} = Rdata.encode(:txt, txt, %{}, 0)

      # Should be: <5>"hello"<5>"world"
      assert encoded == <<5, "hello"::binary, 5, "world"::binary>>
    end

    test "handles TXT strings up to 255 bytes" do
      # Create a 255-byte string
      long_string = String.duplicate("a", 255)
      original = [long_string]

      {encoded, _map} = Rdata.encode(:txt, original, %{}, 0)
      decoded = Rdata.decode(:txt, encoded, encoded)

      assert decoded == original
      assert byte_size(encoded) == 256  # 1 length byte + 255 data bytes
    end
  end

  describe "round-trip unknown record types" do
    test "encodes and decodes raw binary data for unknown types" do
      original = <<1, 2, 3, 4, 5, 6, 7, 8>>

      {encoded, _map} = Rdata.encode(:unknown_type, original, %{}, 0)
      decoded = Rdata.decode(:unknown_type, encoded, encoded)

      assert decoded == original
      assert encoded == original  # Should pass through unchanged
    end

    test "handles empty binary for unknown types" do
      original = <<>>

      {encoded, _map} = Rdata.encode(:some_type, original, %{}, 0)
      decoded = Rdata.decode(:some_type, encoded, encoded)

      assert decoded == original
      assert encoded == original
    end
  end

  describe "suffix map handling" do
    test "A record encoding returns unchanged suffix map" do
      map = %{"example.com" => 100}
      {_encoded, returned_map} = Rdata.encode(:a, <<192, 168, 1, 1>>, map, 0)

      assert returned_map == map
    end

    test "AAAA record encoding returns unchanged suffix map" do
      map = %{"example.com" => 100}
      {_encoded, returned_map} = Rdata.encode(:aaaa, <<1::16, 2::16, 3::16, 4::16, 5::16, 6::16, 7::16, 8::16>>, map, 0)

      assert returned_map == map
    end

    test "TXT record encoding returns unchanged suffix map" do
      map = %{"example.com" => 100}
      {_encoded, returned_map} = Rdata.encode(:txt, ["hello"], map, 0)

      assert returned_map == map
    end

    test "CNAME record encoding updates suffix map" do
      map = %{}
      {_encoded, returned_map} = Rdata.encode(:cname, "example.com", map, 0)

      assert map != returned_map
      assert Map.has_key?(returned_map, "example.com")
    end

    test "PTR record encoding updates suffix map" do
      map = %{}
      {_encoded, returned_map} = Rdata.encode(:ptr, "host.local", map, 0)

      assert map != returned_map
      assert Map.has_key?(returned_map, "host.local")
    end

    test "SRV record encoding updates suffix map for target" do
      map = %{}
      srv = %{priority: 10, weight: 20, port: 8080, target: "server.local"}
      {_encoded, returned_map} = Rdata.encode(:srv, srv, map, 0)

      assert map != returned_map
      assert Map.has_key?(returned_map, "server.local")
    end
  end

  describe "integration with compressed messages" do
    test "multiple CNAME records share compression map" do
      # Simulate encoding multiple CNAMEs in a message
      {enc1, map1} = Rdata.encode(:cname, "example.com", %{}, 0)
      {enc2, map2} = Rdata.encode(:cname, "www.example.com", map1, byte_size(enc1))
      {enc3, _map3} = Rdata.encode(:cname, "mail.example.com", map2, byte_size(enc1) + byte_size(enc2))

      message = enc1 <> enc2 <> enc3

      # Decode all three
      dec1 = Rdata.decode(:cname, enc1, message)

      enc2_start = byte_size(enc1)
      enc2_data = binary_part(message, enc2_start, byte_size(enc2))
      dec2 = Rdata.decode(:cname, enc2_data, message)

      enc3_start = enc2_start + byte_size(enc2)
      enc3_data = binary_part(message, enc3_start, byte_size(enc3))
      dec3 = Rdata.decode(:cname, enc3_data, message)

      assert dec1 == "example.com"
      assert dec2 == "www.example.com"
      assert dec3 == "mail.example.com"

      # Verify compression saved space
      uncompressed_size = 13 + 17 + 18  # Length of each name + terminators
      compressed_size = byte_size(message)
      assert compressed_size < uncompressed_size
    end

    test "SRV records with shared target domain compress efficiently" do
      # Multiple services on same domain
      srv1 = %{priority: 10, weight: 10, port: 80, target: "server.example.com"}
      srv2 = %{priority: 20, weight: 10, port: 443, target: "server.example.com"}

      {enc1, map1} = Rdata.encode(:srv, srv1, %{}, 0)
      {enc2, _map2} = Rdata.encode(:srv, srv2, map1, byte_size(enc1))

      message = enc1 <> enc2

      # Decode both
      dec1 = Rdata.decode(:srv, enc1, message)

      enc2_data = binary_part(message, byte_size(enc1), byte_size(enc2))
      dec2 = Rdata.decode(:srv, enc2_data, message)

      assert dec1 == srv1
      assert dec2 == srv2

      # Second SRV should use compression pointer for target
      assert byte_size(enc2) < byte_size(enc1)
    end
  end
end
