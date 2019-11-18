defprotocol Packmatic.Field do
  @moduledoc """
  Represents data fields used internally by `Packmatic.Encoder` to represent information which
  make up the Zip format.
  """

  @spec encode(t()) :: iodata() | no_return()

  @doc "Encodes the given structure into an IO List, or crashes if the structure is invalid."
  def encode(field)
end
