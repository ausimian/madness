defmodule Madness.Rdata do
  @moduledoc """
  Encoding helpers for DNS RDATA fields.
  """

  @spec encode(Madness.Type.t(), any(), map(), non_neg_integer()) :: {binary(), map()}
  def encode(:a, <<a1, a2, a3, a4>>, suffix_map, _offset) do
    {<<a1, a2, a3, a4>>, suffix_map}
  end

  def encode(:aaaa, <<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>, map, _offset) do
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

  def encode(_type, rdata, suffix_map, _offset) do
    {rdata, suffix_map}
  end

  @spec decode(Madness.Type.t(), binary(), binary()) :: any()
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
end
