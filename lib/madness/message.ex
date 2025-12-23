defmodule Madness.Message do
  use TypedStruct

  typedstruct enforce: true do
    field(:header, Madness.Header.t())
    field(:questions, [Madness.Question.t()], default: [])
    field(:answers, [Madness.Resource.t()], default: [])
    field(:authorities, [Madness.Resource.t()], default: [])
    field(:additionals, [Madness.Resource.t()], default: [])
  end

  @spec new() :: t()
  def new, do: %__MODULE__{header: %Madness.Header{}}

  @spec encode_query([Madness.Question.t()]) :: iodata()
  def encode_query(questions) do
    encode(%{new() | questions: questions})
  end

  @doc """
  Encode a DNS message struct to iodata.

  Returns `{iodata, suffix_map}` where suffix_map contains name compression offsets.
  """
  def encode(%__MODULE__{} = message) do
    header = %{
      message.header
      | qdcount: length(message.questions),
        ancount: length(message.answers),
        nscount: length(message.authorities),
        arcount: length(message.additionals)
    }

    encoded_header = Madness.Header.encode(header)
    offset = 12

    {encoded_questions, suffix_map, offset} =
      encode_list(message.questions, %{}, offset, &Madness.Question.encode/3)

    {encoded_answers, suffix_map, offset} =
      encode_list(message.answers, suffix_map, offset, &Madness.Resource.encode/3)

    {encoded_authorities, suffix_map, offset} =
      encode_list(message.authorities, suffix_map, offset, &Madness.Resource.encode/3)

    {encoded_additionals, _suffix_map, _offset} =
      encode_list(message.additionals, suffix_map, offset, &Madness.Resource.encode/3)

    iodata = [
      encoded_header,
      encoded_questions,
      encoded_answers,
      encoded_authorities,
      encoded_additionals
    ]

    iodata
  end

  defp encode_list(items, suffix_map, offset, encode_fn) do
    Enum.reduce(items, {[], suffix_map, offset}, fn item, {acc, suffix_map, offset} ->
      {encoded, suffix_map} = encode_fn.(item, suffix_map, offset)
      {[acc, encoded], suffix_map, offset + byte_size(encoded)}
    end)
  end

  @doc """
  Decode a DNS message from binary data.

  Returns `{:ok, message, rest}` where `rest` is any remaining unparsed bytes,
  or `{:error, reason}` if decoding fails.
  """
  def decode(data) when byte_size(data) < 12 do
    {:error, "insufficient data: expected at least 12 bytes, got #{byte_size(data)}"}
  end

  def decode(<<header_data::binary-size(12), rest::binary>> = original_message) do
    header = Madness.Header.decode(header_data)

    with {:ok, questions, rest} <- decode_questions(rest, header.qdcount, original_message),
         {:ok, answers, rest} <- decode_resources(rest, header.ancount, original_message),
         {:ok, authorities, rest} <- decode_resources(rest, header.nscount, original_message),
         {:ok, additionals, rest} <- decode_resources(rest, header.arcount, original_message) do
      message = %__MODULE__{
        header: header,
        questions: questions,
        answers: answers,
        authorities: authorities,
        additionals: additionals
      }

      {:ok, message, rest}
    end
  end

  defp decode_questions(data, count, original_message) do
    decode_list(data, count, original_message, &Madness.Question.decode/2)
  end

  defp decode_resources(data, count, original_message) do
    decode_list(data, count, original_message, &Madness.Resource.decode/2)
  end

  defp decode_list(data, count, original_message, decode_fn) do
    decode_list(data, count, original_message, decode_fn, [])
  end

  defp decode_list(data, 0, _original_message, _decode_fn, acc) do
    {:ok, Enum.reverse(acc), data}
  end

  defp decode_list(data, count, original_message, decode_fn, acc) do
    with {:ok, item, rest} <- decode_fn.(data, original_message) do
      decode_list(rest, count - 1, original_message, decode_fn, [item | acc])
    end
  end
end
