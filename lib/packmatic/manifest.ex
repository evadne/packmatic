defmodule Packmatic.Manifest do
  @moduledoc """
  Represents the customer’s request for a particular compressed file, which is composed of various
  Source Entries.
  """

  @type entry :: __MODULE__.Entry.t()
  @type t :: %__MODULE__{entries: nonempty_list(entry)}
  @enforce_keys ~w(entries)a
  defstruct entries: []

  @spec create([entry]) :: t()
  @spec prepend(t(), keyword()) :: t()

  def create(entries \\ []) do
    %__MODULE__{entries: entries}
  end

  def prepend(model, keyword) do
    entry = struct(__MODULE__.Entry, keyword)
    %{model | entries: [entry | model.entries]}
  end
end

defimpl Packmatic.Validator.Target, for: Packmatic.Manifest do
  def validate(%{entries: entries}, :entries) do
    Packmatic.Validator.validate_each(entries)
  end
end
