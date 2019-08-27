defmodule Packmatic.Validator do
  @moduledoc false
  @spec validate(struct()) :: :ok | {:error, keyword()}
  @spec validate_each([struct()]) :: :ok | {:error, [{struct(), keyword()}]}
  @spec errors(struct()) :: keyword()

  def validate(target) do
    case errors(target) do
      [] -> :ok
      list -> {:error, list}
    end
  end

  def validate_each(targets) do
    target_fun = fn target ->
      case errors(target) do
        [] -> []
        list -> [{target, list}]
      end
    end

    case Enum.flat_map(targets, target_fun) do
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
