defmodule Packmatic.Source.URL do
  @moduledoc """
  Represents content which can be acquired by downloading from a remote server via HTTP(S) in
  chunks. Each chunk is then pulled away by the Encoder, which is iterated by the Stream.
  """

  alias Packmatic.Source
  @behaviour Source

  @type init_arg :: String.t()
  @type init_result :: {:ok, t}
  @spec init(init_arg) :: init_result

  @type t :: %__MODULE__{url: String.t(), stream_id: term()}
  @enforce_keys ~w(url stream_id)a
  defstruct url: nil, stream_id: nil

  @impl Source
  def validate(url) when is_binary(url) and url != "", do: :ok
  def validate(_), do: {:error, :invalid}

  @impl Source
  def init(url) do
    with %{host: host} <- URI.parse(url),
         options = httpotion_options(host),
         %HTTPotion.AsyncResponse{id: stream_id} <- HTTPotion.get(url, options) do
      {:ok, %__MODULE__{url: url, stream_id: stream_id}}
    else
      {:error, reason} -> {:error, reason}
      %HTTPotion.ErrorResponse{message: message} -> {:error, message}
    end
  end

  @impl Source
  def read(%__MODULE__{stream_id: stream_id}) do
    with data when is_binary(data) <- read_receive_next(stream_id) do
      data
    else
      value ->
        _ = :ibrowse.stream_close(stream_id)
        value
    end
  end

  defp read_receive_next(stream_id) do
    with :ok <- :ibrowse.stream_next(stream_id) do
      receive do
        %HTTPotion.AsyncHeaders{status_code: 200} -> <<>>
        %HTTPotion.AsyncHeaders{status_code: status} -> {:error, {:unsupported_status, status}}
        %HTTPotion.AsyncChunk{chunk: chunk, id: ^stream_id} -> chunk
        %HTTPotion.AsyncEnd{id: ^stream_id} -> :eof
        %HTTPotion.AsyncTimeout{id: ^stream_id} -> {:error, :timeout}
      end
    end
  end

  @otp_app Mix.Project.config()[:app]
  @default_whole_file_timeout 1000 * 60 * 30
  @default_max_sessions 100

  defp httpotion_options(host) do
    [
      timeout: get_whole_file_timeout(),
      follow_redirects: true,
      stream_to: {self(), :once},
      ibrowse: [
        max_sessions: get_max_sessions(),
        ssl_options: [
          server_name_indication: to_charlist(host)
        ]
      ]
    ]
  end

  defp get_whole_file_timeout do
    Application.get_env(@otp_app, __MODULE__, [])
    |> Keyword.get(:whole_file_timeout, @default_whole_file_timeout)
  end

  defp get_max_sessions do
    Application.get_env(@otp_app, __MODULE__, [])
    |> Keyword.get(:max_sessions, @default_max_sessions)
  end
end
