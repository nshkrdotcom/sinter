defmodule Sinter.NotGiven do
  @moduledoc """
  Sentinel values for distinguishing omitted fields from explicit `nil`.

  Mirrors Python's `NotGiven`/`Omit` pattern so request payload builders can
  drop fields that callers intentionally left out while preserving `nil` values.
  """

  @not_given :__sinter_not_given__
  @omit :__sinter_omit__

  @doc """
  Retrieve the NotGiven sentinel.
  """
  @spec value() :: :__sinter_not_given__
  def value, do: @not_given

  @doc """
  Retrieve the omit sentinel used to explicitly drop default values.
  """
  @spec omit() :: :__sinter_omit__
  def omit, do: @omit

  @doc """
  Check if a value is the NotGiven sentinel.
  """
  def not_given?(value), do: value === @not_given
  defguard is_not_given(value) when value === @not_given

  @doc """
  Check if a value is the omit sentinel.
  """
  def omit?(value), do: value === @omit
  defguard is_omit(value) when value === @omit

  @doc """
  Replace sentinel values with the provided fallback.
  """
  @spec coalesce(term(), term()) :: term()
  def coalesce(value, default \\ nil) do
    if not_given?(value) or omit?(value) do
      default
    else
      value
    end
  end
end
