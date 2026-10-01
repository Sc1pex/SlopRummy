defmodule Remybun.Engine.MeldTest do
  use ExUnit.Case, async: true

  alias Remybun.Engine.{Card, Meld}

  defp c(rank, suit), do: Card.new(System.unique_integer([:positive]), rank, suit)
  defp j, do: Card.joker(System.unique_integer([:positive]))

  describe "build/2 sets" do
    test "three of a kind with different suits" do
      assert {:ok, %Meld{type: :set, rank: 7}} =
               Meld.build([c(7, :hearts), c(7, :spades), c(7, :clubs)], 1)
    end

    test "rejects duplicate suits" do
      assert {:error, :invalid_meld} = Meld.build([c(7, :hearts), c(7, :hearts), c(7, :clubs)], 1)
    end

    test "rejects more than four cards" do
      cards = [c(7, :hearts), c(7, :spades), c(7, :clubs), c(7, :diamonds), j()]
      assert {:error, :invalid_meld} = Meld.build(cards, 1)
    end

    test "with a joker" do
      assert {:ok, %Meld{type: :set, rank: 9} = m} =
               Meld.build([c(9, :hearts), j(), c(9, :clubs)], 1)

      assert Meld.points(m) == 27
    end

    test "aces in a set are worth 11" do
      {:ok, m} = Meld.build([c(1, :hearts), c(1, :spades), c(1, :clubs)], 1)
      assert Meld.points(m) == 33
    end
  end

  describe "build/2 runs" do
    test "consecutive cards of one suit in any order" do
      assert {:ok, %Meld{type: :run, start: 4, suit: :hearts} = m} =
               Meld.build([c(6, :hearts), c(4, :hearts), c(5, :hearts)], 1)

      assert Enum.map(m.cards, & &1.rank) == [4, 5, 6]
      assert Meld.points(m) == 15
    end

    test "rejects mixed suits and gaps" do
      assert {:error, _} = Meld.build([c(4, :hearts), c(5, :spades), c(6, :hearts)], 1)
      assert {:error, _} = Meld.build([c(4, :hearts), c(5, :hearts), c(7, :hearts)], 1)
    end

    test "low and high aces, no wrap-around" do
      assert {:ok, %Meld{start: 1} = low} =
               Meld.build([c(1, :clubs), c(2, :clubs), c(3, :clubs)], 1)

      assert Meld.points(low) == 6

      assert {:ok, %Meld{start: 12} = high} =
               Meld.build([c(12, :clubs), c(13, :clubs), c(1, :clubs)], 1)

      assert Meld.points(high) == 31

      assert {:error, _} = Meld.build([c(13, :clubs), c(1, :clubs), c(2, :clubs)], 1)
    end

    test "joker fills a gap" do
      assert {:ok, %Meld{start: 4} = m} = Meld.build([c(4, :hearts), j(), c(6, :hearts)], 1)
      assert Card.joker?(Enum.at(m.cards, 1))
    end

    test "free joker extends high when possible" do
      assert {:ok, %Meld{start: 5} = m} = Meld.build([c(5, :hearts), c(6, :hearts), j()], 1)
      assert Card.joker?(List.last(m.cards))
      assert Meld.points(m) == 18
    end

    test "free joker extends low after a high ace" do
      assert {:ok, %Meld{start: 12} = m} = Meld.build([c(13, :hearts), c(1, :hearts), j()], 1)
      assert Card.joker?(hd(m.cards))
    end

    test "respects the joker limit" do
      assert {:error, _} = Meld.build([c(4, :hearts), j(), j()], 1)
      assert {:ok, _} = Meld.build([c(4, :hearts), j(), j()], 2)
    end

    test "can't be all jokers" do
      assert {:error, _} = Meld.build([j(), j(), j()], 3)
    end
  end

  describe "add/3" do
    test "extends a run at both ends" do
      {:ok, run} = Meld.build([c(5, :hearts), c(6, :hearts), c(7, :hearts)], 1)
      assert {:ok, run} = Meld.add(run, [c(4, :hearts), c(8, :hearts)], 1)
      assert run.start == 4
      assert length(run.cards) == 5
    end

    test "rejects cards that collide with existing positions" do
      {:ok, run} = Meld.build([c(5, :hearts), c(6, :hearts), c(7, :hearts)], 1)
      assert {:error, _} = Meld.add(run, [c(6, :hearts)], 1)
    end

    test "existing joker keeps its position" do
      {:ok, run} = Meld.build([c(5, :hearts), c(6, :hearts), j()], 1)
      # joker is 7; adding a real 7 is a collision, not a joker move
      assert {:error, _} = Meld.add(run, [c(7, :hearts)], 1)
      assert {:ok, run} = Meld.add(run, [c(8, :hearts)], 1)
      assert run.start == 5 and length(run.cards) == 4
    end

    test "completes a set" do
      {:ok, set} = Meld.build([c(10, :hearts), c(10, :spades), c(10, :clubs)], 1)
      assert {:ok, %Meld{cards: [_, _, _, _]}} = Meld.add(set, [c(10, :diamonds)], 1)
      assert {:error, _} = Meld.add(set, [c(10, :hearts)], 1)
    end

    test "keeps id and owner" do
      {:ok, set} = Meld.build([c(10, :hearts), c(10, :spades), c(10, :clubs)], 1)
      set = %{set | id: 3, owner: 1}
      assert {:ok, %Meld{id: 3, owner: 1}} = Meld.add(set, [c(10, :diamonds)], 1)
    end
  end

  describe "swap_joker/2" do
    test "in a run, requires the exact card" do
      joker = j()
      {:ok, run} = Meld.build([c(4, :hearts), joker, c(6, :hearts)], 1)
      assert {:error, :invalid_swap} = Meld.swap_joker(run, c(5, :spades))
      assert {:ok, run, ^joker} = Meld.swap_joker(run, c(5, :hearts))
      refute Enum.any?(run.cards, &Card.joker?/1)
    end

    test "in a set, requires a missing suit" do
      joker = j()
      {:ok, set} = Meld.build([c(8, :hearts), c(8, :spades), joker], 1)
      assert {:error, _} = Meld.swap_joker(set, c(8, :hearts))
      assert {:ok, _, ^joker} = Meld.swap_joker(set, c(8, :clubs))
    end

    test "no joker to swap" do
      {:ok, set} = Meld.build([c(8, :hearts), c(8, :spades), c(8, :clubs)], 1)
      assert {:error, _} = Meld.swap_joker(set, c(8, :diamonds))
    end
  end
end
