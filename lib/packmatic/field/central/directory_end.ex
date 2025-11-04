defmodule Packmatic.Field.Central.DirectoryEnd do
  @moduledoc """
  Represents the End of Central Directory record.

  Within this implementation, the Zip64 standard always adopted, so the Zip64 End of Central
  Directory Record, and the Zip64 End of Central Directory Record Locator, are also emitted.

  ## Structure

  ### Zip64 End of Central Directory Record

  Size     | Content
  -------- | -
  4 bytes  | Signature
  8 bytes  | Size of Record (excluding leading 12 bytes)
  2 bytes  | Version made by
  2 bytes  | Version needed to extract
  4 bytes  | Number of this disk
  4 bytes  | Number of the disk with the start of the Central Directory
  8 bytes  | Total number of entries in the Central Directory on this disk
  8 bytes  | Total number of entries in the Central Directory
  8 bytes  | Size of the Central Directory
  8 bytes  | Offset of start of Central Directory with respect to the starting disk number
  Variable | Zip64 extensible data sector (variable, but empty in this implementation)

  ### Zip64 End of Central Directory Locator

  Size     | Content
  -------- | -
  4 bytes  | Signature
  4 bytes  | Number of the disk with the start of the Zip64 End of Central Directory
  8 bytes  | Relative offset of the Zip64 End of Central Directory record
  4 bytes  | Total number of disks

  ### End of Central Directory Record

  Size     | Content
  -------- | -
  4 bytes  | Signature
  2 bytes  | Number of this disk
  2 bytes  | Number of the disk with the start of the Central Directory
  2 bytes  | Total number of entries in the Central Directory on this disk
  2 bytes  | Total number of entries in the Central Directory
  4 bytes  | Size of the Central Directory
  4 bytes  | Offset of start of Central Directory with respect to the starting disk number
  2 bytes  | File comment length
  Variable | File comment (64KB max.)

  #### Notes

  1.  File comments are not emitted by Packmatic.
  """

  @type t :: %__MODULE__{
          entries_count: non_neg_integer(),
          entries_size: non_neg_integer(),
          entries_offset: non_neg_integer()
        }

  @enforce_keys ~w(entries_count entries_size entries_offset)a
  defstruct entries_count: 0, entries_size: 0, entries_offset: 0
end

defimpl Packmatic.Field, for: Packmatic.Field.Central.DirectoryEnd do
  import Packmatic.Field.Helpers

  def encode(target) do
    [
      encode_zip64_record(target),
      encode_zip64_record_locator(target),
      encode_zip32_record(target)
    ]
  end

  defp encode_zip64_record(%@for{} = target) do
    [
      <<0x50, 0x4B, 0x06, 0x06>>,
      encode_64(44),
      encode_16(45),
      encode_16(45),
      encode_32(0),
      encode_32(0),
      encode_64(target.entries_count),
      encode_64(target.entries_count),
      encode_64(target.entries_size),
      encode_64(target.entries_offset)
    ]
  end

  defp encode_zip64_record_locator(%@for{} = target) do
    [
      <<0x50, 0x4B, 0x06, 0x07>>,
      encode_32(0),
      encode_64(target.entries_offset + target.entries_size),
      encode_32(1)
    ]
  end

  defp encode_zip32_record(%@for{} = target) do
    [
      <<0x50, 0x4B, 0x05, 0x06>>,
      encode_16(0),
      encode_16(0),
      encode_16(target.entries_count),
      encode_16(target.entries_count),
      encode_32(target.entries_size),
      encode_32(target.entries_offset),
      encode_16(0)
    ]
  end
end
