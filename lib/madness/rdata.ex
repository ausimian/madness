defmodule Madness.Rdata do
  @moduledoc """
  Encoding helpers for DNS RDATA fields.
  """
  alias Madness.Type

  import Bitwise, only: [&&&: 2, |||: 2, <<<: 2]

  @spec encode(Type.t(), any(), map(), non_neg_integer()) :: {binary(), map()}
  def encode(:a, {a1, a2, a3, a4}, suffix_map, _offset) do
    {<<a1, a2, a3, a4>>, suffix_map}
  end

  def encode(:aaaa, {a, b, c, d, e, f, g, h}, map, _offset) do
    {<<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>, map}
  end

  def encode(:cname, cname, suffix_map, offset) do
    Madness.Name.encode(cname, suffix_map, offset)
  end

  def encode(:ptr, ptr, suffix_map, offset) do
    Madness.Name.encode(ptr, suffix_map, offset)
  end

  def encode(:srv, %{priority: prio, weight: weight, port: port, target: target}, map, offset) do
    {encoded_target, updated_suffix_map} = Madness.Name.encode(target, map, offset + 6)
    {<<prio::16, weight::16, port::16, encoded_target::binary>>, updated_suffix_map}
  end

  def encode(:txt, txt_list, suffix_map, _offset) when is_list(txt_list) do
    txt_data = for t <- txt_list, do: <<byte_size(t)::8, t::binary>>
    {IO.iodata_to_binary(txt_data), suffix_map}
  end

  def encode(:nsec, %{name: name, types: types}, suffix_map, offset) do
    {encoded_name, updated_suffix_map} = Madness.Name.encode(name, suffix_map, offset)

    # Build bitmap
    window_blocks =
      types
      |> Enum.map(&Type.to_int/1)
      |> Enum.sort()
      |> Enum.chunk_by(&div(&1, 256))
      |> Enum.with_index()
      |> Enum.map(fn {type_ints, block} ->
        bitmap_size = Enum.max(type_ints) - block * 256
        byte_len = div(bitmap_size, 8) + 1
        bitmap = :binary.copy(<<0>>, byte_len)

        bitmap =
          Enum.reduce(type_ints, bitmap, fn type_int, bmp ->
            idx = type_int - block * 256
            byte_index = div(idx, 8)
            bit_index = idx &&& 7
            <<pre::binary-size(byte_index), byte, post::binary>> = bmp
            byte = byte ||| 1 <<< (7 - bit_index)
            <<pre::binary, byte, post::binary>>
          end)

        <<block::8, byte_size(bitmap)::8, bitmap::binary>>
      end)

    {IO.iodata_to_binary([encoded_name | window_blocks]), updated_suffix_map}
  end

  @spec decode(Type.t(), binary(), binary()) :: any()
  def decode(:a, <<a1, a2, a3, a4>>, _original_message) do
    {a1, a2, a3, a4}
  end

  def decode(:aaaa, <<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>, _original_message) do
    {a, b, c, d, e, f, g, h}
  end

  def decode(:cname, cname_data, original_message) do
    {:ok, name, _rest} = Madness.Name.decode(cname_data, original_message)
    name
  end

  def decode(:ptr, ptr_data, original_message) do
    {:ok, name, _rest} = Madness.Name.decode(ptr_data, original_message)
    name
  end

  def decode(:srv, <<prio::16, weight::16, port::16, target_data::binary>>, original_message) do
    {:ok, target, _rest} = Madness.Name.decode(target_data, original_message)
    %{priority: prio, weight: weight, port: port, target: target}
  end

  def decode(:txt, txt_data, _original_message) do
    decode_txt_strings(txt_data, [])
  end

  def decode(:nsec, nsec_data, original_message) do
    {:ok, name, rest} = Madness.Name.decode(nsec_data, original_message)
    %{name: name, types: decode_window_blocks(rest, [])}
  end

  def decode(_type, rdata, _original_message) do
    rdata
  end

  defp decode_txt_strings(<<>>, acc), do: Enum.reverse(acc)

  defp decode_txt_strings(<<length::8, rest::binary>>, acc) when byte_size(rest) >= length do
    <<txt_string::binary-size(length), remaining::binary>> = rest
    decode_txt_strings(remaining, [txt_string | acc])
  end

  defp decode_txt_strings(data, acc) when is_binary(data) do
    # If data doesn't match expected TXT format, return it as a single string
    Enum.reverse([data | acc])
  end

  defp decode_window_blocks(<<>>, acc), do: Enum.reverse(acc)

  defp decode_window_blocks(<<block::8, len::8, bitmap::binary-size(len), rest::binary>>, acc) do
    decode_window_blocks(rest, decode_bitmap(bitmap, block, 0, acc))
  end

  defp decode_bitmap(<<>>, _block, _idx, acc), do: acc

  defp decode_bitmap(<<byte, rest::binary>>, block, idx, acc) do
    new_acc =
      Enum.reduce(0..7, acc, fn bit, acc_inner ->
        if (byte &&& 1 <<< (7 - bit)) != 0 do
          i = block * 256 + idx * 8 + bit
          [Type.from_int(i) | acc_inner]
        else
          acc_inner
        end
      end)

    decode_bitmap(rest, block, idx + 1, new_acc)
  end
end
