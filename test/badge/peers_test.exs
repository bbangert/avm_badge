defmodule Badge.PeersTest do
  use ExUnit.Case, async: true

  alias Badge.Peers

  defp id(n), do: <<0, 0, 0, 0, 0, n>>
  defp profile(name), do: %{name: name, company: "", email: ""}

  describe "add/3" do
    test "the first badge met" do
      peers = Peers.add([], id(1), profile("Gus"))

      assert Peers.count(peers) == 1
      assert Peers.find(peers, id(1)).profile.name == "Gus"
    end

    test "the newest badge comes first" do
      peers = [] |> Peers.add(id(1), profile("A")) |> Peers.add(id(2), profile("B"))

      assert hd(peers).profile.name == "B"
    end

    test "meeting the same chip again updates rather than duplicating" do
      peers =
        []
        |> Peers.add(id(1), profile("Gus"))
        |> Peers.add(id(2), profile("Other"))
        |> Peers.add(id(1), profile("Gus Ross"))

      assert Peers.count(peers) == 2
      assert Peers.find(peers, id(1)).profile.name == "Gus Ross"
    end

    test "two badges with different chips are both kept" do
      peers = [] |> Peers.add(id(1), profile("A")) |> Peers.add(id(2), profile("B"))

      assert Peers.count(peers) == 2
    end

    test "the list is bounded, dropping the ones met longest ago" do
      peers =
        :lists.foldl(
          fn n, acc -> Peers.add(acc, id(rem(n, 200)), profile("n")) end,
          [],
          :lists.seq(1, 200)
        )

      assert Peers.count(peers) <= 64
    end
  end

  describe "find/2" do
    test "a chip never met is nil rather than a crash" do
      assert Peers.find([], id(9)) == nil
      assert Peers.find(Peers.add([], id(1), profile("A")), id(9)) == nil
    end
  end

  describe "storage" do
    test "round-trips through the blob" do
      peers = [] |> Peers.add(id(1), profile("Gus")) |> Peers.add(id(2), profile("Other"))

      assert peers |> Peers.encode() |> Peers.decode() == peers
    end

    test "no peers round-trips as no peers" do
      assert [] |> Peers.encode() |> Peers.decode() == []
    end

    test "nothing stored yet reads as no peers" do
      assert Peers.decode(nil) == []
      assert Peers.decode("") == []
    end

    test "a corrupt blob reads as no peers rather than crashing the badge" do
      for junk <- ["not a term", <<131, 99, 99, 99>>, <<0, 1, 2, 3>>, <<131>>] do
        assert Peers.decode(junk) == []
      end
    end

    test "a well-formed term of the wrong shape is discarded" do
      assert Peers.decode(:erlang.term_to_binary(%{not: "a list"})) == []
      assert Peers.decode(:erlang.term_to_binary([1, 2, 3])) == []
    end

    test "entries of the wrong shape are dropped, the good ones kept" do
      mixed = :erlang.term_to_binary([%{id: id(1), profile: profile("A")}, :junk, %{id: 5}])

      assert Peers.decode(mixed) == [%{id: id(1), profile: profile("A")}]
    end
  end
end
