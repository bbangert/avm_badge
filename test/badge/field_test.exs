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

  describe "cursor/1" do
    test "a fresh field has its cursor at the start" do
      assert Field.cursor(Field.new(10)) == 0
    end

    test "typing leaves the cursor at the end" do
      assert Field.cursor(type(Field.new(10), "abc")) == 3
    end
  end

  describe "left/1 and right/1" do
    test "left moves the cursor back one character" do
      assert Field.cursor(Field.left(type(Field.new(10), "abc"))) == 2
    end

    test "left stops at the start rather than going negative" do
      field = Field.left(Field.left(Field.left(Field.left(type(Field.new(10), "abc")))))

      assert Field.cursor(field) == 0
    end

    test "right moves the cursor forward one character" do
      field = type(Field.new(10), "abc") |> Field.left() |> Field.left() |> Field.right()

      assert Field.cursor(field) == 2
    end

    test "right stops at the end rather than running past it" do
      assert Field.cursor(Field.right(type(Field.new(10), "abc"))) == 3
    end

    test "moving the cursor never changes the value" do
      field = type(Field.new(10), "abc")

      assert Field.value(Field.left(field)) == "abc"
      assert Field.value(Field.right(Field.left(field))) == "abc"
    end

    test "left on an empty field is a no-op rather than a crash" do
      field = Field.new(10)

      assert Field.left(field) == field
    end
  end

  describe "editing mid-buffer" do
    test "insert lands at the cursor" do
      field = type(Field.new(10), "ac") |> Field.left()

      assert Field.value(type(field, "b")) == "abc"
    end

    test "insert mid-buffer leaves the cursor after what was typed" do
      field = type(Field.new(10), "ac") |> Field.left()

      assert Field.cursor(type(field, "b")) == 2
    end

    test "backspace removes the character before the cursor" do
      field = type(Field.new(10), "abc") |> Field.left()

      assert Field.value(Field.backspace(field)) == "ac"
    end

    test "backspace at the start deletes nothing" do
      field = type(Field.new(10), "abc") |> Field.left() |> Field.left() |> Field.left()

      assert Field.value(Field.backspace(field)) == "abc"
    end

    test "a full field still refuses mid-buffer insertions" do
      field = type(Field.new(3), "abc") |> Field.left()

      assert Field.value(type(field, "z")) == "abc"
    end
  end

  describe "remaining/1" do
    test "a fresh field has its whole capacity left" do
      assert Field.remaining(Field.new(10)) == 10
    end

    test "counts down as characters are typed" do
      assert Field.remaining(type(Field.new(10), "abc")) == 7
    end

    test "reaches zero at capacity and stays there" do
      assert Field.remaining(type(Field.new(3), "abcdef")) == 0
    end
  end

  describe "capacity/1" do
    test "reports what the field was built with" do
      assert Field.capacity(Field.new(10)) == 10
    end
  end

  describe "resize/2" do
    test "changes what is left without touching the value" do
      field = Field.resize(type(Field.new(10), "abc"), 5)

      assert Field.value(field) == "abc"
      assert Field.remaining(field) == 2
    end

    test "a field shrunk past what it holds refuses more and reads zero" do
      field = Field.resize(type(Field.new(10), "abcde"), 3)

      assert Field.value(type(field, "z")) == "abcde"
      assert Field.remaining(field) == 0
    end
  end
end
