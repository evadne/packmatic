defmodule Packmatic.Source.Stream do
  @moduledoc """
  Represents content generated by enumerating a Stream, which returns IO Lists.

  Any data type that implements `Enumerable` can be used as the Initialisation Argument for this
  Source. Usually this would be a Stream that you have created elsewhere.

  In case the data type needs to be dynamically generated, you can instead use a Dynamic source,
  i.e. `Packmatic.Source.Dynamic`, and build the actual enum there.
  """

  alias Packmatic.Source
  @behaviour Source

  @type init_arg :: Enumerable.t()
  @type init_result :: {:ok, t}
  @spec init(init_arg) :: init_result

  @type t :: %__MODULE__{continuation: nil | Enumerable.continuation()}
  @enforce_keys ~w(continuation)a
  defstruct continuation: nil

  @impl Source
  def validate(init_arg) do
    case Enumerable.impl_for(init_arg) do
      nil -> {:error, :invalid}
      _ -> :ok
    end
  end

  @impl Source
  def init(enum) do
    reduce_fun = fn item, _acc -> {:suspend, {:item, item}} end
    {:suspended, nil, continuation} = Enumerable.reduce(enum, {:suspend, nil}, reduce_fun)
    {:ok, %__MODULE__{continuation: continuation}}
  end

  @impl Source
  def read(state)

  def read(%{continuation: nil}) do
    :eof
  end

  def read(%{continuation: continuation} = state) do
    case continuation.({:cont, :eof}) do
      {:suspended, {:item, item}, continuation} -> {item, %{state | continuation: continuation}}
      {:halted, {:item, item}} -> {item, %{state | continuation: nil}}
      {:halted, :eof} -> :eof
      {:done, nil} -> :eof
    end
  end
end
