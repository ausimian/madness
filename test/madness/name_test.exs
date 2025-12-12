defmodule Madness.NameTest do
  use ExUnit.Case, async: true

  alias Madness.Name

  describe "encode/1 without compression" do
    test "encodes a simple single-label name" do
      {encoded, _map} = Name.encode("com")

      # 3 c o m 0
      assert encoded == <<3, "com"::binary, 0>>
    end

    test "encodes a two-label name" do
      {encoded, _map} = Name.encode("example.com")

      # 7 e x a m p l e 3 c o m 0
      assert encoded == <<7, "example"::binary, 3, "com"::binary, 0>>
    end

    test "encodes a multi-label name" do
      {encoded, _map} = Name.encode("foo.bar.example.com")

      assert encoded ==
               <<3, "foo"::binary, 3, "bar"::binary, 7, "example"::binary, 3, "com"::binary, 0>>
    end

    test "encodes empty labels correctly" do
      {encoded, _map} = Name.encode("")

      # Just a null terminator
      assert encoded == <<0>>
    end

    test "returns an empty suffix map for first encoding" do
      {_encoded, suffix_map} = Name.encode("example.com")

      # Map contains all suffixes with their offsets
      assert suffix_map["example.com"] == 0
      assert suffix_map["com"] == 8
    end
  end

  describe "encode/2 with compression" do
    test "uses compression pointer when suffix exists" do
      # First encode builds the map
      {_encoded1, map1} = Name.encode("example.com")

      # Second encode should use pointer for "com"
      {encoded2, _map2} = Name.encode("foo.example.com", map1)

      # Should be: 3 f o o <pointer to offset 0>
      # Pointer is 0b11 (2 bits) followed by offset 0 (14 bits) = 0xC000
      assert encoded2 == <<3, "foo"::binary, 0xC0, 0x00>>
    end

    test "uses compression pointer for exact match" do
      {_encoded1, map1} = Name.encode("example.com")

      # Encode the same name again
      {encoded2, _map2} = Name.encode("example.com", map1)

      # Should be just a pointer to offset 0
      assert encoded2 == <<0xC0, 0x00>>
    end

    test "builds suffix map with all suffixes" do
      {_encoded, map} = Name.encode("foo.bar.example.com")

      # Each suffix should be in the map at its offset
      assert map["foo.bar.example.com"] == 0
      assert map["bar.example.com"] == 4
      assert map["example.com"] == 8
      assert map["com"] == 16
    end

    test "compresses multiple names sharing suffix" do
      # Encode three names sharing "example.com"
      {enc1, map1} = Name.encode("a.example.com")
      {enc2, map2} = Name.encode("b.example.com", map1, byte_size(enc1))
      {enc3, _map3} = Name.encode("c.example.com", map2, byte_size(enc1) + byte_size(enc2))

      # Third encoding should use pointer to "example.com" at offset 2
      # 1 c <pointer>
      assert enc3 == <<1, "c"::binary, 0xC0, 0x02>>
    end
  end

  describe "decode/1 without compression" do
    test "decodes a simple single-label name" do
      data = <<3, "com"::binary, 0>>

      assert {:ok, "com", <<>>} = Name.decode(data)
    end

    test "decodes a two-label name" do
      data = <<7, "example"::binary, 3, "com"::binary, 0>>

      assert {:ok, "example.com", <<>>} = Name.decode(data)
    end

    test "decodes a multi-label name" do
      data = <<3, "foo"::binary, 3, "bar"::binary, 7, "example"::binary, 3, "com"::binary, 0>>

      assert {:ok, "foo.bar.example.com", <<>>} = Name.decode(data)
    end

    test "decodes empty name (just null terminator)" do
      data = <<0>>

      assert {:ok, "", <<>>} = Name.decode(data)
    end

    test "returns remaining data after name" do
      data = <<3, "com"::binary, 0, "extra", "data">>

      assert {:ok, "com", rest} = Name.decode(data)
      assert rest == "extradata"
    end
  end

  describe "decode/2 with compression pointers" do
    test "decodes a name with compression pointer" do
      # Message: "com\0" at offset 0 (5 bytes), then "example" + pointer to 0
      message = <<3, "com"::binary, 0, 7, "example"::binary, 0xC0, 0x00>>

      # Decode second name (starts at offset 5)
      data = binary_part(message, 5, byte_size(message) - 5)

      assert {:ok, "example.com", <<>>} = Name.decode(data, message)
    end

    test "decodes nested compression pointers" do
      # "com\0" at offset 0 (5 bytes)
      # "example" + pointer to 0 at offset 5 (10 bytes)
      # "foo" + pointer to 5 at offset 15
      message =
        <<3, "com"::binary, 0, 7, "example"::binary, 0xC0, 0x00, 3, "foo"::binary, 0xC0, 0x05>>

      # Decode third name
      data = binary_part(message, 15, byte_size(message) - 15)

      assert {:ok, "foo.example.com", <<>>} = Name.decode(data, message)
    end

    test "decodes names sequentially from a message" do
      # Build a message with compressed names
      message = <<3, "com"::binary, 0, 7, "example"::binary, 0xC0, 0x00>>

      # Decode first name
      {:ok, "com", rest} = Name.decode(message, message)

      # Decode second name
      {:ok, "example.com", _rest} = Name.decode(rest, message)
    end

    test "handles pointer to exact name match" do
      # "example.com\0" at offset 0 (13 bytes), then just pointer to 0
      message = <<7, "example"::binary, 3, "com"::binary, 0, 0xC0, 0x00>>

      # Decode second occurrence (starts at offset 13)
      data = binary_part(message, 13, byte_size(message) - 13)

      assert {:ok, "example.com", <<>>} = Name.decode(data, message)
    end

    test "three-level nested compression" do
      # Level 1: "com\0" at offset 0 (5 bytes)
      # Level 2: "example" + ptr(0) at offset 5 (10 bytes)
      # Level 3: "foo.bar" + ptr(5) at offset 15
      message =
        <<3, "com"::binary, 0, 7, "example"::binary, 0xC0, 0x00, 3, "foo"::binary, 3,
          "bar"::binary, 0xC0, 0x05>>

      # Decode the third name
      data = binary_part(message, 15, byte_size(message) - 15)

      assert {:ok, "foo.bar.example.com", <<>>} = Name.decode(data, message)
    end
  end

  describe "decode/1 error handling" do
    test "returns error for insufficient data" do
      # Label says length 5 but only 3 bytes available
      data = <<5, "abc">>

      assert {:error, error} = Name.decode(data)
      assert error =~ "insufficient data"
    end

    test "returns error for invalid label length > 63" do
      data = <<64, "x">>

      assert {:error, error} = Name.decode(data)
      assert error =~ "invalid label length"
    end

    test "returns error for unexpected end of data" do
      # Label without null terminator
      data = <<3, "com">>

      assert {:error, error} = Name.decode(data)
      assert error =~ "unexpected end of data"
    end

    test "returns error for circular compression pointer" do
      # Pointer that points to itself (offset 0 contains pointer to offset 0)
      message = <<0xC0, 0x00>>

      assert {:error, error} = Name.decode(message, message)
      assert error =~ "circular compression pointer"
    end

    test "returns error for circular pointer chain" do
      # Offset 0: pointer to 2
      # Offset 2: pointer to 0 (creates cycle)
      message = <<0xC0, 0x02, 0xC0, 0x00>>

      assert {:error, error} = Name.decode(message, message)
      assert error =~ "circular compression pointer"
    end
  end

  describe "round-trip encoding and decoding" do
    test "round-trips a simple name" do
      original = "example.com"

      {encoded, _map} = Name.encode(original)
      assert {:ok, decoded, <<>>} = Name.decode(encoded)

      assert decoded == original
    end

    test "round-trips a multi-label name" do
      original = "foo.bar.baz.example.com"

      {encoded, _map} = Name.encode(original)
      assert {:ok, decoded, <<>>} = Name.decode(encoded)

      assert decoded == original
    end

    test "round-trips empty name" do
      original = ""

      {encoded, _map} = Name.encode(original)
      assert {:ok, decoded, <<>>} = Name.decode(encoded)

      assert decoded == original
    end

    test "round-trips multiple names with compression" do
      names = ["example.com", "foo.example.com", "bar.example.com"]

      # Encode all names with compression
      {encoded_message, _final_map} =
        Enum.reduce(names, {<<>>, %{}}, fn name, {acc, map} ->
          base_offset = byte_size(acc)
          {encoded, new_map} = Name.encode(name, map, base_offset)
          {acc <> encoded, new_map}
        end)

      # Decode all names
      {decoded_names, remaining} =
        Enum.reduce(1..3, {[], encoded_message}, fn _, {names_acc, data} ->
          {:ok, name, rest} = Name.decode(data, encoded_message)
          {names_acc ++ [name], rest}
        end)

      assert decoded_names == names
      assert remaining == <<>>
    end
  end

  describe "complex compression scenarios" do
    test "decodes mDNS-style service names with compression" do
      # Typical mDNS: "_http._tcp.local" followed by "myservice._http._tcp.local"
      {enc1, map1} = Name.encode("_http._tcp.local")
      {enc2, _map2} = Name.encode("myservice._http._tcp.local", map1, byte_size(enc1))

      message = enc1 <> enc2

      # Decode first name
      {:ok, name1, rest} = Name.decode(message, message)
      assert name1 == "_http._tcp.local"

      # Decode second name (should use compression)
      {:ok, name2, <<>>} = Name.decode(rest, message)
      assert name2 == "myservice._http._tcp.local"
    end

    test "handles multiple pointers in a message" do
      # Create a message with multiple names sharing suffixes
      names = [
        "local",
        "_tcp.local",
        "_http._tcp.local",
        "service1._http._tcp.local",
        "service2._http._tcp.local"
      ]

      # Encode with progressive compression
      {message, _} =
        Enum.reduce(names, {<<>>, %{}}, fn name, {acc, map} ->
          base_offset = byte_size(acc)
          {encoded, new_map} = Name.encode(name, map, base_offset)
          {acc <> encoded, new_map}
        end)

      # Decode all names
      {decoded, remaining} =
        Enum.reduce(names, {[], message}, fn _, {acc, data} ->
          {:ok, name, rest} = Name.decode(data, message)
          {acc ++ [name], rest}
        end)

      assert decoded == names
      assert remaining == <<>>
    end

    test "compression reduces message size" do
      # Without compression
      {enc1_no_comp, _} = Name.encode("example.com")
      {enc2_no_comp, _} = Name.encode("foo.example.com")

      size_without_compression = byte_size(enc1_no_comp) + byte_size(enc2_no_comp)

      # With compression
      {enc1, map1} = Name.encode("example.com")
      {enc2, _} = Name.encode("foo.example.com", map1, byte_size(enc1))

      size_with_compression = byte_size(enc1) + byte_size(enc2)

      # Compression should save bytes
      assert size_with_compression < size_without_compression

      # Specifically: saved "example.com" (13 bytes) vs pointer (2 bytes) = 11 bytes saved
      assert size_without_compression - size_with_compression == 11
    end
  end
end
