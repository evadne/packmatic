defmodule Packmatic.Encoder.Field do
  @moduledoc false
  alias Packmatic.Manifest.Entry
  alias Packmatic.Encoder.EncodingState.EntryInfo
  alias Packmatic.Encoder.JournalingState
  alias Packmatic.Field.Local
  alias Packmatic.Field.Central
  import Packmatic.Field, only: [encode: 1]

  def encode_local_file_header(%Entry{} = entry) do
    encode(%Local.FileHeader{
      path: entry.path,
      timestamp: entry.timestamp
    })
  end

  def encode_local_data_descriptor(%EntryInfo{} = info) do
    encode(%Local.DataDescriptor{
      checksum: info.checksum,
      size_compressed: info.size_compressed,
      size: info.size
    })
  end

  def encode_central_file_header(%Entry{} = entry, %EntryInfo{} = info) do
    encode(%Central.FileHeader{
      offset: info.offset,
      path: entry.path,
      checksum: info.checksum,
      size_compressed: info.size_compressed,
      size: info.size,
      timestamp: entry.timestamp
    })
  end

  def encode_central_directory_end(%JournalingState{} = state) do
    encode(%Central.DirectoryEnd{
      entries_count: state.entries_emitted,
      entries_size: state.bytes_emitted,
      entries_offset: state.offset
    })
  end
end
