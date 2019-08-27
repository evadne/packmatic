defprotocol Packmatic.Validator.Target do
  @moduledoc false
  @spec validate(t(), atom()) :: :ok | {:error, term()}
  def validate(target, key)
end
