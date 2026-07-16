defmodule SelectoMix.IdentifierTest do
  use ExUnit.Case, async: true

  alias SelectoMix.Identifier

  describe "valid_elixir_identifier?/1" do
    test "accepts letters, digits, and underscores starting with a letter or underscore" do
      assert Identifier.valid_elixir_identifier?("user_id")
      assert Identifier.valid_elixir_identifier?("_private")
      assert Identifier.valid_elixir_identifier?("Category1")
    end

    test "rejects identifiers with invalid characters or leading digits" do
      refute Identifier.valid_elixir_identifier?("1invalid")
      refute Identifier.valid_elixir_identifier?("has space")
      refute Identifier.valid_elixir_identifier?("has-dash")
      refute Identifier.valid_elixir_identifier?("")
    end

    test "rejects non-binary input" do
      refute Identifier.valid_elixir_identifier?(:atom)
      refute Identifier.valid_elixir_identifier?(nil)
      refute Identifier.valid_elixir_identifier?(123)
    end
  end

  describe "valid_sql_identifier?/1" do
    test "accepts the same charset as an Elixir identifier" do
      assert Identifier.valid_sql_identifier?("orders")
      assert Identifier.valid_sql_identifier?("order_items")
    end

    test "rejects identifiers over the 63 byte PostgreSQL limit" do
      too_long = String.duplicate("a", 64)
      exactly_63 = String.duplicate("a", 63)

      assert Identifier.valid_sql_identifier?(exactly_63)
      refute Identifier.valid_sql_identifier?(too_long)
    end

    test "rejects invalid characters" do
      refute Identifier.valid_sql_identifier?("orders; DROP TABLE users;")
      refute Identifier.valid_sql_identifier?("orders--")
      refute Identifier.valid_sql_identifier?("1orders")
    end
  end

  describe "validate_sql_identifier/1" do
    test "returns {:ok, name} for a valid binary" do
      assert {:ok, "orders"} = Identifier.validate_sql_identifier("orders")
    end

    test "returns {:ok, name} for a valid atom, converted to a binary" do
      assert {:ok, "orders"} = Identifier.validate_sql_identifier(:orders)
    end

    test "returns {:error, message} for an invalid binary" do
      assert {:error, message} = Identifier.validate_sql_identifier("bad name; --")
      assert message =~ "invalid SQL identifier"
    end

    test "returns {:error, message} for other terms" do
      assert {:error, _message} = Identifier.validate_sql_identifier(123)
      assert {:error, _message} = Identifier.validate_sql_identifier(nil)
    end
  end

  describe "validate_sql_identifier!/1" do
    test "returns the validated binary on success" do
      assert Identifier.validate_sql_identifier!("orders") == "orders"
    end

    test "raises ArgumentError on failure" do
      assert_raise ArgumentError, ~r/invalid SQL identifier/, fn ->
        Identifier.validate_sql_identifier!("bad name")
      end
    end
  end

  describe "to_atom!/1" do
    test "passes existing atoms through unchanged" do
      assert Identifier.to_atom!(:orders) == :orders
    end

    test "converts a valid binary to an atom" do
      assert Identifier.to_atom!("orders") == :orders
    end

    test "raises ArgumentError for an invalid binary" do
      assert_raise ArgumentError, fn ->
        Identifier.to_atom!("bad name; --")
      end
    end

    test "raises ArgumentError for other terms" do
      assert_raise ArgumentError, fn ->
        Identifier.to_atom!(123)
      end
    end
  end

  describe "to_atom/1" do
    test "returns {:ok, atom} for an existing atom" do
      assert {:ok, :orders} = Identifier.to_atom(:orders)
    end

    test "returns {:ok, atom} for a valid binary" do
      assert {:ok, :orders} = Identifier.to_atom("orders")
    end

    test "returns {:error, message} for an invalid binary" do
      assert {:error, _message} = Identifier.to_atom("bad name; --")
    end

    test "returns {:error, message} for other terms" do
      assert {:error, _message} = Identifier.to_atom(123)
      assert {:error, _message} = Identifier.to_atom(nil)
    end
  end
end
