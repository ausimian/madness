defmodule Madness.MessageTest do
  use ExUnit.Case, async: true

  alias Madness.{Message, Header, Question, Resource}

  describe "round-trip encoding and decoding" do
    test "round-trips an empty message (header only)" do
      original = %Message{
        header: %Header{id: 1234}
      }

      {iodata, _suffix_map} = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert decoded.header.id == original.header.id
      assert decoded.questions == []
      assert decoded.answers == []
      assert decoded.authorities == []
      assert decoded.additionals == []
    end

    test "round-trips a message with one question" do
      original = %Message{
        header: %Header{id: 1},
        questions: [
          %Question{name: "example.com", type: :a, class: :in}
        ]
      }

      {iodata, _suffix_map} = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert decoded.header.id == 1
      assert decoded.header.qdcount == 1
      assert length(decoded.questions) == 1
      assert hd(decoded.questions).name == "example.com"
      assert hd(decoded.questions).type == :a
    end

    test "round-trips a message with multiple questions" do
      original = %Message{
        header: %Header{id: 42},
        questions: [
          %Question{name: "example.com", type: :a, class: :in},
          %Question{name: "example.com", type: :aaaa, class: :in},
          %Question{name: "other.example.com", type: :ptr, class: :in}
        ]
      }

      {iodata, _suffix_map} = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert decoded.header.qdcount == 3
      assert length(decoded.questions) == 3

      [q1, q2, q3] = decoded.questions
      assert q1.name == "example.com"
      assert q1.type == :a
      assert q2.name == "example.com"
      assert q2.type == :aaaa
      assert q3.name == "other.example.com"
      assert q3.type == :ptr
    end

    test "round-trips a message with one answer" do
      original = %Message{
        header: %Header{id: 100, qr: true},
        answers: [
          %Resource{
            name: "example.com",
            type: :a,
            class: :in,
            ttl: 300,
            rdata: <<192, 168, 1, 1>>
          }
        ]
      }

      {iodata, _suffix_map} = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert decoded.header.qr == true
      assert decoded.header.ancount == 1
      assert length(decoded.answers) == 1

      answer = hd(decoded.answers)
      assert answer.name == "example.com"
      assert answer.type == :a
      assert answer.ttl == 300
      assert answer.rdata == {192, 168, 1, 1}
    end

    test "round-trips a message with all sections populated" do
      original = %Message{
        header: %Header{id: 9999, qr: true, aa: true},
        questions: [
          %Question{name: "_http._tcp.local", type: :ptr, class: :in}
        ],
        answers: [
          %Resource{
            name: "_http._tcp.local",
            type: :ptr,
            class: :in,
            ttl: 4500,
            rdata: <<7, "myhost", 6, "_http", 4, "_tcp", 5, "local", 0>>
          }
        ],
        authorities: [
          %Resource{
            name: "local",
            type: :ns,
            class: :in,
            ttl: 1000,
            rdata: <<2, "ns", 5, "local", 0>>
          }
        ],
        additionals: [
          %Resource{
            name: "myhost.local",
            type: :a,
            class: :in,
            ttl: 120,
            rdata: <<10, 0, 0, 1>>
          }
        ]
      }

      {iodata, _suffix_map} = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)

      assert decoded.header.id == 9999
      assert decoded.header.qr == true
      assert decoded.header.aa == true
      assert decoded.header.qdcount == 1
      assert decoded.header.ancount == 1
      assert decoded.header.nscount == 1
      assert decoded.header.arcount == 1

      assert length(decoded.questions) == 1
      assert length(decoded.answers) == 1
      assert length(decoded.authorities) == 1
      assert length(decoded.additionals) == 1

      assert hd(decoded.questions).name == "_http._tcp.local"
      assert hd(decoded.answers).name == "_http._tcp.local"
      assert hd(decoded.authorities).name == "local"
      assert hd(decoded.additionals).name == "myhost.local"
    end

    test "round-trips a message with unicast_response flag" do
      original = %Message{
        header: %Header{id: 1},
        questions: [
          %Question{name: "example.com", type: :a, class: :in, unicast_response: true}
        ]
      }

      {iodata, _suffix_map} = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert hd(decoded.questions).unicast_response == true
    end

    test "round-trips a message with cache_flush flag" do
      original = %Message{
        header: %Header{id: 1, qr: true},
        answers: [
          %Resource{
            name: "example.com",
            type: :a,
            class: :in,
            cache_flush: true,
            ttl: 120,
            rdata: <<1, 2, 3, 4>>
          }
        ]
      }

      {iodata, _suffix_map} = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert hd(decoded.answers).cache_flush == true
    end

    test "round-trips preserves all record types" do
      types = [:a, :ns, :cname, :ptr, :txt, :aaaa, :srv, :nsec, :any]

      for type <- types do
        original = %Message{
          header: %Header{id: 1},
          questions: [%Question{name: "test.local", type: type, class: :in}]
        }

        {iodata, _suffix_map} = Message.encode(original)
        binary = IO.iodata_to_binary(iodata)

        assert {:ok, decoded, <<>>} = Message.decode(binary)
        assert hd(decoded.questions).type == type
      end
    end

    test "uses name compression across sections" do
      original = %Message{
        header: %Header{id: 1, qr: true},
        questions: [
          %Question{name: "example.com", type: :a, class: :in}
        ],
        answers: [
          %Resource{
            name: "example.com",
            type: :a,
            class: :in,
            ttl: 300,
            rdata: <<1, 2, 3, 4>>
          }
        ]
      }

      {iodata, _suffix_map} = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      # Verify compression saved space - answer name should be compressed
      # Header: 12, Question: 13 (name) + 4 = 17, Answer: 2 (ptr) + 10 = 12
      # Without compression answer would be 13 + 10 = 23
      assert byte_size(binary) < 12 + 17 + 23

      # Verify decoding still works
      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert hd(decoded.answers).name == "example.com"
    end
  end

  describe "decode/1 error handling" do
    test "returns error for insufficient data" do
      assert {:error, msg} = Message.decode(<<1, 2, 3>>)
      assert msg =~ "insufficient data"
    end

    test "returns error for empty data" do
      assert {:error, msg} = Message.decode(<<>>)
      assert msg =~ "insufficient data"
    end

    test "returns error when question decoding fails" do
      # Header says 1 question but question data is truncated
      header = <<0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0>>
      truncated_question = <<7, "example", 3, "com", 0>>

      assert {:error, _msg} = Message.decode(header <> truncated_question)
    end

    test "returns error when answer decoding fails" do
      # Header says 0 questions, 1 answer, but answer data is truncated
      header = <<0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0>>
      truncated_answer = <<7, "example", 3, "com", 0, 0, 1>>

      assert {:error, _msg} = Message.decode(header <> truncated_answer)
    end

    test "returns error when authority decoding fails" do
      # Header says 0 questions, 0 answers, 1 authority, but data is truncated
      header = <<0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0>>
      truncated_authority = <<5, "local", 0, 0, 2>>

      assert {:error, _msg} = Message.decode(header <> truncated_authority)
    end

    test "returns error when additional decoding fails" do
      # Header says 0 questions, 0 answers, 0 authorities, 1 additional, but data is truncated
      header = <<0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1>>
      truncated_additional = <<5, "local", 0, 0, 1>>

      assert {:error, _msg} = Message.decode(header <> truncated_additional)
    end
  end

  describe "encode/1 updates header counts" do
    test "sets correct counts in header" do
      original = %Message{
        header: %Header{id: 1, qdcount: 0, ancount: 0, nscount: 0, arcount: 0},
        questions: [
          %Question{name: "a.local", type: :a, class: :in},
          %Question{name: "b.local", type: :a, class: :in}
        ],
        answers: [
          %Resource{name: "c.local", type: :a, class: :in, ttl: 100, rdata: <<1, 2, 3, 4>>}
        ],
        authorities: [],
        additionals: [
          %Resource{name: "d.local", type: :a, class: :in, ttl: 100, rdata: <<5, 6, 7, 8>>},
          %Resource{name: "e.local", type: :a, class: :in, ttl: 100, rdata: <<9, 10, 11, 12>>},
          %Resource{name: "f.local", type: :a, class: :in, ttl: 100, rdata: <<13, 14, 15, 16>>}
        ]
      }

      {iodata, _suffix_map} = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert decoded.header.qdcount == 2
      assert decoded.header.ancount == 1
      assert decoded.header.nscount == 0
      assert decoded.header.arcount == 3
    end
  end
end
