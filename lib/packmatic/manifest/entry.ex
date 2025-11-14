defmodule Packmatic.Manifest.Entry do
  @moduledoc """
  Represents a particular file that will go into package, which is sourced by reading from a file,
  downloading from an URI, etc.

  The `source` attribute is a Source Entry (`t:Packmatic.Source.entry/0`), which will be dynamically
  resolved at runtime using `Packmatic.Source.build/1` by the Encoder, when it is time to start
  reading from it.

  The `path` attribute is the file name in the record; by default, it should be a relative path.

  The `timestamp` attribute is a UTC DataTime which will be presented in both the normal way (DOS
  timestamp) and the extended way.

  The `attributes`attribute represents specific attributes (mode, UID, GID, etc) of the record;
  the permissions of any file whose Entry does not have a specific attribute will be `0o644` (octal),
  aka `rw-r--r--` (owner read/write, others read only). For more information please see the type
  `t:Packmatic.Manifest.Entry.Attributes.entry/0`.

  The `method` attribute represents how a particular file should be compressed by the Encoder, and
  are represented as `name` or `{name, options}`, for example:

  - `:store`

  - `:deflate`

  - `{:deflate, level: :best_compression}`, where the level is of `t:zlib:zlevel/0`

  For compatibility reasons, only STORE and DEFLATE methods are supported initially; further
  compression methods such as Zstandard can be added in the future, but they must remain representable
  within the General Purpose bits within the File Headers.
  """

  @type t :: %__MODULE__{source: source, path: path, timestamp: timestamp}
  @type proplist ::
          nonempty_list(
            {:source, source}
            | {:path, path}
            | {:timestamp, timestamp}
            | {:attributes, attributes}
            | {:method, method}
          )

  @type source :: Packmatic.Source.entry()
  @type path :: Path.t()
  @type timestamp :: DateTime.t()
  @type attributes :: __MODULE__.Attributes.entry()
  @type method :: :store | :deflate

  @type error_source :: {:source, :missing | :invalid}
  @type error_path :: {:path, :missing}
  @type error_timestamp :: {:timestamp, :missing | :invalid}
  @type error :: error_source | error_path | error_timestamp

  @enforce_keys ~w(source path timestamp)a

  defstruct source: nil,
            path: nil,
            timestamp: DateTime.from_unix!(0),
            attributes: 0o644,
            method: :deflate
end

defimpl Packmatic.Validator.Target, for: Packmatic.Manifest.Entry do
  alias Packmatic.Source
  alias Packmatic.Manifest.Entry.Attributes

  def validate(%{source: nil}, :source), do: {:error, :missing}
  def validate(%{source: entry}, :source), do: Source.validate(entry)

  def validate(%{path: nil}, :path), do: {:error, :missing}
  def validate(%{path: _}, :path), do: :ok

  def validate(%{timestamp: nil}, :timestamp), do: {:error, :missing}
  def validate(%{timestamp: %{time_zone: "Etc/UTC"}}, :timestamp), do: :ok
  def validate(%{timestamp: %{time_zone: _}}, :timestamp), do: {:error, :invalid}

  def validate(%{attributes: nil}, :attributes), do: :ok
  def validate(%{attributes: entry}, :attributes), do: Attributes.validate(entry)

  def validate(%{method: :store}, :method), do: :ok
  def validate(%{method: :deflate}, :method), do: :ok
  def validate(%{method: {:deflate, proplist}}, :method) when is_list(proplist), do: :ok
  def validate(%{method: _}), do: {:error, :invalid}
end
