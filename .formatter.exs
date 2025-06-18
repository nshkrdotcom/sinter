# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  line_length: 100,
  locals_without_parens: [
    # Schema DSL
    field: 2,
    field: 3,
    option: 2,

    # Test helpers
    assert_error: 2,
    assert_valid: 2,
    refute_valid: 2
  ],
  export: [
    locals_without_parens: [
      field: 2,
      field: 3,
      option: 2
    ]
  ]
]
