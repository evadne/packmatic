defmodule PackmaticTest.InvocationTarget do
  @moduledoc """
  The Invocation Target can be used to generate a File Source dynamically, useful when testing.
  """

  def perform do
    {:ok, path} = Briefly.create()
    content = DateTime.to_iso8601(DateTime.utc_now())
    :ok = File.write(path, content)
    {:ok, {:file, path}}
  end
end
