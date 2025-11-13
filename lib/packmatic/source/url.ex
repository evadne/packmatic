defmodule Packmatic.Source.URL do
  @moduledoc """
  Represents content which can be acquired by downloading from a remote server via HTTP(S) in
  chunks. Each chunk is then pulled away by the Encoder, which is iterated by the Stream.

  The underlying implementation is achieved via Req/Finch, which uses Mint.
  """

  alias Packmatic.Source
  alias Packmatic.Source.URL.Reader
  @behaviour Source

  @type target :: String.t() | URI.t()
  @type options :: keyword()

  @type init_arg :: target | {target, options}
  @type init_result :: {:ok, t}
  @spec init(init_arg) :: init_result

  @type t :: %__MODULE__{reader_pid: pid()}
  @enforce_keys ~w()a
  defstruct reader_pid: nil

  @impl Source
  def validate({target, _options}), do: validate(target)
  def validate(%URI{scheme: "http"}), do: :ok
  def validate(%URI{scheme: "https"}), do: :ok
  def validate(url) when is_binary(url), do: validate(URI.parse(url))
  def validate(_), do: {:error, :invalid}

  @impl Source
  def init({target, options}), do: init(target, options)
  def init(target), do: init(target, [])

  defp init(target, options) do
    with {:ok, reader_pid} <- :gen_statem.start_link(Reader, {target, options}, []),
         :ok <- :gen_statem.call(reader_pid, :connect) do
      {:ok, %__MODULE__{reader_pid: reader_pid}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Source
  def read(%__MODULE__{} = state) do
    with {:ok, buffer_pid} <- :gen_statem.call(state.reader_pid, :read),
         data when is_binary(data) <- :gen_statem.call(buffer_pid, :read) do
      data
    else
      :eof ->
        :ok = :gen_statem.stop(state.reader_pid)
        :eof

      {:error, reason} ->
        :ok = :gen_statem.stop(state.reader_pid)
        {:error, reason}
    end
  end
end
