defmodule Madness.HeaderTest do
  use ExUnit.Case, async: true
  import Bitwise

  alias Madness.Header

  describe "encode/1" do
    test "encodes a minimal header with defaults" do
      header = %Header{id: 0}

      # ID=0, flags=0x0100 (RD=1), all counts=0
      assert Header.encode(header) == <<0, 0, 0x01, 0x00, 0, 0, 0, 0, 0, 0, 0, 0>>
    end

    test "encodes a header with custom ID" do
      header = %Header{id: 12345}

      encoded = Header.encode(header)
      <<id::16, _rest::binary>> = encoded
      assert id == 12345
    end

    test "encodes QR flag correctly" do
      header_query = %Header{id: 1, qr: false}
      header_response = %Header{id: 1, qr: true}

      <<_id1::16, flags_query::16, _rest1::binary>> = Header.encode(header_query)
      <<_id2::16, flags_response::16, _rest2::binary>> = Header.encode(header_response)

      # QR is the most significant bit of flags
      assert (flags_query &&& 0x8000) == 0x0000
      assert (flags_response &&& 0x8000) == 0x8000
    end

    test "encodes opcode correctly" do
      header = %Header{id: 1, opcode: 5}

      <<_id::16, flags::16, _rest::binary>> = Header.encode(header)
      # Opcode is bits 11-14 (4 bits after QR)
      opcode = (flags &&& 0x7800) >>> 11
      assert opcode == 5
    end

    test "encodes all boolean flags" do
      header = %Header{
        id: 1,
        qr: true,
        aa: true,
        tc: true,
        rd: false,
        ra: true
      }

      <<_id::16, flags::16, _rest::binary>> = Header.encode(header)

      # QR
      assert (flags &&& 0x8000) == 0x8000
      # AA
      assert (flags &&& 0x0400) == 0x0400
      # TC
      assert (flags &&& 0x0200) == 0x0200
      # RD
      assert (flags &&& 0x0100) == 0x0000
      # RA
      assert (flags &&& 0x0080) == 0x0080
    end

    test "encodes rcode correctly" do
      header = %Header{id: 1, rcode: 3}

      <<_id::16, flags::16, _rest::binary>> = Header.encode(header)
      # RCODE is the last 4 bits
      rcode = flags &&& 0x000F
      assert rcode == 3
    end

    test "encodes all count fields" do
      header = %Header{
        id: 100,
        qdcount: 1,
        ancount: 2,
        nscount: 3,
        arcount: 4
      }

      <<_id::16, _flags::16, qdcount::16, ancount::16, nscount::16, arcount::16>> =
        Header.encode(header)

      assert qdcount == 1
      assert ancount == 2
      assert nscount == 3
      assert arcount == 4
    end

    test "encodes a complete header with all fields set" do
      header = %Header{
        id: 0xABCD,
        qr: true,
        opcode: 4,
        aa: true,
        tc: false,
        rd: true,
        ra: true,
        z: 0,
        rcode: 2,
        qdcount: 10,
        ancount: 20,
        nscount: 30,
        arcount: 40
      }

      encoded = Header.encode(header)
      assert byte_size(encoded) == 12
    end
  end

  describe "decode/1" do
    test "decodes a minimal header" do
      # ID=0, flags=0x0100 (RD=1), all counts=0
      data = <<0, 0, 0x01, 0x00, 0, 0, 0, 0, 0, 0, 0, 0>>

      header = Header.decode(data)
      assert header.id == 0
      assert header.qr == false
      assert header.rd == true
      assert header.qdcount == 0
    end

    test "decodes a header with custom ID" do
      data = <<0x12, 0x34, 0x01, 0x00, 0, 0, 0, 0, 0, 0, 0, 0>>

      header = Header.decode(data)
      assert header.id == 0x1234
    end

    test "decodes QR flag correctly" do
      query = <<0, 1, 0x01, 0x00, 0, 0, 0, 0, 0, 0, 0, 0>>
      response = <<0, 1, 0x81, 0x00, 0, 0, 0, 0, 0, 0, 0, 0>>

      query_header = Header.decode(query)
      response_header = Header.decode(response)

      assert query_header.qr == false
      assert response_header.qr == true
    end

    test "decodes opcode correctly" do
      data = <<0, 1, 0x29, 0x00, 0, 0, 0, 0, 0, 0, 0, 0>>

      header = Header.decode(data)
      assert header.opcode == 5
    end

    test "decodes all boolean flags" do
      # QR=1, opcode=0, AA=1, TC=1, RD=0, RA=1, Z=0, RCODE=0
      # Binary: 1000 0110 1000 0000 = 0x8680
      data = <<0, 1, 0x86, 0x80, 0, 0, 0, 0, 0, 0, 0, 0>>

      header = Header.decode(data)
      assert header.qr == true
      assert header.aa == true
      assert header.tc == true
      assert header.rd == false
      assert header.ra == true
    end

    test "decodes rcode correctly" do
      data = <<0, 1, 0x01, 0x03, 0, 0, 0, 0, 0, 0, 0, 0>>

      header = Header.decode(data)
      assert header.rcode == 3
    end

    test "decodes all count fields" do
      data = <<0, 1, 0x01, 0x00, 0, 1, 0, 2, 0, 3, 0, 4>>

      header = Header.decode(data)
      assert header.qdcount == 1
      assert header.ancount == 2
      assert header.nscount == 3
      assert header.arcount == 4
    end
  end

  describe "round-trip encoding and decoding" do
    test "round-trips a minimal header" do
      original = %Header{id: 0}

      encoded = Header.encode(original)
      decoded = Header.decode(encoded)

      assert decoded == original
    end

    test "round-trips a header with all flags set to true" do
      original = %Header{
        id: 42,
        qr: true,
        aa: true,
        tc: true,
        rd: true,
        ra: true
      }

      encoded = Header.encode(original)
      decoded = Header.decode(encoded)

      assert decoded == original
    end

    test "round-trips a header with all flags set to false" do
      original = %Header{
        id: 42,
        qr: false,
        aa: false,
        tc: false,
        rd: false,
        ra: false
      }

      encoded = Header.encode(original)
      decoded = Header.decode(encoded)

      assert decoded == original
    end

    test "round-trips a header with various opcode values" do
      for opcode <- 0..15 do
        original = %Header{id: 1, opcode: opcode}

        encoded = Header.encode(original)
        decoded = Header.decode(encoded)

        assert decoded.opcode == opcode
      end
    end

    test "round-trips a header with various rcode values" do
      for rcode <- 0..15 do
        original = %Header{id: 1, rcode: rcode}

        encoded = Header.encode(original)
        decoded = Header.decode(encoded)

        assert decoded.rcode == rcode
      end
    end

    test "round-trips a header with maximum count values" do
      original = %Header{
        id: 65535,
        qdcount: 65535,
        ancount: 65535,
        nscount: 65535,
        arcount: 65535
      }

      encoded = Header.encode(original)
      decoded = Header.decode(encoded)

      assert decoded == original
    end

    test "round-trips a complete header with all fields set" do
      original = %Header{
        id: 0xABCD,
        qr: true,
        opcode: 4,
        aa: true,
        tc: false,
        rd: true,
        ra: true,
        z: 5,
        rcode: 2,
        qdcount: 10,
        ancount: 20,
        nscount: 30,
        arcount: 40
      }

      encoded = Header.encode(original)
      decoded = Header.decode(encoded)

      assert decoded == original
    end

    test "round-trips multiple random headers" do
      for _ <- 1..100 do
        original = %Header{
          id: :rand.uniform(65536) - 1,
          qr: Enum.random([true, false]),
          opcode: :rand.uniform(16) - 1,
          aa: Enum.random([true, false]),
          tc: Enum.random([true, false]),
          rd: Enum.random([true, false]),
          ra: Enum.random([true, false]),
          z: :rand.uniform(8) - 1,
          rcode: :rand.uniform(16) - 1,
          qdcount: :rand.uniform(1000),
          ancount: :rand.uniform(1000),
          nscount: :rand.uniform(1000),
          arcount: :rand.uniform(1000)
        }

        encoded = Header.encode(original)
        decoded = Header.decode(encoded)

        assert decoded == original
      end
    end
  end

  describe "edge cases" do
    test "encoded header is always 12 bytes" do
      header = %Header{id: 0}
      assert byte_size(Header.encode(header)) == 12
    end

    test "decode handles exactly 12 bytes" do
      data = <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
      header = Header.decode(data)
      assert %Header{} = header
    end
  end
end
