defmodule Packmatic.Manifest.Entry do
  @moduledoc """
  Represents a particular file that will go into package, which is sourced by reading from a file,
  downloading from an URI, etc.

  The `source` in the Manifest Entry is actually just a Source Entry which will be dynamically
  resolved at runtime when it is time for the Encoder to start reading from it.
  """

  @type source :: Packmatic.Source.entry()
  @type path :: Path.t()
  @type timestamp :: DateTime.t()
  @type t :: %__MODULE__{source: source, path: path, timestamp: timestamp}

  @type error_source :: {:source, :missing | :invalid}
  @type error_path :: {:path, :missing}
  @type error_timestamp :: {:timestamp, :missing | :invalid}
  @type error :: error_source | error_path | error_timestamp

  @enforce_keys ~w(source path timestamp)a
  defstruct source: nil, path: nil, timestamp: DateTime.from_unix!(0)
end

defimpl Packmatic.Validator.Target, for: Packmatic.Manifest.Entry do
  def validate(%{source: nil}, :source), do: {:error, :missing}
  def validate(%{source: {:file, ""}}, :source), do: {:error, :invalid}
  def validate(%{source: {:file, path}}, :source) when is_binary(path), do: :ok
  def validate(%{source: {:url, ""}}, :source), do: {:error, :invalid}
  def validate(%{source: {:url, url}}, :source) when is_binary(url), do: :ok
  def validate(%{source: {:dynamic, fun}}, :source) when is_function(fun, 0), do: :ok
  def validate(%{source: {:random, bytes}}, :source) when is_number(bytes) and bytes > 0, do: :ok
  def validate(%{source: _}, :source), do: {:error, :invalid}

  def validate(%{path: nil}, :path), do: {:error, :missing}
  def validate(%{path: _}, :path), do: :ok

  def validate(%{timestamp: nil}, :timestamp), do: {:error, :missing}
  def validate(%{timestamp: %{time_zone: "Etc/UTC"}}, :timestamp), do: :ok
  def validate(%{timestamp: %{time_zone: _}}, :timestamp), do: {:error, :invalid}
end
