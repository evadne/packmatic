defmodule Packmatic.Validator do
  @moduledoc false
  @spec validate(struct()) :: :ok | {:error, keyword()}
  @spec errors(struct()) :: keyword()

  def validate(target) do
    case errors(target) do
      [] -> :ok
      list -> {:error, list}
    end
  end

  def errors(target) do
    keys = Map.keys(target) -- [:__struct__]

    Enum.reduce(keys, [], fn key, errors ->
      case __MODULE__.Target.validate(target, key) do
        :ok -> errors
        {:error, reason} -> [{key, reason} | errors]
      end
    end)
  end
end
