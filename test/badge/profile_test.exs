defmodule Badge.ProfileTest do
  use ExUnit.Case, async: true

  alias Badge.Profile

  defp with_values(overrides), do: Map.merge(Profile.blank(), overrides)

  describe "fields" do
    test "name comes first, since it is the one that must be filled in" do
      assert hd(Profile.keys()) == Profile.required()
      assert Profile.required() == :name
    end

    test "every field has a label and a capacity" do
      for key <- Profile.keys() do
        assert byte_size(Profile.label(key)) > 0
        assert Profile.capacity(key) > 0
      end
    end

    test "a blank profile has every field, all empty" do
      blank = Profile.blank()

      assert Map.keys(blank) |> :lists.sort() == :lists.sort(Profile.keys())
      assert Enum.all?(Map.values(blank), &(&1 == ""))
    end

    test "an unknown field does not crash the lookups" do
      assert Profile.label(:nonesuch) == ""
      assert Profile.capacity(:nonesuch) > 0
    end
  end

  describe "completeness" do
    test "a name is enough" do
      assert Profile.complete?(with_values(%{name: "Gus"}))
    end

    test "everything else without a name is not" do
      refute Profile.complete?(with_values(%{company: "Protolux", email: "a@b.c"}))
    end

    test "an empty name falls back for display rather than showing nothing" do
      assert Profile.display_name(Profile.blank()) == Profile.placeholder()
      assert Profile.display_name(with_values(%{name: "Gus"})) == "Gus"
    end
  end

  describe "lines/1" do
    test "an empty profile has nothing to show" do
      assert Profile.lines(Profile.blank()) == []
    end

    test "the name is not repeated below the rule" do
      refute "Gus" in Profile.lines(with_values(%{name: "Gus"}))
    end

    test "fields keep their declared order" do
      profile = with_values(%{name: "G", company: "C", email: "E", note: "N"})

      assert Profile.lines(profile) == ["C", "E", "N"]
    end

    test "handles carry their marker" do
      assert Profile.lines(with_values(%{github: "gusrs"})) == ["gh gusrs"]
      assert Profile.lines(with_values(%{bluesky: "a.b"})) == ["@a.b"]
    end

    test "several links become several lines" do
      lines = Profile.lines(with_values(%{links: "one.example two.example three.example"}))

      assert lines == ["one.example", "two.example", "three.example"]
    end

    test "a single link is still one line" do
      assert Profile.lines(with_values(%{links: "one.example"})) == ["one.example"]
    end

    test "extra spaces between links do not make empty lines" do
      assert Profile.lines(with_values(%{links: "  a.example   b.example  "})) ==
               ["a.example", "b.example"]
    end
  end
end
