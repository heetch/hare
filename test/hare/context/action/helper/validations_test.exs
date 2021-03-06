defmodule Hare.Context.Action.Helper.ValidationsTest do
  use ExUnit.Case, async: true

  alias Hare.Context.Action.Helper.Validations
  require Validations

  test "validate/3" do
    config = [foo: "bar"]

    assert :ok == Validations.validate(config, :foo, :binary)

    error = {:error, {:not_atom, :foo, "bar"}}
    assert error == Validations.validate(config, :foo, :atom)

    error = {:error, {:not_present, :baz, config}}
    assert error == Validations.validate(config, :baz, :binary)

    assert :ok == Validations.validate(config, :baz, :binary, required: false)
  end

  test "validate_keyword/2" do
    config = [valid:   [foo: "bar"],
              invalid: %{foo: "bar"}]

    assert :ok == Validations.validate_keyword(config, :valid)

    error = {:error, {:not_keyword_list, :invalid, %{foo: "bar"}}}
    assert error == Validations.validate_keyword(config, :invalid)

    error = {:error, {:not_present, :baz, config}}
    assert error == Validations.validate_keyword(config, :baz)

    assert :ok == Validations.validate_keyword(config, :baz, required: false)
  end
end
