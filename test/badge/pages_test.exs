defmodule Badge.PagesTest do
  use ExUnit.Case, async: true

  alias Badge.Pages

  @keys [:square, :triangle, :cross, :circle, :clover, :diamond]

  describe "all/0" do
    test "one slot per shape key, in button order" do
      assert for({key, _module} <- Pages.all(), do: key) == @keys
    end
  end

  describe "for_key/1" do
    test "resolves every assigned slot to its module" do
      for {key, module} <- Pages.all(), module != nil do
        assert Pages.for_key(key) == module
      end
    end

    test "an unassigned slot is nil, not a crash" do
      for {key, module} <- Pages.all(), module == nil do
        assert Pages.for_key(key) == nil
      end
    end

    test "an unknown key is nil" do
      assert Pages.for_key(:nonesuch) == nil
      assert Pages.for_key(:home) == nil
    end
  end

  describe "registered pages" do
    test "every assigned module implements the whole behaviour" do
      for {_key, module} <- Pages.all(), module != nil do
        # function_exported?/3 only sees loaded modules.
        Code.ensure_loaded!(module)

        assert function_exported?(module, :title, 0)
        assert function_exported?(module, :icon, 0)
        assert function_exported?(module, :init, 0)
        assert function_exported?(module, :render, 1)
        assert function_exported?(module, :handle_key, 2)
        assert function_exported?(module, :tick, 1)
      end
    end

    test "every icon a page asks for actually exists" do
      for {_key, module} <- Pages.all(), module != nil do
        assert module.icon() in Badge.Icons.names()
      end
    end

    test "titles are short enough to fit a grid cell" do
      for {_key, module} <- Pages.all(), module != nil do
        assert byte_size(module.title()) <= 13
      end
    end

    test "a page's icon matches the key that opens it" do
      for {key, module} <- Pages.all(), module != nil do
        assert module.icon() == key
      end
    end
  end
end
