# Ignore missing Protocol implementations for built-in types
# https://github.com/elixir-lang/elixir/issues/7708
# https://github.com/elixir-lang/elixir/issues/8317

[
  ~r/:0:unknown_function Function .*.Atom.__impl__\/1 does not exist./,
  ~r/:0:unknown_function Function .*.BitString.__impl__\/1 does not exist./,
  ~r/:0:unknown_function Function .*.Float.__impl__\/1 does not exist./,
  ~r/:0:unknown_function Function .*.Function.__impl__\/1 does not exist./,
  ~r/:0:unknown_function Function .*.Integer.__impl__\/1 does not exist./,
  ~r/:0:unknown_function Function .*.List.__impl__\/1 does not exist./,
  ~r/:0:unknown_function Function .*.Map.__impl__\/1 does not exist./,
  ~r/:0:unknown_function Function .*.PID.__impl__\/1 does not exist./,
  ~r/:0:unknown_function Function .*.Port.__impl__\/1 does not exist./,
  ~r/:0:unknown_function Function .*.Reference.__impl__\/1 does not exist./,
  ~r/:0:unknown_function Function .*.Tuple.__impl__\/1 does not exist./
]
