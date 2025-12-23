defmodule Madness.MessageTest do
  use ExUnit.Case, async: true

  alias Madness.{Message, Header, Question, Resource}

  describe "round-trip encoding and decoding" do
    test "round-trips an empty message (header only)" do
      original = %Message{
        header: %Header{id: 1234}
      }

      iodata = Message.encode(original)
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

      iodata = Message.encode(original)
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

      iodata = Message.encode(original)
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
            rdata: {192, 168, 1, 1}
          }
        ]
      }

      iodata = Message.encode(original)
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
            rdata: "myhost._http._tcp.local"
          }
        ],
        authorities: [
          %Resource{
            name: "local",
            type: :ns,
            class: :in,
            ttl: 1000,
            rdata: "ns.local"
          }
        ],
        additionals: [
          %Resource{
            name: "myhost.local",
            type: :a,
            class: :in,
            ttl: 120,
            rdata: {10, 0, 0, 1}
          }
        ]
      }

      iodata = Message.encode(original)
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

      iodata = Message.encode(original)
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
            rdata: {1, 2, 3, 4}
          }
        ]
      }

      iodata = Message.encode(original)
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

        iodata = Message.encode(original)
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
            rdata: {1, 2, 3, 4}
          }
        ]
      }

      iodata = Message.encode(original)
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
          %Resource{name: "c.local", type: :a, class: :in, ttl: 100, rdata: {1, 2, 3, 4}}
        ],
        authorities: [],
        additionals: [
          %Resource{name: "d.local", type: :a, class: :in, ttl: 100, rdata: {5, 6, 7, 8}},
          %Resource{name: "e.local", type: :a, class: :in, ttl: 100, rdata: {9, 10, 11, 12}},
          %Resource{name: "f.local", type: :a, class: :in, ttl: 100, rdata: {13, 14, 15, 16}}
        ]
      }

      iodata = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert decoded.header.qdcount == 2
      assert decoded.header.ancount == 1
      assert decoded.header.nscount == 0
      assert decoded.header.arcount == 3
    end
  end

  describe "new/0" do
    test "creates an empty message with default header" do
      message = Message.new()

      assert %Message{} = message
      assert %Header{} = message.header
      assert message.header.id == 0
      assert message.questions == []
      assert message.answers == []
      assert message.authorities == []
      assert message.additionals == []
    end

    test "default header has expected values" do
      message = Message.new()

      assert message.header.qr == false
      assert message.header.opcode == 0
      assert message.header.aa == false
      assert message.header.tc == false
      assert message.header.rd == true
      assert message.header.ra == false
      assert message.header.rcode == 0
      assert message.header.qdcount == 0
      assert message.header.ancount == 0
      assert message.header.nscount == 0
      assert message.header.arcount == 0
    end
  end

  describe "encode_query/1" do
    test "encodes a single question as a query" do
      questions = [%Question{name: "example.com", type: :a, class: :in}]

      iodata = Message.encode_query(questions)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert length(decoded.questions) == 1
      assert hd(decoded.questions).name == "example.com"
      assert hd(decoded.questions).type == :a
      assert decoded.answers == []
      assert decoded.authorities == []
      assert decoded.additionals == []
    end

    test "encodes multiple questions as a query" do
      questions = [
        %Question{name: "example.com", type: :a, class: :in},
        %Question{name: "example.com", type: :aaaa, class: :in},
        %Question{name: "other.com", type: :txt, class: :in}
      ]

      iodata = Message.encode_query(questions)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert length(decoded.questions) == 3
      assert decoded.header.qdcount == 3
      assert decoded.answers == []
    end

    test "encodes query with correct header" do
      questions = [%Question{name: "test.local", type: :ptr, class: :in}]

      iodata = Message.encode_query(questions)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert decoded.header.qr == false
      assert decoded.header.qdcount == 1
      assert decoded.header.ancount == 0
      assert decoded.header.nscount == 0
      assert decoded.header.arcount == 0
    end

    test "encodes empty query" do
      iodata = Message.encode_query([])
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert decoded.questions == []
      assert decoded.header.qdcount == 0
    end
  end

  describe "complex RDATA types" do
    test "round-trips message with SRV records" do
      original = %Message{
        header: %Header{id: 100, qr: true},
        answers: [
          %Resource{
            name: "_http._tcp.local",
            type: :srv,
            class: :in,
            ttl: 120,
            rdata: %{priority: 10, weight: 20, port: 8080, target: "server.local"}
          }
        ]
      }

      iodata = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      answer = hd(decoded.answers)
      assert answer.type == :srv
      assert answer.rdata.priority == 10
      assert answer.rdata.weight == 20
      assert answer.rdata.port == 8080
      assert answer.rdata.target == "server.local"
    end

    test "round-trips message with TXT records" do
      original = %Message{
        header: %Header{id: 200, qr: true},
        answers: [
          %Resource{
            name: "service.local",
            type: :txt,
            class: :in,
            ttl: 4500,
            rdata: ["txtvers=1", "key=value", "foo=bar"]
          }
        ]
      }

      iodata = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      answer = hd(decoded.answers)
      assert answer.type == :txt
      assert answer.rdata == ["txtvers=1", "key=value", "foo=bar"]
    end

    test "round-trips message with AAAA records" do
      original = %Message{
        header: %Header{id: 300, qr: true},
        answers: [
          %Resource{
            name: "ipv6.example.com",
            type: :aaaa,
            class: :in,
            ttl: 300,
            rdata: {0x2001, 0x0DB8, 0, 0, 0, 0, 0, 1}
          }
        ]
      }

      iodata = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      answer = hd(decoded.answers)
      assert answer.type == :aaaa
      assert answer.rdata == {0x2001, 0x0DB8, 0, 0, 0, 0, 0, 1}
    end

    test "round-trips message with NSEC records" do
      original = %Message{
        header: %Header{id: 400, qr: true},
        answers: [
          %Resource{
            name: "example.com",
            type: :nsec,
            class: :in,
            ttl: 120,
            rdata: %{name: "next.example.com", types: [:a, :ns, :txt]}
          }
        ]
      }

      iodata = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      answer = hd(decoded.answers)
      assert answer.type == :nsec
      assert answer.rdata.name == "next.example.com"
      assert :a in answer.rdata.types
      assert :ns in answer.rdata.types
      assert :txt in answer.rdata.types
    end

    test "round-trips message with CNAME records" do
      original = %Message{
        header: %Header{id: 500, qr: true},
        answers: [
          %Resource{
            name: "alias.example.com",
            type: :cname,
            class: :in,
            ttl: 600,
            rdata: "canonical.example.com"
          }
        ]
      }

      iodata = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      answer = hd(decoded.answers)
      assert answer.type == :cname
      assert answer.rdata == "canonical.example.com"
    end

    test "round-trips message with PTR records" do
      original = %Message{
        header: %Header{id: 600, qr: true},
        answers: [
          %Resource{
            name: "_services._dns-sd._udp.local",
            type: :ptr,
            class: :in,
            ttl: 4500,
            rdata: "_http._tcp.local"
          }
        ]
      }

      iodata = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      answer = hd(decoded.answers)
      assert answer.type == :ptr
      assert answer.rdata == "_http._tcp.local"
    end
  end

  describe "name compression across all sections" do
    test "compresses names across question, answer, authority, and additional sections" do
      original = %Message{
        header: %Header{id: 777, qr: true},
        questions: [
          %Question{name: "example.com", type: :a, class: :in}
        ],
        answers: [
          %Resource{
            name: "example.com",
            type: :a,
            class: :in,
            ttl: 300,
            rdata: {1, 2, 3, 4}
          },
          %Resource{
            name: "www.example.com",
            type: :a,
            class: :in,
            ttl: 300,
            rdata: {5, 6, 7, 8}
          }
        ],
        authorities: [
          %Resource{
            name: "example.com",
            type: :ns,
            class: :in,
            ttl: 3600,
            rdata: "ns.example.com"
          }
        ],
        additionals: [
          %Resource{
            name: "ns.example.com",
            type: :a,
            class: :in,
            ttl: 3600,
            rdata: {9, 10, 11, 12}
          }
        ]
      }

      iodata = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      # Verify significant compression occurred
      # "example.com" appears 4 times, "ns.example.com" appears 2 times
      # Without compression this would be much larger
      uncompressed_estimate = 12 + 17 + 4 * 23 + 2 * 26
      assert byte_size(binary) < uncompressed_estimate

      # Verify decoding works correctly
      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert hd(decoded.questions).name == "example.com"
      assert Enum.at(decoded.answers, 0).name == "example.com"
      assert Enum.at(decoded.answers, 1).name == "www.example.com"
      assert hd(decoded.authorities).name == "example.com"
      assert hd(decoded.additionals).name == "ns.example.com"
    end

    test "compresses SRV target names" do
      original = %Message{
        header: %Header{id: 888, qr: true},
        answers: [
          %Resource{
            name: "_http._tcp.local",
            type: :srv,
            class: :in,
            ttl: 120,
            rdata: %{priority: 0, weight: 0, port: 80, target: "server.local"}
          },
          %Resource{
            name: "_https._tcp.local",
            type: :srv,
            class: :in,
            ttl: 120,
            rdata: %{priority: 0, weight: 0, port: 443, target: "server.local"}
          }
        ],
        additionals: [
          %Resource{
            name: "server.local",
            type: :a,
            class: :in,
            ttl: 120,
            rdata: {192, 168, 1, 100}
          }
        ]
      }

      iodata = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert Enum.at(decoded.answers, 0).rdata.target == "server.local"
      assert Enum.at(decoded.answers, 1).rdata.target == "server.local"
      assert hd(decoded.additionals).name == "server.local"
    end
  end

  describe "decode/1 with remaining bytes" do
    test "returns remaining bytes after valid message" do
      message = %Message{
        header: %Header{id: 1},
        questions: [%Question{name: "test.local", type: :a, class: :in}]
      }

      iodata = Message.encode(message)
      binary = IO.iodata_to_binary(iodata)
      extra_data = <<1, 2, 3, 4, 5>>
      binary_with_extra = binary <> extra_data

      assert {:ok, decoded, rest} = Message.decode(binary_with_extra)
      assert rest == extra_data
      assert decoded.header.id == 1
    end

    test "handles multiple messages in stream" do
      msg1 = %Message{
        header: %Header{id: 1},
        questions: [%Question{name: "first.local", type: :a, class: :in}]
      }

      msg2 = %Message{
        header: %Header{id: 2},
        questions: [%Question{name: "second.local", type: :a, class: :in}]
      }

      binary1 = IO.iodata_to_binary(Message.encode(msg1))
      binary2 = IO.iodata_to_binary(Message.encode(msg2))
      combined = binary1 <> binary2

      assert {:ok, decoded1, rest} = Message.decode(combined)
      assert decoded1.header.id == 1
      assert hd(decoded1.questions).name == "first.local"

      assert {:ok, decoded2, <<>>} = Message.decode(rest)
      assert decoded2.header.id == 2
      assert hd(decoded2.questions).name == "second.local"
    end
  end

  describe "header flags combinations" do
    test "round-trips message with all boolean flags set" do
      original = %Message{
        header: %Header{
          id: 12345,
          qr: true,
          aa: true,
          tc: true,
          rd: true,
          ra: true
        },
        questions: [%Question{name: "test.local", type: :a, class: :in}]
      }

      iodata = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert decoded.header.qr == true
      assert decoded.header.aa == true
      assert decoded.header.tc == true
      assert decoded.header.rd == true
      assert decoded.header.ra == true
    end

    test "round-trips message with opcode set" do
      for opcode <- [0, 1, 2, 4, 5] do
        original = %Message{
          header: %Header{id: 1, opcode: opcode},
          questions: [%Question{name: "test.local", type: :a, class: :in}]
        }

        iodata = Message.encode(original)
        binary = IO.iodata_to_binary(iodata)

        assert {:ok, decoded, <<>>} = Message.decode(binary)
        assert decoded.header.opcode == opcode
      end
    end

    test "round-trips message with rcode set" do
      for rcode <- [0, 1, 2, 3, 4, 5] do
        original = %Message{
          header: %Header{id: 1, qr: true, rcode: rcode}
        }

        iodata = Message.encode(original)
        binary = IO.iodata_to_binary(iodata)

        assert {:ok, decoded, <<>>} = Message.decode(binary)
        assert decoded.header.rcode == rcode
      end
    end
  end

  describe "edge cases" do
    test "round-trips message with maximum ID value" do
      original = %Message{
        header: %Header{id: 65535}
      }

      iodata = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert decoded.header.id == 65535
    end

    test "round-trips message with zero TTL" do
      original = %Message{
        header: %Header{id: 1, qr: true},
        answers: [
          %Resource{
            name: "test.local",
            type: :a,
            class: :in,
            ttl: 0,
            rdata: {127, 0, 0, 1}
          }
        ]
      }

      iodata = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert hd(decoded.answers).ttl == 0
    end

    test "round-trips message with maximum TTL value" do
      original = %Message{
        header: %Header{id: 1, qr: true},
        answers: [
          %Resource{
            name: "test.local",
            type: :a,
            class: :in,
            ttl: 2_147_483_647,
            rdata: {127, 0, 0, 1}
          }
        ]
      }

      iodata = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert hd(decoded.answers).ttl == 2_147_483_647
    end

    test "round-trips message with many records in each section" do
      questions = for i <- 1..10, do: %Question{name: "q#{i}.local", type: :a, class: :in}

      answers =
        for i <- 1..20,
            do: %Resource{
              name: "a#{i}.local",
              type: :a,
              class: :in,
              ttl: 120,
              rdata: {i, i, i, i}
            }

      authorities =
        for i <- 1..5,
            do: %Resource{
              name: "ns#{i}.local",
              type: :ns,
              class: :in,
              ttl: 3600,
              rdata: "ns.local"
            }

      additionals =
        for i <- 1..15,
            do: %Resource{
              name: "x#{i}.local",
              type: :a,
              class: :in,
              ttl: 60,
              rdata: {i, i, i, i}
            }

      original = %Message{
        header: %Header{id: 9999, qr: true},
        questions: questions,
        answers: answers,
        authorities: authorities,
        additionals: additionals
      }

      iodata = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert decoded.header.qdcount == 10
      assert decoded.header.ancount == 20
      assert decoded.header.nscount == 5
      assert decoded.header.arcount == 15
      assert length(decoded.questions) == 10
      assert length(decoded.answers) == 20
      assert length(decoded.authorities) == 5
      assert length(decoded.additionals) == 15
    end

    test "round-trips message with empty TXT record" do
      original = %Message{
        header: %Header{id: 1, qr: true},
        answers: [
          %Resource{
            name: "empty.local",
            type: :txt,
            class: :in,
            ttl: 120,
            rdata: [""]
          }
        ]
      }

      iodata = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert hd(decoded.answers).rdata == [""]
    end

    test "round-trips message with long domain names" do
      # DNS allows labels up to 63 chars, total name up to 255 chars
      long_label = String.duplicate("a", 63)
      long_name = "#{long_label}.#{long_label}.#{long_label}.com"

      original = %Message{
        header: %Header{id: 1},
        questions: [%Question{name: long_name, type: :a, class: :in}]
      }

      iodata = Message.encode(original)
      binary = IO.iodata_to_binary(iodata)

      assert {:ok, decoded, <<>>} = Message.decode(binary)
      assert hd(decoded.questions).name == long_name
    end
  end
end
