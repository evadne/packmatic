defmodule Packmatic.Source.File do
  @moduledoc """
  Represents content on disk, for example from a static file. Also useful for content generated
  ahead of time.
  """

  alias Packmatic.Source
  @behaviour Source

  @type init_arg :: String.t()
  @type init_result :: {:ok, t}
  @spec init(init_arg) :: init_result

  @type t :: %__MODULE__{path: String.t(), device: File.io_device()}
  @enforce_keys ~w(path device)a
  defstruct path: nil, device: nil

  @impl Source
  def init(path) do
    with {:ok, device} <- File.open(path, [:binary, :read]) do
      {:ok, %__MODULE__{path: path, device: device}}
    end
  end

  @impl Source
  def read(source) do
    IO.binread(source.device, get_chunk_size())
  end

  @impl Source
  def close(source) do
    File.close(source.device)
  end

  @otp_app Mix.Project.config()[:app]
  @default_chunk_size 4096

  defp get_chunk_size do
    Application.get_env(@otp_app, __MODULE__, [])
    |> Keyword.get(:chunk_size, @default_chunk_size)
  end
end
