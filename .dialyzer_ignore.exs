[
  # Phase 2 Implementation: Type specification warnings
  # These are intentionally broad type specs for JSON Schema manipulation functions
  # Dialyzer wants overly specific types that would make the code less readable
  {"lib/sinter.ex", "Type specification for find_last_non_nil is a supertype of the success typing."},
  {"lib/sinter/json_schema.ex", "Type specification for ensure_required_array is a supertype of the success typing."},
  {"lib/sinter/json_schema.ex", "Type specification for optimize_for_function_calling is a supertype of the success typing."},
  {"lib/sinter/json_schema.ex", "Type specification for optimize_for_tool_use is a supertype of the success typing."},
  {"lib/sinter/json_schema.ex", "Type specification for remove_unsupported_formats is a supertype of the success typing."},
  {"lib/sinter/json_schema.ex", "Type specification for remove_format_if_unsupported is a supertype of the success typing."},
  {"lib/sinter/json_schema.ex", "Type specification for simplify_complex_unions is a supertype of the success typing."},
  {"lib/sinter/json_schema.ex", "Type specification for ensure_object_properties is a supertype of the success typing."},
  {"lib/sinter/json_schema.ex", "Type specification for flatten_schema is a supertype of the success typing."},
  {"lib/sinter/json_schema.ex", "Type specification for maybe_add_title is a supertype of the success typing."},
  {"lib/sinter/json_schema.ex", "Type specification for maybe_add_description is a supertype of the success typing."},
  {"lib/sinter/performance.ex", "@spec for calculate_field_complexity has more types than are returned by the function."}
]
