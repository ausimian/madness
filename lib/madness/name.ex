defmodule Madness.Name do
  @moduledoc false

  @doc """
  Encodes a DNS name with optional compression using a suffix map.

  Parameters:
  - name: The domain name to encode
  - suffix_map: Map of suffix -> offset for compression
  - base_offset: The absolute offset where this encoding will be placed in the final message

  Returns {encoded_binary, updated_suffix_map}.
  """
  def encode(name, suffix_map \\ %{}, base_offset \\ 0) do
    labels = if name == "", do: [], else: String.split(name, ".")
    encode_labels(labels, suffix_map, <<>>, base_offset)
  end

  @doc """
  Decodes a DNS name from binary format, handling compression pointers.

  Parameters:
  - data: The binary data starting at the name to decode
  - original_message: The full DNS message (needed to follow compression pointers)

  Returns: {:ok, name, rest} or {:error, reason}
  """
  def decode(data, original_message \\ nil) do
    original_message = original_message || data
    decode_labels(data, original_message, [], MapSet.new())
  end

  # Terminating null byte - end of name
  defp decode_labels(<<0, rest::binary>>, _original, labels, _visited) do
    name = Enum.join(Enum.reverse(labels), ".")
    {:ok, name, rest}
  end

  # Compression pointer (top 2 bits are 11)
  defp decode_labels(<<0b11::2, offset::14, rest::binary>>, original, labels, visited) do
    # Check for circular reference
    if MapSet.member?(visited, offset) do
      {:error, "circular compression pointer detected at offset #{offset}"}
    else
      updated_visited = MapSet.put(visited, offset)

      # Decode the name at the pointer location
      pointer_data = binary_part(original, offset, byte_size(original) - offset)

      case decode_labels(pointer_data, original, [], updated_visited) do
        {:ok, pointed_name, _rest} ->
          # Combine current labels with the pointed name
          full_name =
            if labels == [] do
              pointed_name
            else
              Enum.join(Enum.reverse(labels), ".") <> "." <> pointed_name
            end

          {:ok, full_name, rest}

        error ->
          error
      end
    end
  end

  # Regular label (length byte followed by data)
  defp decode_labels(<<length::8, rest::binary>>, original, labels, visited)
       when length > 0 and length <= 63 do
    if byte_size(rest) < length do
      {:error, "insufficient data for label of length #{length}"}
    else
      <<label_data::binary-size(length), remaining::binary>> = rest
      decode_labels(remaining, original, [label_data | labels], visited)
    end
  end

  # Invalid length byte
  defp decode_labels(<<length::8, _rest::binary>>, _original, _labels, _visited) do
    {:error, "invalid label length: #{length}"}
  end

  # Insufficient data
  defp decode_labels(<<>>, _original, _labels, _visited) do
    {:error, "unexpected end of data while decoding name"}
  end

  defp encode_labels([], suffix_map, acc, _base_offset) do
    {acc <> <<0>>, suffix_map}
  end

  defp encode_labels([label | rest], suffix_map, acc, base_offset) do
    suffix = Enum.join([label | rest], ".")

    case Map.get(suffix_map, suffix) do
      nil ->
        # Record this suffix's offset for future compression (absolute offset in message)
        current_offset = base_offset + byte_size(acc)
        updated_suffix_map = Map.put(suffix_map, suffix, current_offset)

        # Encode the label
        label_length = byte_size(label)
        new_acc = acc <> <<label_length>> <> label
        encode_labels(rest, updated_suffix_map, new_acc, base_offset)

      offset ->
        # Use compression pointer
        new_acc = acc <> <<0b11::2, offset::14>>
        {new_acc, suffix_map}
    end
  end
end
