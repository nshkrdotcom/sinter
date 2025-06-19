defmodule Sinter.ErrorTest do
  use ExUnit.Case, async: true

  alias Sinter.{Error, ValidationError}

  describe "new/3 and new/4" do
    test "creates error with list path" do
      error = Error.new([:user, :email], :format, "invalid email format")

      assert error.path == [:user, :email]
      assert error.code == :format
      assert error.message == "invalid email format"
      assert error.context == nil
    end

    test "creates error with atom path" do
      error = Error.new(:name, :required, "field is required")

      assert error.path == [:name]
      assert error.code == :required
      assert error.message == "field is required"
      assert error.context == nil
    end

    test "creates error with string path" do
      error = Error.new("email", :format, "invalid format")

      assert error.path == ["email"]
      assert error.code == :format
      assert error.message == "invalid format"
      assert error.context == nil
    end

    test "creates error with context" do
      context = %{expected: "string", actual: "integer", value: 42}
      error = Error.new([:age], :type, "expected string", context)

      assert error.path == [:age]
      assert error.code == :type
      assert error.message == "expected string"
      assert error.context == context
    end

    test "normalizes mixed path types" do
      error = Error.new([:user, "profile", 0, :name], :required, "field required")

      assert error.path == [:user, "profile", 0, :name]
    end
  end

  describe "with_context/4" do
    test "creates error with context information" do
      context = %{expected: "string", actual: "integer", value: 42}
      error = Error.with_context([:age], :type, "expected string", context)

      assert error.path == [:age]
      assert error.code == :type
      assert error.message == "expected string"
      assert error.context == context
    end

    test "requires context to be a map" do
      context = %{min: 5, max: 10, actual: 3}
      error = Error.with_context(:count, :range, "value out of range", context)

      assert error.context == context
    end
  end

  describe "format/2" do
    test "formats error with path by default" do
      error = Error.new([:user, :email], :format, "invalid email format")
      formatted = Error.format(error)

      assert formatted == "user.email: invalid email format"
    end

    test "formats error without path when requested" do
      error = Error.new([:user, :email], :format, "invalid email format")
      formatted = Error.format(error, include_path: false)

      assert formatted == "invalid email format"
    end

    test "uses custom path separator" do
      error = Error.new([:user, :profile, :name], :required, "field is required")
      formatted = Error.format(error, path_separator: " -> ")

      assert formatted == "user -> profile -> name: field is required"
    end

    test "handles empty path" do
      error = Error.new([], :global, "global error")
      formatted = Error.format(error)

      assert formatted == "global error"
    end

    test "handles single element path" do
      error = Error.new(:name, :required, "field is required")
      formatted = Error.format(error)

      assert formatted == "name: field is required"
    end

    test "handles mixed path types in formatting" do
      error = Error.new([:users, 0, :email], :format, "invalid email")
      formatted = Error.format(error)

      assert formatted == "users.0.email: invalid email"
    end
  end

  describe "format_errors/2" do
    test "formats multiple errors" do
      errors = [
        Error.new([:name], :required, "field is required"),
        Error.new([:age], :type, "expected integer")
      ]

      formatted = Error.format_errors(errors)

      assert formatted == "name: field is required\nage: expected integer"
    end

    test "formats empty error list" do
      formatted = Error.format_errors([])

      assert formatted == ""
    end

    test "passes options to individual error formatting" do
      errors = [
        Error.new([:name], :required, "field is required"),
        Error.new([:age], :type, "expected integer")
      ]

      formatted = Error.format_errors(errors, include_path: false)

      assert formatted == "field is required\nexpected integer"
    end
  end

  describe "group_by_path/1" do
    test "groups errors by their path" do
      errors = [
        Error.new([:user, :name], :required, "field is required"),
        Error.new([:user, :name], :min_length, "too short"),
        Error.new([:user, :email], :format, "invalid format"),
        Error.new([:settings], :type, "expected map")
      ]

      grouped = Error.group_by_path(errors)

      assert map_size(grouped) == 3
      assert length(grouped[[:user, :name]]) == 2
      assert length(grouped[[:user, :email]]) == 1
      assert length(grouped[[:settings]]) == 1

      # Check specific errors
      name_errors = grouped[[:user, :name]]
      assert Enum.any?(name_errors, &(&1.code == :required))
      assert Enum.any?(name_errors, &(&1.code == :min_length))
    end

    test "handles empty error list" do
      grouped = Error.group_by_path([])

      assert grouped == %{}
    end
  end

  describe "summarize/1" do
    test "creates summary of validation errors" do
      errors = [
        Error.new([:name], :required, "field is required"),
        Error.new([:age], :type, "expected integer"),
        Error.new([:email], :format, "invalid email format"),
        Error.new([:password], :required, "field is required")
      ]

      summary = Error.summarize(errors)

      assert summary.total_errors == 4
      assert :required in summary.error_codes
      assert :type in summary.error_codes
      assert :format in summary.error_codes
      assert length(summary.error_codes) == 3

      assert [:name] in summary.affected_paths
      assert [:age] in summary.affected_paths
      assert [:email] in summary.affected_paths
      assert [:password] in summary.affected_paths

      assert summary.by_code[:required] == 2
      assert summary.by_code[:type] == 1
      assert summary.by_code[:format] == 1
    end

    test "handles empty error list" do
      summary = Error.summarize([])

      assert summary.total_errors == 0
      assert summary.error_codes == []
      assert summary.affected_paths == []
      assert summary.by_code == %{}
    end

    test "handles single error" do
      errors = [Error.new([:name], :required, "field is required")]
      summary = Error.summarize(errors)

      assert summary.total_errors == 1
      assert summary.error_codes == [:required]
      assert summary.affected_paths == [[:name]]
      assert summary.by_code == %{required: 1}
    end
  end
