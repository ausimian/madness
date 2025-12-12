defmodule Madness.QuestionTest do
  use ExUnit.Case, async: true
  import Bitwise

  alias Madness.Question

  describe "encode/1 with atom types" do
    test "encodes a simple A record question" do
      question = %Question{name: "example.com", type: :a, class: :in}

      {encoded, _map} = Question.encode(question)

      # Should be: name + type (1) + class (1)
      # Name: 7 example 3 com 0 = 13 bytes
      # Type: 2 bytes
      # Class: 2 bytes
      # Total: 17 bytes
      assert byte_size(encoded) == 17

      # Extract and verify type and class at the end
      <<_name::binary-size(13), type::16, class::16>> = encoded
      # A record
      assert type == 1
      # IN class
      assert class == 1
    end

    test "encodes PTR record question" do
      question = %Question{name: "_http._tcp.local", type: :ptr, class: :in}

      {encoded, _map} = Question.encode(question)

      name_size = byte_size(encoded) - 4
      <<_name::binary-size(name_size), type::16, _class::16>> = encoded
      # PTR
      assert type == 12
    end

    test "encodes SRV record question" do
      question = %Question{name: "myservice._http._tcp.local", type: :srv, class: :in}

      {encoded, _map} = Question.encode(question)

      name_size = byte_size(encoded) - 4
      <<_name::binary-size(name_size), type::16, _class::16>> = encoded
      # SRV
      assert type == 33
    end

    test "encodes TXT record question" do
      question = %Question{name: "example.com", type: :txt, class: :in}

      {encoded, _map} = Question.encode(question)

      name_size = byte_size(encoded) - 4
      <<_name::binary-size(name_size), type::16, _class::16>> = encoded
      # TXT
      assert type == 16
    end

    test "encodes AAAA record question" do
      question = %Question{name: "example.com", type: :aaaa, class: :in}

      {encoded, _map} = Question.encode(question)

      name_size = byte_size(encoded) - 4
      <<_name::binary-size(name_size), type::16, _class::16>> = encoded
      # AAAA
      assert type == 28
    end

    test "encodes ANY type question" do
      question = %Question{name: "example.com", type: :any, class: :in}

      {encoded, _map} = Question.encode(question)

      name_size = byte_size(encoded) - 4
      <<_name::binary-size(name_size), type::16, _class::16>> = encoded
      # ANY
      assert type == 255
    end
  end

  describe "encode/1 with integer types" do
    test "encodes question with integer type" do
      question = %Question{name: "example.com", type: 1, class: :in}

      {encoded, _map} = Question.encode(question)

      name_size = byte_size(encoded) - 4
      <<_name::binary-size(name_size), type::16, _class::16>> = encoded
      assert type == 1
    end

    test "encodes question with unknown integer type" do
      # Type 999 is not a known type
      question = %Question{name: "example.com", type: 999, class: :in}

      {encoded, _map} = Question.encode(question)

      name_size = byte_size(encoded) - 4
      <<_name::binary-size(name_size), type::16, _class::16>> = encoded
      assert type == 999
    end
  end

  describe "encode/1 with unicast_response flag" do
    test "encodes with unicast_response=false (default)" do
      question = %Question{name: "example.com", type: :a, class: :in}

      {encoded, _map} = Question.encode(question)

      name_size = byte_size(encoded) - 4
      <<_name::binary-size(name_size), _type::16, class::16>> = encoded

      # Top bit should not be set
      assert (class &&& 0x8000) == 0
      # IN class
      assert (class &&& 0x7FFF) == 1
    end

    test "encodes with unicast_response=true" do
      question = %Question{name: "example.com", type: :a, class: :in, unicast_response: true}

      {encoded, _map} = Question.encode(question)

      name_size = byte_size(encoded) - 4
      <<_name::binary-size(name_size), _type::16, class::16>> = encoded

      # Top bit should be set
      assert (class &&& 0x8000) == 0x8000
      # IN class
      assert (class &&& 0x7FFF) == 1
    end
  end

  describe "encode/3 with compression" do
    test "uses suffix_map for name compression" do
      # First encode a name
      {enc1, map1} = Question.encode(%Question{name: "example.com", type: :a, class: :in})

      # Second encode should use compression
      # base_offset should be the size of the first encoded question
      {enc2, _map2} =
        Question.encode(
          %Question{name: "foo.example.com", type: :a, class: :in},
          map1,
          byte_size(enc1)
        )

      # Name: 1 (len) + 3 ("foo") + 2 (pointer) = 6 bytes
      # Type: 2 bytes
      # Class: 2 bytes
      # Total: 10 bytes
      assert byte_size(enc2) == 10
    end

    test "tracks base_offset correctly" do
      question = %Question{name: "example.com", type: :a, class: :in}

      {_encoded, map} = Question.encode(question, %{}, 100)

      # Suffix map should contain offsets starting at 100
      assert map["example.com"] == 100
      assert map["com"] == 108
    end
  end

  describe "decode/2" do
    test "decodes a simple A record question" do
      # Manually construct: "example.com" + type A + class IN
      data = <<7, "example"::binary, 3, "com"::binary, 0, 0, 1, 0, 1>>

      assert {:ok, question, <<>>} = Question.decode(data)
      assert question.name == "example.com"
      assert question.type == :a
      assert question.class == :in
      assert question.unicast_response == false
    end

    test "decodes PTR record question" do
      data = <<5, "local"::binary, 0, 0, 12, 0, 1>>

      assert {:ok, question, <<>>} = Question.decode(data)
      assert question.name == "local"
      assert question.type == :ptr
      assert question.class == :in
    end

    test "decodes SRV record question" do
      data = <<7, "example"::binary, 3, "com"::binary, 0, 0, 33, 0, 1>>

      assert {:ok, question, <<>>} = Question.decode(data)
      assert question.type == :srv
    end

    test "decodes TXT record question" do
      data = <<7, "example"::binary, 3, "com"::binary, 0, 0, 16, 0, 1>>

      assert {:ok, question, <<>>} = Question.decode(data)
      assert question.type == :txt
    end

    test "decodes AAAA record question" do
      data = <<7, "example"::binary, 3, "com"::binary, 0, 0, 28, 0, 1>>

      assert {:ok, question, <<>>} = Question.decode(data)
      assert question.type == :aaaa
    end

    test "decodes ANY type question" do
      data = <<7, "example"::binary, 3, "com"::binary, 0, 0, 255, 0, 1>>

      assert {:ok, question, <<>>} = Question.decode(data)
      assert question.type == :any
    end

    test "decodes unknown type as integer" do
      # Type 999 is not a known type
      data = <<7, "example"::binary, 3, "com"::binary, 0, 3, 231, 0, 1>>

      assert {:ok, question, <<>>} = Question.decode(data)
      assert question.type == 999
      assert is_integer(question.type)
    end

    test "decodes unicast_response flag when set" do
      # Class with top bit set: 0x8001
      data = <<7, "example"::binary, 3, "com"::binary, 0, 0, 1, 0x80, 0x01>>

      assert {:ok, question, <<>>} = Question.decode(data)
      assert question.unicast_response == true
      assert question.class == :in
    end

    test "decodes unicast_response flag when not set" do
      data = <<7, "example"::binary, 3, "com"::binary, 0, 0, 1, 0, 1>>

      assert {:ok, question, <<>>} = Question.decode(data)
      assert question.unicast_response == false
    end

    test "returns remaining data after question" do
      data = <<7, "example"::binary, 3, "com"::binary, 0, 0, 1, 0, 1, "extra">>

      assert {:ok, question, rest} = Question.decode(data)
      assert question.name == "example.com"
      assert rest == "extra"
    end

    test "returns error for insufficient data" do
      # Missing class bytes
      data = <<7, "example"::binary, 3, "com"::binary, 0, 0, 1>>

      assert {:error, error} = Question.decode(data)
      assert error =~ "insufficient data"
    end
  end

  describe "decode/2 with compression" do
    test "decodes question with compressed name" do
      # Message with compression: "com\0" at offset 0, then "example" + pointer
      message = <<3, "com"::binary, 0, 7, "example"::binary, 0xC0, 0x00, 0, 1, 0, 1>>

      # Decode from offset 5 (the "example" part)
      data = binary_part(message, 5, byte_size(message) - 5)

      assert {:ok, question, <<>>} = Question.decode(data, message)
      assert question.name == "example.com"
      assert question.type == :a
    end
  end

  describe "round-trip encoding and decoding" do
    test "round-trips A record question" do
      original = %Question{name: "example.com", type: :a, class: :in}

      {encoded, _map} = Question.encode(original)
      assert {:ok, decoded, <<>>} = Question.decode(encoded)

      assert decoded.name == original.name
      assert decoded.type == original.type
      assert decoded.class == original.class
      assert decoded.unicast_response == original.unicast_response
    end

    test "round-trips PTR record question" do
      original = %Question{name: "_http._tcp.local", type: :ptr, class: :in}

      {encoded, _map} = Question.encode(original)
      assert {:ok, decoded, <<>>} = Question.decode(encoded)

      assert decoded == original
    end

    test "round-trips SRV record question" do
      original = %Question{name: "myservice._http._tcp.local", type: :srv, class: :in}

      {encoded, _map} = Question.encode(original)
      assert {:ok, decoded, <<>>} = Question.decode(encoded)

      assert decoded == original
    end

    test "round-trips with unicast_response flag" do
      original = %Question{
        name: "example.com",
        type: :a,
        class: :in,
        unicast_response: true
      }

      {encoded, _map} = Question.encode(original)
      assert {:ok, decoded, <<>>} = Question.decode(encoded)

      assert decoded == original
    end

    test "round-trips all common record types" do
      types = [:a, :ns, :cname, :ptr, :txt, :aaaa, :srv, :nsec, :any]

      for type <- types do
        original = %Question{name: "example.com", type: type, class: :in}

        {encoded, _map} = Question.encode(original)
        assert {:ok, decoded, <<>>} = Question.decode(encoded)

        assert decoded == original
      end
    end

    test "round-trips unknown integer type" do
      original = %Question{name: "example.com", type: 999, class: :in}

      {encoded, _map} = Question.encode(original)
      assert {:ok, decoded, <<>>} = Question.decode(encoded)

      assert decoded == original
      assert is_integer(decoded.type)
    end
  end

  describe "type and class conversions" do
    test "converts all known types to atoms on decode" do
      type_mappings = %{
        1 => :a,
        2 => :ns,
        5 => :cname,
        12 => :ptr,
        16 => :txt,
        28 => :aaaa,
        33 => :srv,
        47 => :nsec,
        255 => :any
      }

      for {int_type, atom_type} <- type_mappings do
        data = <<7, "example"::binary, 3, "com"::binary, 0, int_type::16, 0, 1>>

        assert {:ok, question, <<>>} = Question.decode(data)
        assert question.type == atom_type
      end
    end

    test "leaves unknown types as integers" do
      # Include SOA (6), HINFO (13), MX (15) which are no longer supported
      unknown_types = [3, 4, 6, 13, 15, 100, 500, 1000]

      for type_int <- unknown_types do
        data = <<7, "example"::binary, 3, "com"::binary, 0, type_int::16, 0, 1>>

        assert {:ok, question, <<>>} = Question.decode(data)
        assert question.type == type_int
        assert is_integer(question.type)
      end
    end

    test "converts known classes to atoms on decode" do
      # IN class
      data1 = <<7, "example"::binary, 3, "com"::binary, 0, 0, 1, 0, 1>>
      assert {:ok, question1, <<>>} = Question.decode(data1)
      assert question1.class == :in

      # ANY class
      data2 = <<7, "example"::binary, 3, "com"::binary, 0, 0, 1, 0, 255>>
      assert {:ok, question2, <<>>} = Question.decode(data2)
      assert question2.class == :any
    end
  end

  describe "multiple questions with compression" do
    test "encodes multiple questions sharing name suffixes" do
      q1 = %Question{name: "example.com", type: :a, class: :in}
      q2 = %Question{name: "foo.example.com", type: :a, class: :in}
      q3 = %Question{name: "bar.example.com", type: :a, class: :in}

      # Encode with progressive compression
      {enc1, map1} = Question.encode(q1)
      {enc2, map2} = Question.encode(q2, map1, byte_size(enc1))
      {enc3, _map3} = Question.encode(q3, map2, byte_size(enc1) + byte_size(enc2))

      # Build message
      message = enc1 <> enc2 <> enc3

      # Decode all three
      {:ok, decoded1, rest1} = Question.decode(message, message)
      {:ok, decoded2, rest2} = Question.decode(rest1, message)
      {:ok, decoded3, <<>>} = Question.decode(rest2, message)

      assert decoded1.name == "example.com"
      assert decoded2.name == "foo.example.com"
      assert decoded3.name == "bar.example.com"

      # Verify compression saved space
      uncompressed_size = byte_size(enc1) * 3
      compressed_size = byte_size(message)
      assert compressed_size < uncompressed_size
    end
  end
end
