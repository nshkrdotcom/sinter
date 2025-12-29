defmodule Sinter.Transform do
  @moduledoc """
  Lightweight serialization helpers for request payloads.

  - Drops `Sinter.NotGiven`/`Sinter.NotGiven.omit/0` sentinels
  - Applies key aliases and simple formatters (e.g., ISO8601 timestamps)
  - Recurses through maps, structs, and lists while stringifying keys
  """

  alias Sinter.NotGiven

  alias Sinter.Schema

  @type format :: :iso8601 | (term() -> term())
  @type opts :: [
          aliases: map(),
          formats: map(),
          drop_nil?: boolean(),
          schema: Schema.t() | nil,
          use_aliases: boolean()
        ]

  @doc """
  Transform a payload into a JSON-friendly map.

  - Keys are stringified and alias mappings are applied
  - `NotGiven`/`omit` sentinels are removed
  - Optional formatters can be attached per key (`:iso8601` or a unary function)

  ## Options

    * `:aliases` - Map of canonical keys to alias keys
    * `:formats` - Map of keys to formatters
    * `:drop_nil?` - Whether to drop nil values (default: false)
    * `:schema` - A Sinter.Schema to extract aliases from
    * `:use_aliases` - Whether to use aliases from schema (default: false)
  """
  @spec transform(term(), opts()) :: term()
  def transform(data, opts \\ [])

  def transform(nil, _opts), do: nil

  def transform(list, opts) when is_list(list) do
    Enum.map(list, &transform(&1, opts))
  end

  def transform(%_{} = struct, opts) do
    struct
    |> Map.from_struct()
    |> Map.delete(:__struct__)
    |> transform_map(opts)
  end

  def transform(map, opts) when is_map(map) do
    transform_map(map, opts)
  end

  def transform(other, _opts), do: other

  defp transform_map(map, opts) do
    # Build aliases map - either from explicit option or from schema
    aliases = build_aliases(opts)
    formats = Keyword.get(opts, :formats, %{})
    drop_nil? = Keyword.get(opts, :drop_nil?, false)

    Enum.reduce(map, %{}, fn {key, value}, acc ->
      cond do
        NotGiven.not_given?(value) or NotGiven.omit?(value) ->
          acc

        drop_nil? and is_nil(value) ->
          acc

        true ->
          encoded_key = encode_key(key, aliases)
          formatted_value = transform_value(value, key, formats, opts)
          Map.put(acc, encoded_key, formatted_value)
      end
    end)
  end

  defp build_aliases(opts) do
    explicit_aliases = Keyword.get(opts, :aliases, %{})
    schema = Keyword.get(opts, :schema)
    use_aliases = Keyword.get(opts, :use_aliases, false)

    schema_aliases =
      if schema && use_aliases do
        Schema.field_aliases(schema)
      else
        %{}
      end

    # Merge explicit aliases on top of schema aliases
    Map.merge(schema_aliases, explicit_aliases)
  end

  defp transform_value(value, key, formats, opts) do
    formatter = format_for(key, formats)

    cond do
      formatter ->
        apply_format(formatter, value)

      is_map(value) or match?(%_{}, value) ->
        transform(value, opts)

      is_list(value) ->
        Enum.map(value, &transform(&1, opts))

      true ->
        value
    end
  end

  defp encode_key(key, aliases) do
    normalized = normalize_key(key)

    case Map.get(aliases, key) || Map.get(aliases, normalized) do
      nil -> normalized
      alias_key -> normalize_key(alias_key)
    end
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(other), do: to_string(other)

  defp format_for(key, formats) do
    Map.get(formats, key) || Map.get(formats, normalize_key(key))
  end

  defp apply_format(:iso8601, %DateTime{} = value), do: DateTime.to_iso8601(value)
  defp apply_format(:iso8601, %NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp apply_format(:iso8601, %Date{} = value), do: Date.to_iso8601(value)
  defp apply_format(fun, value) when is_function(fun, 1), do: fun.(value)
  defp apply_format(_unknown, value), do: value
end
