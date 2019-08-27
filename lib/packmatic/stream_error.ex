defmodule Packmatic.StreamError do
  defexception message: "unable to construct Stream due to underlying error", reason: nil
end
