defmodule Packmatic.Field.Shared.ExtendedTimestamp do
  @moduledoc """
  Represents the Extended Timestamp Extra Field, which is emitted in both Local and Central File
  Headers. The field is emitted with only the modification time, in seconds since UNIX epoch
  (1 January, 1970).

  ## Structure

  ### Shared Extended Timestamp (UTc)

  Size     | Content
  -------- | -
  2 bytes  | Signature
  2 bytes  | Size of Rest of Field (Bytes)
  1 byte   | Flags
  4 bytes  | Modification Time (Seconds since UNIX Epoch)

  #### Notes

  1.  The flag value is `1`, representing that Modification Time is set.
  """

  @type t :: %__MODULE__{timestamp: DateTime.t()}
  @enforce_keys ~w(timestamp)a
  defstruct timestamp: nil
end

defimpl Packmatic.Field, for: Packmatic.Field.Shared.ExtendedTimestamp do
  import Packmatic.Field.Helpers

  def encode(%{timestamp: %DateTime{time_zone: "Etc/UTC"}} = target) do
    [
      <<0x55, 0x54>>,
      encode_16(5),
      encode_8(1),
      encode_32(DateTime.to_unix(target.timestamp))
    ]
  end
end
