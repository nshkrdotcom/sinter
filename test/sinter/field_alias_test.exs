defmodule Sinter.FieldAliasTest do
  use ExUnit.Case, async: true

  alias Sinter.{JsonSchema, Schema, Transform, Validator}

  describe "field alias in validation" do
    test "accepts input using alias name" do
      schema =
        Schema.define([
          {:account_name, :string, [required: true, alias: "accountName"]}
        ])

      # Input uses alias
      assert {:ok, result} = Validator.validate(schema, %{"accountName" => "Test"})
      # Result uses canonical name
      assert result["account_name"] == "Test"
    end

    test "accepts input using canonical name" do
      schema =
        Schema.define([
          {:account_name, :string, [required: true, alias: "accountName"]}
        ])

      # Input uses canonical name
      assert {:ok, result} = Validator.validate(schema, %{"account_name" => "Test"})
      assert result["account_name"] == "Test"
    end

    test "alias takes precedence over canonical name if both present" do
      schema =
        Schema.define([
          {:name, :string, [required: true, alias: "displayName"]}
        ])

      # Both present - alias wins
      input = %{"name" => "canonical", "displayName" => "alias"}
      assert {:ok, result} = Validator.validate(schema, input)
      assert result["name"] == "alias"
    end

    test "required check works with alias" do
      schema =
        Schema.define([
          {:user_id, :string, [required: true, alias: "userId"]}
        ])

      # Provide via alias - should pass
      assert {:ok, _} = Validator.validate(schema, %{"userId" => "123"})

      # Missing both alias and canonical - should fail
      assert {:error, [error]} = Validator.validate(schema, %{})
      assert error.code == :required
    end

    test "alias works with nested objects" do
      inner_schema =
        Schema.define([
          {:first_name, :string, [required: true, alias: "firstName"]}
        ])

      schema =
        Schema.define([
          {:user, {:object, inner_schema}, [required: true]}
        ])

      # Nested alias
      input = %{"user" => %{"firstName" => "Alice"}}
      assert {:ok, result} = Validator.validate(schema, input)
      assert result["user"]["first_name"] == "Alice"
    end
  end

  describe "field alias in transform output" do
    test "outputs using alias name when use_aliases: true" do
      schema =
        Schema.define([
          {:account_name, :string, [required: true, alias: "accountName"]}
        ])

      data = %{"account_name" => "Test"}
      result = Transform.transform(data, schema: schema, use_aliases: true)

      assert result["accountName"] == "Test"
      refute Map.has_key?(result, "account_name")
    end

    test "outputs canonical name when use_aliases: false" do
      schema =
        Schema.define([
          {:account_name, :string, [required: true, alias: "accountName"]}
        ])

      data = %{"account_name" => "Test"}
      result = Transform.transform(data, schema: schema, use_aliases: false)

      assert result["account_name"] == "Test"
      refute Map.has_key?(result, "accountName")
    end

    test "outputs canonical name by default" do
      schema =
        Schema.define([
          {:account_name, :string, [required: true, alias: "accountName"]}
        ])

      data = %{"account_name" => "Test"}
      result = Transform.transform(data, schema: schema)

      assert result["account_name"] == "Test"
    end
  end

  describe "field alias in JSON Schema" do
    test "uses alias as property name" do
      schema =
        Schema.define([
          {:account_name, :string, [required: true, alias: "accountName"]}
        ])

      json_schema = JsonSchema.generate(schema)

      assert Map.has_key?(json_schema["properties"], "accountName")
      refute Map.has_key?(json_schema["properties"], "account_name")
    end

    test "alias appears in required array" do
      schema =
        Schema.define([
          {:account_name, :string, [required: true, alias: "accountName"]}
        ])

      json_schema = JsonSchema.generate(schema)

      assert "accountName" in json_schema["required"]
    end

    test "fields without alias use canonical name" do
      schema =
        Schema.define([
          {:name, :string, [required: true]},
          {:user_id, :string, [required: true, alias: "userId"]}
        ])

      json_schema = JsonSchema.generate(schema)

      assert Map.has_key?(json_schema["properties"], "name")
      assert Map.has_key?(json_schema["properties"], "userId")
      refute Map.has_key?(json_schema["properties"], "user_id")
    end
  end

  describe "Schema.field_aliases/1" do
    test "returns map of canonical name to alias" do
      schema =
        Schema.define([
          {:account_name, :string, [alias: "accountName"]},
          {:user_id, :string, [alias: "userId"]},
          {:no_alias, :string, []}
        ])

      aliases = Schema.field_aliases(schema)

      assert aliases["account_name"] == "accountName"
      assert aliases["user_id"] == "userId"
      refute Map.has_key?(aliases, "no_alias")
    end
  end
end
