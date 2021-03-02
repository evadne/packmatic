defmodule Packmatic.Source.Random do
  @moduledoc """
  Represents randomly generated content, which is used mostly for testing, when you want to have a
  particular entry generated to a specific length.
  """

  import :erlang, only: [iolist_size: 1]
  alias Packmatic.Source
  @behaviour Source

  @type init_arg :: non_neg_integer()
  @type init_result :: {:ok, t}
  @spec init(init_arg) :: init_result

  @type t :: %__MODULE__{
          bytes_remaining: non_neg_integer(),
          chunk_size: non_neg_integer(),
          template: binary()
        }

  @chunk_size 1_048_576 * 10
  @enforce_keys ~w(bytes_remaining template)a
  defstruct bytes_remaining: 0, chunk_size: @chunk_size, template: nil

  @impl Source
  def validate(bytes) when is_number(bytes) and bytes > 0, do: :ok
  def validate(_), do: {:error, :invalid}

  @impl Source
  def init(bytes) when is_number(bytes) and bytes > 0 do
    template = :crypto.strong_rand_bytes(@chunk_size)
    state = %__MODULE__{bytes_remaining: bytes, template: template}
    {:ok, state}
  end

  @impl Source
  def read(state) do
    bytes = min(state.bytes_remaining, state.chunk_size)
    result = :binary.part(state.template, 0, bytes)
    state = %{state | bytes_remaining: state.bytes_remaining - bytes}

    cond do
      iolist_size(result) > 0 -> {result, state}
      true -> :eof
    end
  end
end
