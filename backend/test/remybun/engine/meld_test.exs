defmodule Remybun.Engine.MeldTest do
  use ExUnit.Case, async: true

  alias Remybun.Engine.{Card, Meld}

  defp c(rank, color), do: Card.new(System.unique_integer([:positive]), rank, color)
  defp j, do: Card.joker(System.unique_integer([:positive]))

  describe "build/2 sets" do
    test "three of a kind with different colors" do
      assert {:ok, %Meld{type: :set, rank: 7}} =
               Meld.build([c(7, :red), c(7, :blue), c(7, :black)], 1)
    end

    test "rejects duplicate colors" do
      assert {:error, :invalid_meld} = Meld.build([c(7, :red), c(7, :red), c(7, :black)], 1)
    end

    test "rejects more than four cards" do
      cards = [c(7, :red), c(7, :blue), c(7, :black), c(7, :yellow), j()]
      assert {:error, :invalid_meld} = Meld.build(cards, 1)
    end

    test "with a joker" do
      assert {:ok, %Meld{type: :set, rank: 9} = m} =
               Meld.build([c(9, :red), j(), c(9, :black)], 1)

      assert Meld.points(m) == 3 * 5
    end

    test "1s in a set are worth 25 each" do
      {:ok, m} = Meld.build([c(1, :red), c(1, :blue), c(1, :black)], 1)
      assert Meld.points(m) == 75
    end
  end

  describe "build/2 runs" do
    test "consecutive cards of one color in any order" do
      assert {:ok, %Meld{type: :run, start: 4, color: :red} = m} =
               Meld.build([c(6, :red), c(4, :red), c(5, :red)], 1)

      assert Enum.map(m.cards, & &1.rank) == [4, 5, 6]
      assert Meld.points(m) == 15
    end

    test "rejects mixed colors and gaps" do
      assert {:error, _} = Meld.build([c(4, :red), c(5, :blue), c(6, :red)], 1)
      assert {:error, _} = Meld.build([c(4, :red), c(5, :red), c(7, :red)], 1)
    end

    test "1 before 2 (worth 5) or after 13 (worth 10), no wrap-around" do
      assert {:ok, %Meld{start: 1} = low} =
               Meld.build([c(1, :black), c(2, :black), c(3, :black)], 1)

      assert Meld.points(low) == 5 + 5 + 5

      assert {:ok, %Meld{start: 12} = high} =
               Meld.build([c(12, :black), c(13, :black), c(1, :black)], 1)

      assert Meld.points(high) == 10 + 10 + 10

      assert {:error, _} = Meld.build([c(13, :black), c(1, :black), c(2, :black)], 1)
    end

    test "joker fills a gap" do
      assert {:ok, %Meld{start: 4} = m} = Meld.build([c(4, :red), j(), c(6, :red)], 1)
      assert Card.joker?(Enum.at(m.cards, 1))
    end

    test "free joker extends high when possible" do
      assert {:ok, %Meld{start: 5} = m} = Meld.build([c(5, :red), c(6, :red), j()], 1)
      assert Card.joker?(List.last(m.cards))
      assert Meld.points(m) == 5 + 5 + 5
    end

    test "free joker extends low after a high ace" do
      assert {:ok, %Meld{start: 12} = m} = Meld.build([c(13, :red), c(1, :red), j()], 1)
      assert Card.joker?(hd(m.cards))
    end

    test "respects the joker limit" do
      assert {:error, _} = Meld.build([c(4, :red), j(), j()], 1)
      assert {:ok, _} = Meld.build([c(4, :red), j(), j()], 2)
    end

    test "can't be all jokers" do
      assert {:error, _} = Meld.build([j(), j(), j()], 3)
    end
  end

  describe "add/3" do
    test "extends a run at both ends" do
      {:ok, run} = Meld.build([c(5, :red), c(6, :red), c(7, :red)], 1)
      assert {:ok, run} = Meld.add(run, [c(4, :red), c(8, :red)], 1)
      assert run.start == 4
      assert length(run.cards) == 5
    end

    test "rejects cards that collide with existing positions" do
      {:ok, run} = Meld.build([c(5, :red), c(6, :red), c(7, :red)], 1)
      assert {:error, _} = Meld.add(run, [c(6, :red)], 1)
    end

    test "existing joker keeps its position" do
      {:ok, run} = Meld.build([c(5, :red), c(6, :red), j()], 1)
      # joker is 7; adding a real 7 is a collision, not a joker move
      assert {:error, _} = Meld.add(run, [c(7, :red)], 1)
      assert {:ok, run} = Meld.add(run, [c(8, :red)], 1)
      assert run.start == 5 and length(run.cards) == 4
    end

    test "completes a set" do
      {:ok, set} = Meld.build([c(10, :red), c(10, :blue), c(10, :black)], 1)
      assert {:ok, %Meld{cards: [_, _, _, _]}} = Meld.add(set, [c(10, :yellow)], 1)
      assert {:error, _} = Meld.add(set, [c(10, :red)], 1)
    end

    test "keeps id and owner" do
      {:ok, set} = Meld.build([c(10, :red), c(10, :blue), c(10, :black)], 1)
      set = %{set | id: 3, owner: 1}
      assert {:ok, %Meld{id: 3, owner: 1}} = Meld.add(set, [c(10, :yellow)], 1)
    end
  end

  describe "swap_joker/2" do
    test "in a run, requires the exact card" do
      joker = j()
      {:ok, run} = Meld.build([c(4, :red), joker, c(6, :red)], 1)
      assert {:error, :invalid_swap} = Meld.swap_joker(run, c(5, :blue))
      assert {:ok, run, ^joker} = Meld.swap_joker(run, c(5, :red))
      refute Enum.any?(run.cards, &Card.joker?/1)
    end

    test "in a set, requires a missing color" do
      joker = j()
      {:ok, set} = Meld.build([c(8, :red), c(8, :blue), joker], 1)
      assert {:error, _} = Meld.swap_joker(set, c(8, :red))
      assert {:ok, _, ^joker} = Meld.swap_joker(set, c(8, :black))
    end

    test "no joker to swap" do
      {:ok, set} = Meld.build([c(8, :red), c(8, :blue), c(8, :black)], 1)
      assert {:error, _} = Meld.swap_joker(set, c(8, :yellow))
    end
  end
end
