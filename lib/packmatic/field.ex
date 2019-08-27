defprotocol Packmatic.Field do
  @moduledoc false
  @spec encode(t()) :: iodata() | no_return()
  def encode(field)
end
