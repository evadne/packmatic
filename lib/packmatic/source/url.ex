defmodule Packmatic.Source.URL do
  @moduledoc """
  Represents content which can be acquired by downloading from a remote server via HTTP(S) in
  chunks. Each chunk is then pulled away by the Encoder, which is iterated by the Stream.

  The underlying implementation is achieved via HTTPoison and Hackney.
  """

  alias Packmatic.Source
  @behaviour Source

  @type target :: String.t() | URI.t()
  @type headers :: keyword()
  @type options :: keyword()

  @type init_arg :: target | {target, options} | {target, headers, options}
  @type init_result :: {:ok, t}
  @spec init(init_arg) :: init_result

  @type t :: %__MODULE__{url: String.t(), stream_id: term()}
  @enforce_keys ~w(url stream_id)a
  defstruct url: nil, stream_id: nil

  @otp_app Mix.Project.config()[:app]

  alias HTTPoison.{
    AsyncChunk,
    AsyncEnd,
    AsyncHeaders,
    AsyncRedirect,
    AsyncResponse,
    AsyncStatus,
    Error
  }

  @impl Source
  def validate({target, _headers, _options}), do: validate(target)
  def validate(%URI{scheme: "http"}), do: :ok
  def validate(%URI{scheme: "https"}), do: :ok
  def validate(url) when is_binary(url), do: validate(URI.parse(url))
  def validate(_), do: {:error, :invalid}

  @impl Source
  def init({target, headers, options}), do: init(target, headers, options)
  def init({target, options}), do: init(target, [], options)
  def init(target), do: init(target, [], [])

  def init(target, headers, options) do
    with url = to_string(target),
         options = build_options(options),
         {:ok, %AsyncResponse{id: stream_id}} <- HTTPoison.get(url, headers, options) do
      {:ok, %__MODULE__{url: url, stream_id: stream_id}}
    else
      {:error, %Error{reason: reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Source
  def read(%__MODULE__{stream_id: stream_id}) do
    case read_receive_next(stream_id) do
      data when is_binary(data) ->
        data

      :eof ->
        _ = :hackney.stop_async(stream_id)
        :eof

      {:error, reason} ->
        _ = :hackney.stop_async(stream_id)
        {:error, reason}
    end
  end

  defp read_receive_next(stream_id) do
    with {:ok, _} <- HTTPoison.stream_next(%AsyncResponse{id: stream_id}) do
      receive do
        %AsyncStatus{code: 200} -> <<>>
        %AsyncStatus{code: status} -> {:error, {:unsupported_status, status}}
        %AsyncChunk{id: ^stream_id, chunk: chunk} -> chunk
        %AsyncHeaders{id: ^stream_id} -> <<>>
        %AsyncEnd{id: ^stream_id} -> :eof
        %AsyncRedirect{id: ^stream_id} -> <<>>
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def build_options(inline_options) do
    default_options = [
      timeout: 1000 * 5,
      recv_timeout: 1000 * 60 * 30,
      stream_to: self(),
      async: :once,
      follow_redirect: true,
      max_redirect: 5,
      max_body_length: 1_048_576,
      hackney: [
        pool: false
      ]
    ]

    [x: default_options]
    |> Config.Reader.merge(x: Application.get_env(@otp_app, __MODULE__, []))
    |> Config.Reader.merge(x: inline_options)
    |> Keyword.get(:x)
  end
end
