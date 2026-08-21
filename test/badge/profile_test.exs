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
      assert Profile.lines(with_values(%{name: "Gus"})) == []
    end

    test "fields keep their declared order" do
      profile = with_values(%{name: "G", company: "C", email: "E", links: "L"})

      assert Profile.lines(profile) == [{:company, "C"}, {:email, "E"}, {:link, "L"}]
    end

    test "handles carry an icon instead of a text marker" do
      assert Profile.lines(with_values(%{github: "gusrs"})) == [{:github, "gusrs"}]
      assert Profile.lines(with_values(%{bluesky: "a.b"})) == [{:bluesky, "a.b"}]
      assert Profile.lines(with_values(%{mastodon: "a@b.c"})) == [{:mastodon, "a@b.c"}]
      assert Profile.lines(with_values(%{email: "a@b.c"})) == [{:email, "a@b.c"}]
    end

    test "every icon a field asks for actually exists" do
      for key <- Profile.keys(), Profile.icon(key) != nil do
        assert Profile.icon(key) in Badge.Icons.names()
      end
    end

    test "the name and its own line carry no icon" do
      assert Profile.icon(:name) == nil
    end

    test "every field but the name has one, so the badge reads as a list" do
      for key <- Profile.keys(), key != Profile.required() do
        assert Profile.icon(key) != nil
      end
    end

    test "several links become several lines" do
      lines = Profile.lines(with_values(%{links: "one.example two.example three.example"}))

      assert lines == [{:link, "one.example"}, {:link, "two.example"}, {:link, "three.example"}]
    end

    test "a single link is still one line" do
      assert Profile.lines(with_values(%{links: "one.example"})) == [{:link, "one.example"}]
    end

    test "extra spaces between links do not make empty lines" do
      assert Profile.lines(with_values(%{links: "  a.example   b.example  "})) ==
               [{:link, "a.example"}, {:link, "b.example"}]
    end
  end
end
