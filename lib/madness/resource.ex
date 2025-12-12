defmodule Madness.Resource do
  use TypedStruct
  import Bitwise

  typedstruct enforce: true do
    field(:name, String.t())
    field(:type, Madness.Type.t())
    field(:class, Madness.Class.t(), default: :in)
    field(:cache_flush, boolean(), default: false)
    field(:ttl, non_neg_integer(), default: 0)
    field(:rdlength, non_neg_integer(), default: 0)
    field(:rdata, binary(), default: <<>>)
  end

  def encode(%__MODULE__{} = resource, suffix_map \\ %{}, base_offset \\ 0) do
    {encoded_name, updated_suffix_map} =
      Madness.Name.encode(resource.name, suffix_map, base_offset)

    type_value = Madness.Type.to_int(resource.type)
    class_value = Madness.Class.to_int(resource.class)
    cache_flush_bit = if resource.cache_flush, do: 0x8000, else: 0x0000
    rdlength = byte_size(resource.rdata)

    encoded_resource =
      <<
        encoded_name::binary,
        type_value::16,
        class_value ||| cache_flush_bit::16,
        resource.ttl::32,
        rdlength::16,
        resource.rdata::binary
      >>

    {encoded_resource, updated_suffix_map}
  end

  def decode(data, original_message \\ nil) do
    with {:ok, name, rest} <- Madness.Name.decode(data, original_message) do
      case rest do
        <<type::16, class::16, ttl::32, rdlength::16, rdata::binary-size(rdlength), rest2::binary>> ->
          cache_flush = (class &&& 0x8000) != 0
          actual_class = class &&& 0x7FFF

          resource = %__MODULE__{
            name: name,
            type: Madness.Type.from_int(type),
            class: Madness.Class.from_int(actual_class),
            cache_flush: cache_flush,
            ttl: ttl,
            rdlength: rdlength,
            rdata: rdata
          }

          {:ok, resource, rest2}

        _ ->
          {:error, "insufficient data to decode resource record"}
      end
    end
  end
end
