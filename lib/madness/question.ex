defmodule Madness.Question do
  use TypedStruct
  import Bitwise

  typedstruct enforce: true do
    field(:name, String.t())
    field(:type, Madness.Type.t())
    field(:class, Madness.Class.t(), default: :in)
    field(:unicast_response, boolean(), default: false)
  end

  def new(attrs) do
    attrs
    |> Map.put_new(:class, :in)
    |> Map.put_new(:unicast_response, false)
    |> then(&struct(__MODULE__, &1))
  end

  def encode(%__MODULE__{} = query, suffix_map \\ %{}, base_offset \\ 0) do
    {encoded_name, updated_suffix_map} =
      Madness.Name.encode(query.name, suffix_map, base_offset)

    type_value = Madness.Type.to_int(query.type)
    class_value = Madness.Class.to_int(query.class)
    unicast_bit = if query.unicast_response, do: 0x8000, else: 0x0000

    encoded_query =
      <<
        encoded_name::binary,
        type_value::16,
        class_value ||| unicast_bit::16
      >>

    {encoded_query, updated_suffix_map}
  end

  def decode(data, original_message \\ nil) do
    with {:ok, name, rest} <- Madness.Name.decode(data, original_message) do
      case rest do
        <<type::16, class::16, rest2::binary>> ->
          unicast_response = (class &&& 0x8000) != 0
          actual_class = class &&& 0x7FFF

          query = %__MODULE__{
            name: name,
            type: Madness.Type.from_int(type),
            class: Madness.Class.from_int(actual_class),
            unicast_response: unicast_response
          }

          {:ok, query, rest2}

        _ ->
          {:error, "insufficient data to decode question"}
      end
    end
  end
end