end

defmodule Sinter.ValidationErrorTest do
  use ExUnit.Case, async: true

  alias Sinter.{Error, ValidationError}

  describe "exception/1" do
    test "creates exception with single error" do
      error = Error.new([:name], :required, "field is required")
      exception = ValidationError.exception(errors: [error])

      assert exception.errors == [error]
      assert exception.message == "Validation failed: name: field is required"
    end

    test "creates exception with multiple errors" do
      errors = [
        Error.new([:name], :required, "field is required"),
        Error.new([:age], :type, "expected integer")
      ]

      exception = ValidationError.exception(errors: errors)

      assert exception.errors == errors
      assert String.contains?(exception.message, "Validation failed with 2 errors:")
      assert String.contains?(exception.message, "name: field is required")
      assert String.contains?(exception.message, "age: expected integer")
    end

    test "creates exception with no errors" do
      exception = ValidationError.exception(errors: [])

      assert exception.errors == []
      assert exception.message == "Validation failed"
    end

    test "creates exception with default empty errors" do
      exception = ValidationError.exception([])

      assert exception.errors == []
      assert exception.message == "Validation failed"
    end
  end

  describe "errors/1" do
    test "returns validation errors from exception" do
      errors = [Error.new([:name], :required, "field is required")]
      exception = ValidationError.exception(errors: errors)

      assert ValidationError.errors(exception) == errors
    end
  end

  describe "format/1" do
    test "returns formatted message" do
      error = Error.new([:name], :required, "field is required")
      exception = ValidationError.exception(errors: [error])

      formatted = ValidationError.format(exception)

      assert formatted == "Validation failed: name: field is required"
    end
  end

  describe "raising ValidationError" do
    test "can be raised and caught" do
      errors = [Error.new([:name], :required, "field is required")]

      assert_raise ValidationError, "Validation failed: name: field is required", fn ->
        raise ValidationError, errors: errors
      end
    end

    test "preserves error information when caught" do
      errors = [Error.new([:name], :required, "field is required")]

      try do
        raise ValidationError, errors: errors
      rescue
        e in ValidationError ->
          assert ValidationError.errors(e) == errors
          assert String.contains?(ValidationError.format(e), "name: field is required")
      end
    end
  end
end
