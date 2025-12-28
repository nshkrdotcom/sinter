defmodule Sinter.JSON do
  @moduledoc """
  JSON encode/decode helpers with Sinter validation and transforms.
  """

  alias Sinter.{Error, Schema, Transform, Validator}

  @type encode_opts :: [
          aliases: map(),
          formats: map(),
          drop_nil?: boolean()
        ]

  @type decode_opts :: Validator.validation_opts()

  @doc """
  Encodes data as JSON after applying the transform pipeline.
  """
  @spec encode(term(), encode_opts()) :: {:ok, String.t()} | {:error, term()}
  def encode(data, opts \\ []) do
    transform_opts = Keyword.take(opts, [:aliases, :formats, :drop_nil?])

    data
    |> Transform.transform(transform_opts)
    |> Jason.encode()
  end

  @doc """
  Encodes data as JSON and raises on failure.
  """
  @spec encode!(term(), encode_opts()) :: String.t()
  def encode!(data, opts \\ []) do
    transform_opts = Keyword.take(opts, [:aliases, :formats, :drop_nil?])

    data
    |> Transform.transform(transform_opts)
    |> Jason.encode!()
  end

  @doc """
  Decodes JSON and validates against a schema.
  """
  @spec decode(String.t(), Schema.t(), decode_opts()) ::
          {:ok, map()} | {:error, [Error.t()]}
  def decode(json, %Schema{} = schema, opts \\ []) do
    with {:ok, data} <- Jason.decode(json),
         {:ok, validated} <- Validator.validate(schema, data, opts) do
      {:ok, validated}
    else
      {:error, %Jason.DecodeError{} = error} ->
        {:error, [Error.new([], :json_decode, Exception.message(error))]}

      {:error, errors} ->
        {:error, errors}
    end
  end

  @doc """
  Decodes JSON and validates against a schema, raising on failure.
  """
  @spec decode!(String.t(), Schema.t(), decode_opts()) :: map()
  def decode!(json, %Schema{} = schema, opts \\ []) do
    case decode(json, schema, opts) do
      {:ok, validated} -> validated
      {:error, errors} -> raise Sinter.ValidationError, errors: errors
    end
  end
end
