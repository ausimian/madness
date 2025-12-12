defmodule Madness.Header do
  @moduledoc """
  Functions for encoding and decoding mDNS record headers.
  """

  use TypedStruct

  import Bitwise, only: [&&&: 2, |||: 2, >>>: 2, <<<: 2]

  typedstruct enforce: true do
    field(:id, non_neg_integer())
    field(:qr, boolean(), default: false)
    field(:opcode, non_neg_integer(), default: 0)
    field(:aa, boolean(), default: false)
    field(:tc, boolean(), default: false)
    field(:rd, boolean(), default: true)
    field(:ra, boolean(), default: false)
    field(:z, non_neg_integer(), default: 0)
    field(:rcode, non_neg_integer(), default: 0)
    field(:qdcount, non_neg_integer(), default: 0)
    field(:ancount, non_neg_integer(), default: 0)
    field(:nscount, non_neg_integer(), default: 0)
    field(:arcount, non_neg_integer(), default: 0)
  end

  def decode(<<
        id::16,
        flags::16,
        qdcount::16,
        ancount::16,
        nscount::16,
        arcount::16
      >>) do
    %Madness.Header{
      id: id,
      qr: (flags &&& 0x8000) != 0,
      opcode: (flags &&& 0x7800) >>> 11,
      aa: (flags &&& 0x0400) != 0,
      tc: (flags &&& 0x0200) != 0,
      rd: (flags &&& 0x0100) != 0,
      ra: (flags &&& 0x0080) != 0,
      z: (flags &&& 0x0070) >>> 4,
      rcode: flags &&& 0x000F,
      qdcount: qdcount,
      ancount: ancount,
      nscount: nscount,
      arcount: arcount
    }
  end

  def encode(%Madness.Header{} = header) do
    flags =
      if(header.qr, do: 0x8000, else: 0) |||
        (header.opcode <<< 11 &&& 0x7800) |||
        if(header.aa, do: 0x0400, else: 0) |||
        if(header.tc, do: 0x0200, else: 0) |||
        if(header.rd, do: 0x0100, else: 0) |||
        if(header.ra, do: 0x0080, else: 0) |||
        (header.z <<< 4 &&& 0x0070) |||
        (header.rcode &&& 0x000F)

    <<
      header.id::16,
      flags::16,
      header.qdcount::16,
      header.ancount::16,
      header.nscount::16,
      header.arcount::16
    >>
  end
end
