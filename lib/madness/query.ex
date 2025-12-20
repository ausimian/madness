defmodule Madness.Query do
  use TypedStruct

  alias Madness.Question

  typedstruct do
    field :questions, [Question.t()], default: []
  end

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec add_question(t(), Question.t()) :: t()
  def add_question(%__MODULE__{} = query, %Question{} = question) do
    %{query | questions: [question | query.questions]}
  end

  @spec add_question(t(), map()) :: t()
  def add_question(%__MODULE__{} = query, attrs) when is_map(attrs) do
    add_question(query, Question.new(attrs))
  end

  def all_unicast?(%__MODULE__{questions: questions}) do
    Enum.all?(questions, &match?(%Question{unicast_response: true}, &1))
  end
end
