defmodule Packmatic.Field.Shared.Unix do
  @moduledoc """
  Represents the Info-ZIP New Unix Extra Field, which is emitted in the Central File
  Headers. The field is emitted only when both the UID and GID are set via the
  Entry Attributes, otherwise it will not be emitted. The size is 4 bytes for both the
  UID and GID, same as what Erlang’s zip module emits.

  ## Structure

  ### Info-ZIP New Unix Extra Field

  Size     | Content
  -------- | -
  2 bytes  | Signature
  2 bytes  | Size of Rest of Field (Bytes)
  1 byte   | Version (1)
  1 byte   | Size of UID
  N bytes  | UID
  1 byte   | Size of GID
  N bytes  | GID
  """

  @type t :: %__MODULE__{uid: non_neg_integer(), gid: non_neg_integer()}
  @enforce_keys ~w(uid gid)a
  defstruct uid: nil, gid: nil
end

defimpl Packmatic.Field, for: Packmatic.Field.Shared.Unix do
  import Packmatic.Field.Helpers

  def encode(%@for{uid: uid, gid: gid} = target) when uid >= 0 and gid >= 0 do
    [
      <<0x78, 0x75>>,
      encode_16(11),
      encode_8(1),
      encode_8(4),
      encode_32(target.uid),
      encode_8(4),
      encode_32(target.gid)
    ]
  end
end
