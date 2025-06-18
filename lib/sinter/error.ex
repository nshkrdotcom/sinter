defmodule Sinter.Error do
  @moduledoc """
  Structured error representation for Sinter validation errors.

  This module provides a consistent way to represent validation errors
  throughout Sinter, including path information for nested data structures
  and machine-readable error codes.
  """

  @enforce_keys [:path, :code, :message]
  defstruct [:path, :code, :message, :context]

  @type t :: %__MODULE__{
          path: [atom() | String.t() | integer()],
          code: atom(),
          message: String.t(),
          context: map() | nil
        }

  @doc """
  Creates a new validation error.

  ## Parameters

    * `path` - Path to the field that caused the error
    * `code` - Machine-readable error code
    * `message` - Human-readable error message
    * `context` - Optional additional context information

  ## Examples

      iex> Sinter.Error.new([:user, :email], :format, "invalid email format")
      %Sinter.Error{
        path: [:user, :email],
        code: :format,
        message: "invalid email format",
        context: nil
      }

      iex> Sinter.Error.new(:name, :required, "field is required")
      %Sinter.Error{path: [:name], code: :required, message: "field is required"}
  """
  @spec new(
          [atom() | String.t() | integer()] | atom() | String.t(),
          atom(),
          String.t(),
          map() | nil
        ) :: t()
  def new(path, code, message, context \\ nil) do
    %__MODULE__{
      path: normalize_path(path),
      code: code,
      message: message,
      context: context
    }
  end

  @doc """
  Creates a new error with additional context information.

  ## Examples

      iex> context = %{expected: "string", actual: "integer", value: 42}
      iex> Sinter.Error.with_context([:age], :type_mismatch, "expected string", context)
      %Sinter.Error{
        path: [:age],
        code: :type_mismatch,
        message: "expected string",
        context: %{expected: "string", actual: "integer", value: 42}
      }
  """
  @spec with_context(
          [atom() | String.t() | integer()] | atom() | String.t(),
          atom(),
          String.t(),
          map()
        ) :: t()
  def with_context(path, code, message, context) when is_map(context) do
    new(path, code, message, context)
  end

  @doc """
  Formats an error into a human-readable string.

  ## Parameters

    * `error` - The error to format
    * `opts` - Formatting options

  ## Options

    * `:include_path` - Include the path in the formatted message (default: true)
    * `:path_separator` - Separator for path elements (default: ".")

  ## Examples

      iex> error = %Sinter.Error{
      ...>   path: [:user, :email],
      ...>   code: :format,
      ...>   message: "invalid email format"
      ...> }
      iex> Sinter.Error.format(error)
      "user.email: invalid email format"

      iex> Sinter.Error.format(error, include_path: false)
      "invalid email format"
  """
  @spec format(t(), keyword()) :: String.t()
  def format(%__MODULE__{} = error, opts \\ []) do
    include_path = Keyword.get(opts, :include_path, true)
    path_separator = Keyword.get(opts, :path_separator, ".")

    if include_path and not Enum.empty?(error.path) do
      path_str = format_path(error.path, path_separator)
      "#{path_str}: #{error.message}"
    else
      error.message
    end
  end

  @doc """
  Formats multiple errors into a readable string.

  ## Examples

      iex> errors = [
      ...>   Sinter.Error.new([:name], :required, "field is required"),
      ...>   Sinter.Error.new([:age], :type_mismatch, "expected integer")
      ...> ]
      iex> Sinter.Error.format_errors(errors)
      \"\"\"
      name: field is required
      age: expected integer
      \"\"\"
  """
  @spec format_errors([t()], keyword()) :: String.t()
  def format_errors(errors, opts \\ []) when is_list(errors) do
    errors
    |> Enum.map(&format(&1, opts))
    |> Enum.join("\n")
  end

  @doc """
  Groups errors by their path for easier processing.

  ## Examples

      iex> errors = [
      ...>   Sinter.Error.new([:user, :name], :required, "field is required"),
      ...>   Sinter.Error.new([:user, :name], :min_length, "too short"),
      ...>   Sinter.Error.new([:user, :email], :format, "invalid format")
      ...> ]
      iex> Sinter.Error.group_by_path(errors)
      %{
        [:user, :name] => [
          %Sinter.Error{code: :required, ...},
          %Sinter.Error{code: :min_length, ...}
        ],
        [:user, :email] => [
          %Sinter.Error{code: :format, ...}
        ]
      }
  """
  @spec group_by_path([t()]) :: %{[atom() | String.t() | integer()] => [t()]}
  def group_by_path(errors) when is_list(errors) do
    Enum.group_by(errors, & &1.path)
  end

  @doc """
  Groups errors by their error code.

  ## Examples

      iex> errors = [
      ...>   Sinter.Error.new([:name], :required, "field is required"),
      ...>   Sinter.Error.new([:email], :required, "field is required"),
      ...>   Sinter.Error.new([:age], :type_mismatch, "expected integer")
      ...> ]
      iex> Sinter.Error.group_by_code(errors)
      %{
        required: [
          %Sinter.Error{path: [:name], ...},
          %Sinter.Error{path: [:email], ...}
        ],
        type_mismatch: [
          %Sinter.Error{path: [:age], ...}
        ]
      }
  """
  @spec group_by_code([t()]) :: %{atom() => [t()]}
  def group_by_code(errors) when is_list(errors) do
    Enum.group_by(errors, & &1.code)
  end

  @doc """
  Filters errors by error code.

  ## Examples

      iex> errors = [
      ...>   Sinter.Error.new([:name], :required, "field is required"),
      ...>   Sinter.Error.new([:age], :type_mismatch, "expected integer")
      ...> ]
      iex> Sinter.Error.filter_by_code(errors, :required)
      [%Sinter.Error{path: [:name], code: :required, ...}]
  """
  @spec filter_by_code([t()], atom()) :: [t()]
  def filter_by_code(errors, code) when is_list(errors) and is_atom(code) do
    Enum.filter(errors, &(&1.code == code))
  end

  @doc """
  Filters errors by path prefix.

  ## Examples

      iex> errors = [
      ...>   Sinter.Error.new([:user, :name], :required, "field is required"),
      ...>   Sinter.Error.new([:user, :email], :format, "invalid format"),
      ...>   Sinter.Error.new([:settings, :theme], :choices, "invalid choice")
      ...> ]
      iex> Sinter.Error.filter_by_path_prefix(errors, [:user])
      [
        %Sinter.Error{path: [:user, :name], ...},
        %Sinter.Error{path: [:user, :email], ...}
      ]
  """
  @spec filter_by_path_prefix([t()], [atom() | String.t() | integer()]) :: [t()]
  def filter_by_path_prefix(errors, path_prefix) when is_list(errors) and is_list(path_prefix) do
    Enum.filter(errors, fn error ->
      path_starts_with?(error.path, path_prefix)
    end)
  end

  @doc """
  Converts an error to a map representation.

  Useful for JSON serialization or API responses.

  ## Examples

      iex> error = Sinter.Error.new([:user, :email], :format, "invalid email format")
      iex> Sinter.Error.to_map(error)
      %{
        "path" => ["user", "email"],
        "code" => "format",
        "message" => "invalid email format"
      }
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = error) do
    base = %{
      "path" => Enum.map(error.path, &to_string/1),
      "code" => to_string(error.code),
      "message" => error.message
    }

    if error.context do
      Map.put(base, "context", error.context)
    else
      base
    end
  end

  @doc """
  Converts multiple errors to map representations.

  ## Examples

      iex> errors = [
      ...>   Sinter.Error.new([:name], :required, "field is required"),
      ...>   Sinter.Error.new([:age], :type_mismatch, "expected integer")
      ...> ]
      iex> Sinter.Error.to_maps(errors)
      [
        %{"path" => ["name"], "code" => "required", "message" => "field is required"},
        %{"path" => ["age"], "code" => "type_mismatch", "message" => "expected integer"}
      ]
  """
  @spec to_maps([t()]) :: [map()]
  def to_maps(errors) when is_list(errors) do
    Enum.map(errors, &to_map/1)
  end

  @doc """
  Creates an error from a map representation.

  Useful for deserializing errors from JSON or external sources.

  ## Examples

      iex> error_map = %{
      ...>   "path" => ["user", "email"],
      ...>   "code" => "format",
      ...>   "message" => "invalid email format"
      ...> }
      iex> Sinter.Error.from_map(error_map)
      {:ok, %Sinter.Error{
        path: [:user, :email],
        code: :format,
        message: "invalid email format"
      }}
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    with {:ok, path} <- extract_path(map),
         {:ok, code} <- extract_code(map),
         {:ok, message} <- extract_message(map) do
      context = Map.get(map, "context")
      {:ok, new(path, code, message, context)}
    end
  end

  @doc """
  Gets the most specific error for a given path.

  Returns the error with the longest matching path prefix.

  ## Examples

      iex> errors = [
      ...>   Sinter.Error.new([:user], :required, "user is required"),
      ...>   Sinter.Error.new([:user, :email], :format, "invalid email format")
      ...> ]
      iex> Sinter.Error.most_specific_for_path(errors, [:user, :email])
      %Sinter.Error{path: [:user, :email], code: :format, ...}
  """
  @spec most_specific_for_path([t()], [atom() | String.t() | integer()]) :: t() | nil
  def most_specific_for_path(errors, target_path) when is_list(errors) do
    errors
    |> Enum.filter(fn error ->
      path_starts_with?(target_path, error.path)
    end)
    |> Enum.max_by(fn error -> length(error.path) end, fn -> nil end)
  end

  @doc """
  Summarizes validation errors into a report.

  ## Examples

      iex> errors = [
      ...>   Sinter.Error.new([:name], :required, "field is required"),
      ...>   Sinter.Error.new([:age], :type_mismatch, "expected integer"),
      ...>   Sinter.Error.new([:email], :format, "invalid email format")
      ...> ]
      iex> Sinter.Error.summarize(errors)
      %{
        total_errors: 3,
        error_codes: [:required, :type_mismatch, :format],
        affected_paths: [[:name], [:age], [:email]],
        by_code: %{
          required: 1,
          type_mismatch: 1,
          format: 1
        }
      }
  """
  @spec summarize([t()]) :: map()
  def summarize(errors) when is_list(errors) do
    by_code = Enum.frequencies_by(errors, & &1.code)

    %{
      total_errors: length(errors),
      error_codes: Map.keys(by_code),
      affected_paths: Enum.map(errors, & &1.path) |> Enum.uniq(),
      by_code: by_code
    }
  end

  # Private helper functions

  @spec normalize_path([atom() | String.t() | integer()] | atom() | String.t()) ::
          [atom() | String.t() | integer()]
  defp normalize_path(path) when is_list(path), do: path
  defp normalize_path(path) when is_atom(path) or is_binary(path), do: [path]

  @spec format_path([atom() | String.t() | integer()], String.t()) :: String.t()
  defp format_path(path, separator) do
    path
    |> Enum.map(&to_string/1)
    |> Enum.join(separator)
  end

  @spec path_starts_with?([term()], [term()]) :: boolean()
  defp path_starts_with?(path, prefix) do
    prefix_length = length(prefix)
    path_length = length(path)

    if prefix_length <= path_length do
      path_prefix = Enum.take(path, prefix_length)
      path_prefix == prefix
    else
      false
    end
  end

  @spec extract_path(map()) :: {:ok, [atom()]} | {:error, String.t()}
  defp extract_path(map) do
    case Map.get(map, "path") do
      path when is_list(path) ->
        converted_path =
          Enum.map(path, fn
            str when is_binary(str) -> String.to_atom(str)
            num when is_integer(num) -> num
            atom when is_atom(atom) -> atom
            other -> other
          end)

        {:ok, converted_path}

      nil ->
        {:error, "missing 'path' field"}

      _other ->
        {:error, "invalid 'path' field, expected list"}
    end
  end

  @spec extract_code(map()) :: {:ok, atom()} | {:error, String.t()}
  defp extract_code(map) do
    case Map.get(map, "code") do
      code when is_binary(code) ->
        {:ok, String.to_atom(code)}

      code when is_atom(code) ->
        {:ok, code}

      nil ->
        {:error, "missing 'code' field"}

      _other ->
        {:error, "invalid 'code' field, expected string or atom"}
    end
  end

  @spec extract_message(map()) :: {:ok, String.t()} | {:error, String.t()}
  defp extract_message(map) do
    case Map.get(map, "message") do
      message when is_binary(message) ->
        {:ok, message}

      nil ->
        {:error, "missing 'message' field"}

      _other ->
        {:error, "invalid 'message' field, expected string"}
    end
  end
end

defmodule Sinter.ValidationError do
  @moduledoc """
  Exception raised by `validate!` functions when validation fails.

  This exception contains the validation errors that caused the failure,
  allowing the caller to access detailed error information programmatically.
  """

  defexception [:message, :errors]

  @type t :: %__MODULE__{
          message: String.t(),
          errors: [Sinter.Error.t()]
        }

  @doc """
  Creates a new ValidationError from a list of errors.

  ## Examples

      iex> errors = [Sinter.Error.new([:name], :required, "field is required")]
      iex> raise Sinter.ValidationError, errors: errors
  """
  def exception(opts) do
    errors = Keyword.get(opts, :errors, [])

    message =
      case length(errors) do
        0 -> "Validation failed"
        1 -> "Validation failed: #{Sinter.Error.format(hd(errors))}"
        count -> "Validation failed with #{count} errors:\n#{Sinter.Error.format_errors(errors)}"
      end

    %__MODULE__{
      message: message,
      errors: errors
    }
  end

  @doc """
  Gets the validation errors from the exception.
  """
  @spec errors(t()) :: [Sinter.Error.t()]
  def errors(%__MODULE__{errors: errors}), do: errors

  @doc """
  Formats the validation error for display.
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{message: message}), do: message
end
