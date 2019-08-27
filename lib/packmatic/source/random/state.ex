defmodule Packmatic.Source.Random.State do
  @moduledoc false
  @type t :: %__MODULE__{bytes_remaining: non_neg_integer(), chunk_size: non_neg_integer()}
  @enforce_keys ~w(bytes_remaining)a
  defstruct bytes_remaining: 0, chunk_size: 1_048_576 * 10
end
