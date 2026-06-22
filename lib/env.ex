defmodule Env do
  defmodule Error do
    defexception [:key, :value, :reason, :hint]

    @impl true
    def message(%__MODULE__{key: key, value: value, reason: reason, hint: hint}) do
      base =
        "Failed to parse env var #{inspect(key)} (value: #{inspect(value)}): #{Zoi.prettify_errors(reason)}"

      if hint, do: base <> "\nHint: #{hint}", else: base
    end
  end

  def parse!(schema, key, opts \\ []) do
    case parse(schema, key, opts) do
      {:ok, value} -> value
      {:error, %Error{} = err} -> raise err
    end
  end

  def parse(schema, key, opts \\ []) do
    raw = System.get_env(key)

    case Zoi.parse(schema, raw) do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        {:error, %Error{key: key, value: raw, reason: reason, hint: Keyword.get(opts, :hint)}}
    end
  end
end
