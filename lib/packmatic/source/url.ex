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

  @type t :: %__MODULE__{url: String.t(), id: term()}
  @enforce_keys ~w(url id)a
  defstruct url: nil, id: nil

  @impl Source
  def init(url) do
    with %{host: host} <- URI.parse(url),
         options = httpotion_options(host),
         %HTTPotion.AsyncResponse{id: id} <- HTTPotion.get(url, options) do
      {:ok, %__MODULE__{url: url, id: id}}
    else
      {:error, reason} -> {:error, reason}
      %HTTPotion.ErrorResponse{message: message} -> {:error, message}
    end
  end

  @impl Source
  def read(%__MODULE__{id: id}) do
    with :ok <- :ibrowse.stream_next(id) do
      receive do
        %HTTPotion.AsyncHeaders{status_code: 200} -> <<>>
        %HTTPotion.AsyncHeaders{status_code: status} -> {:error, {:unsupported_status, status}}
        %HTTPotion.AsyncChunk{chunk: chunk, id: ^id} -> chunk
        %HTTPotion.AsyncEnd{id: ^id} -> :eof
        %HTTPotion.AsyncTimeout{id: ^id} -> {:error, :timeout}
      end
    else
      {:error, reason} -> {:error, reason}
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
