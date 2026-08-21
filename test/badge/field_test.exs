defmodule Badge.FieldTest do
  use ExUnit.Case, async: true

  alias Badge.Field

  defp type(field, string) do
    :lists.foldl(&Field.insert(&2, &1), field, :erlang.binary_to_list(string))
  end

  describe "new/1" do
    test "starts empty" do
      field = Field.new(10)

      assert Field.value(field) == ""
      assert Field.length(field) == 0
      assert Field.masked(field) == ""
    end
  end

  describe "insert/2" do
    test "characters accumulate in order" do
      assert Field.value(type(Field.new(10), "abc")) == "abc"
    end

    test "length tracks the characters" do
      assert Field.length(type(Field.new(10), "abc")) == 3
    end

    test "punctuation and digits are kept verbatim" do
      assert Field.value(type(Field.new(20), "p@ss-w0rd_1!")) == "p@ss-w0rd_1!"
    end

    test "stops accepting at capacity" do
      field = type(Field.new(3), "abcdef")

      assert Field.value(field) == "abc"
      assert Field.length(field) == 3
    end
  end

  describe "backspace/1" do
    test "removes the last character" do
      assert Field.value(Field.backspace(type(Field.new(10), "abc"))) == "ab"
    end

    test "on an empty field is a no-op rather than a crash" do
      field = Field.new(10)

      assert Field.backspace(field) == field
    end

    test "clears back to empty" do
      field =
        :lists.foldl(fn _i, acc -> Field.backspace(acc) end, type(Field.new(10), "abc"), [1, 2, 3])

      assert Field.value(field) == ""
    end

    test "makes room again after capacity" do
      field = type(Field.new(3), "abcdef")

      assert Field.value(type(Field.backspace(field), "z")) == "abz"
    end
  end

  describe "masked/1" do
    test "is one asterisk per character" do
      assert Field.masked(type(Field.new(10), "abc")) == "***"
    end

    test "never reveals the value" do
      masked = Field.masked(type(Field.new(20), "hunter2"))

      assert :binary.match(masked, "hunter2") == :nomatch
      assert byte_size(masked) == 7
    end
  end
end
