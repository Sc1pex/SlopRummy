defmodule Remybun.Engine.RoundTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Remybun.Engine.{Card, Deck, Match, Round, Rules}

  @rules Rules.preset("classic")

  defp c(id, rank, color), do: Card.new(id, rank, color)

  # A round in the discard phase for seat 0 with the given hands.
  defp round_with(hands, opts \\ []) do
    seats = map_size(hands)

    %Round{
      Round.new(@rules, seats, 0, Deck.new())
      | hands: hands,
        stock: Keyword.get(opts, :stock, [c(900, 2, :black), c(901, 3, :black)]),
        discard: Keyword.get(opts, :discard, []),
        opened: Keyword.get(opts, :opened, Map.new(0..(seats - 1), &{&1, false})),
        phase: Keyword.get(opts, :phase, :awaiting_discard)
    }
  end

  defp ids(cards), do: Enum.map(cards, & &1.id)

  test "deals 15 tiles to the starting seat and 14 to the others" do
    r = Round.new(@rules, 3, 1, Deck.shuffled())
    assert length(r.hands[1]) == 15
    assert length(r.hands[0]) == 14 and length(r.hands[2]) == 14
    assert length(r.stock) == 106 - 43
    assert r.current == 1 and r.phase == :awaiting_discard
  end

  test "rejects actions out of turn or in the wrong phase" do
    r = Round.new(@rules, 2, 0, Deck.shuffled())
    assert {:error, :not_your_turn} = Round.play(r, 1, :draw_stock)
    assert {:error, :wrong_phase} = Round.play(r, 0, :draw_stock)
    assert {:error, :invalid_action} = Round.play(r, 0, :dance)
  end

  test "normal turn: discard, next player draws" do
    r = Round.new(@rules, 2, 0, Deck.shuffled())
    [card | _] = r.hands[0]

    assert {:ok, r, [%{type: :discarded}, %{type: :turn, seat: 1}]} =
             Round.play(r, 0, {:discard, card.id})

    assert r.current == 1 and r.phase == :awaiting_draw
    assert {:ok, r, [%{type: :drew_stock, seat: 1}]} = Round.play(r, 1, :draw_stock)
    assert length(r.hands[1]) == 15
  end

  describe "opening" do
    setup do
      # 10-J-Q of hearts (30) + three 5s (15) = 45
      run = [c(1, 10, :red), c(2, 11, :red), c(3, 12, :red)]
      set = [c(4, 5, :black), c(5, 5, :blue), c(6, 5, :yellow)]
      rest = [c(7, 9, :black), c(8, 2, :blue)]
      %{run: run, set: set, rest: rest}
    end

    test "requires the minimum points in one lay-down", %{run: run, set: set, rest: rest} do
      r = round_with(%{0 => run ++ set ++ rest, 1 => []})
      assert {:error, :opening_too_low} = Round.play(r, 0, {:lay_down, [ids(run)]})
      assert {:ok, r, [%{type: :laid_down}]} = Round.play(r, 0, {:lay_down, [ids(run), ids(set)]})
      assert r.opened[0]
      assert length(r.melds) == 2
      assert ids(r.hands[0]) == [7, 8]
    end

    test "can't add to melds before opening", %{run: run, set: set, rest: rest} do
      r = round_with(%{0 => rest, 1 => run ++ set}, opened: %{0 => false, 1 => true})

      r = %{
        r
        | melds: [
            %Remybun.Engine.Meld{
              id: 1,
              owner: 1,
              type: :run,
              color: :black,
              start: 6,
              cards: [c(50, 6, :black), c(51, 7, :black), c(52, 8, :black)]
            }
          ]
      }

      assert {:error, :not_opened} = Round.play(r, 0, {:add_to_meld, 1, [7]})

      r = %{r | opened: %{0 => true, 1 => true}}
      assert {:ok, r, [%{type: :added_to_meld}]} = Round.play(r, 0, {:add_to_meld, 1, [7]})
      assert length(hd(r.melds).cards) == 4
    end

    test "must keep a card to discard", %{run: run, set: set} do
      r = round_with(%{0 => run ++ set, 1 => []})

      assert {:error, :must_keep_card_to_discard} =
               Round.play(r, 0, {:lay_down, [ids(run), ids(set)]})
    end

    test "rejects cards not in hand and duplicates", %{run: run, set: set, rest: rest} do
      r = round_with(%{0 => run ++ set ++ rest, 1 => []})
      assert {:error, :card_not_in_hand} = Round.play(r, 0, {:lay_down, [[1, 2, 999]]})
      assert {:error, :duplicate_cards} = Round.play(r, 0, {:lay_down, [[1, 2, 3], [3, 4, 5]]})
    end
  end

  describe "discard pickup (must_use)" do
    setup do
      top = c(10, 13, :red)

      hand = [
        c(1, 11, :red),
        c(2, 12, :red),
        c(3, 7, :black),
        c(4, 7, :blue),
        c(5, 7, :yellow),
        c(6, 2, :black)
      ]

      %{r: round_with(%{0 => hand, 1 => []}, phase: :awaiting_draw, discard: [top]), top: top}
    end

    test "taken discard must be used before discarding", %{r: r} do
      {:ok, r, _} = Round.play(r, 0, :take_discard)
      assert {:error, :must_use_discard} = Round.play(r, 0, {:discard, 6})
      assert {:error, :must_use_discard} = Round.play(r, 0, {:discard, 10})

      # J-Q-K hearts (30) + three 7s (21) = 51
      {:ok, r, _} = Round.play(r, 0, {:lay_down, [[1, 2, 10], [3, 4, 5]]})
      assert {:ok, r, events} = Round.play(r, 0, {:discard, 6})
      assert [%{type: :discarded}, %{type: :round_finished}] = events
      assert r.result.winner == 0
    end

    test "can be returned before acting", %{r: r} do
      {:ok, r, _} = Round.play(r, 0, :take_discard)
      assert {:ok, r, [%{type: :returned_discard}]} = Round.play(r, 0, :return_discard)
      assert r.phase == :awaiting_draw and length(r.discard) == 1
      assert {:ok, _, _} = Round.play(r, 0, :draw_stock)
    end

    test "free pickup has no obligation", %{r: r} do
      r = %{r | rules: %{@rules | discard_pickup: :free}}
      {:ok, r, _} = Round.play(r, 0, :take_discard)
      assert {:ok, _, _} = Round.play(r, 0, {:discard, 10})
    end
  end

  test "swapped joker must be used that turn" do
    joker = Card.joker(104)

    meld = %Remybun.Engine.Meld{
      id: 1,
      owner: 1,
      type: :run,
      color: :black,
      start: 6,
      cards: [c(50, 6, :black), joker, c(52, 8, :black)]
    }

    hand = [c(1, 7, :black), c(2, 9, :black), c(3, 10, :black), c(4, 2, :red)]
    r = %{round_with(%{0 => hand, 1 => []}, opened: %{0 => true, 1 => true}) | melds: [meld]}

    assert {:ok, r, [%{type: :swapped_joker}]} = Round.play(r, 0, {:swap_joker, 1, 1})
    assert 104 in ids(r.hands[0])
    assert {:error, :must_use_joker} = Round.play(r, 0, {:discard, 4})
    {:ok, r, _} = Round.play(r, 0, {:lay_down, [[2, 3, 104]]})
    assert {:ok, _, _} = Round.play(r, 0, {:discard, 4})
  end

  describe "scoring" do
    test "going out: opened players pay their hand, unopened pay the flat penalty" do
      hands = %{
        0 => [c(1, 5, :black)],
        1 => [c(2, 1, :red), c(3, 13, :blue), Card.joker(104)],
        2 => [c(4, 2, :black)]
      }

      r = round_with(hands, opened: %{0 => true, 1 => true, 2 => false})
      {:ok, r, _} = Round.play(r, 0, {:discard, 1})
      assert r.result.scores == %{0 => 0, 1 => 25 + 10 + 50, 2 => 100}
    end

    test "closing with a joker doubles everyone's penalty" do
      hands = %{0 => [Card.joker(104)], 1 => [c(2, 9, :red)]}
      r = round_with(hands, opened: %{0 => true, 1 => true})
      {:ok, r, _} = Round.play(r, 0, {:discard, 104})
      assert r.result.scores == %{0 => 0, 1 => 2 * 5}
      assert r.result.joker_close
    end
  end

  describe "stock exhausted" do
    test "reshuffles the discard pile except its top card" do
      discard = [c(10, 2, :black), c(11, 3, :black), c(12, 4, :black)]

      r =
        round_with(%{0 => [c(1, 5, :black)], 1 => []},
          phase: :awaiting_draw,
          stock: [],
          discard: discard
        )

      assert {:ok, r, [%{type: :stock_reshuffled}, %{type: :drew_stock}]} =
               Round.play(r, 0, :draw_stock)

      assert r.discard == [hd(discard)]
      assert length(r.stock) == 1
    end

    test "ends the round when nothing can be reshuffled" do
      r =
        round_with(%{0 => [c(1, 5, :black)], 1 => [c(2, 6, :black)]},
          phase: :awaiting_draw,
          stock: [],
          discard: [c(3, 2, :black)]
        )

      assert {:ok, r, [%{type: :round_finished}]} = Round.play(r, 0, :draw_stock)
      assert r.result.winner == nil
    end
  end

  describe "auto play" do
    test "returns an unused discard, draws and discards" do
      r =
        round_with(%{0 => [c(1, 5, :black), c(2, 9, :red)], 1 => []},
          phase: :awaiting_draw,
          discard: [c(3, 13, :blue)]
        )

      {:ok, r, _} = Round.play(r, 0, :take_discard)
      assert {:ok, r, events} = Round.auto_play(r)
      assert Enum.map(events, & &1.type) == [:returned_discard, :drew_stock, :discarded, :turn]
      assert r.current == 1
    end
  end

  # Cards are never created or destroyed.
  defp all_cards(%Round{} = r) do
    Enum.flat_map(r.hands, &elem(&1, 1)) ++
      r.stock ++ r.discard ++ Enum.flat_map(r.melds, & &1.cards)
  end

  property "auto-played matches finish and conserve cards" do
    check all(seats <- integer(2..4), seed <- integer(), max_runs: 30) do
      :rand.seed(:exsss, {seed, seed, seed})
      # auto play never melds, so rounds end by stock exhaustion
      rules = %{@rules | match: {:rounds, seats}, stock_exhausted: :end_round}
      m = Match.new(rules, seats)

      m =
        Enum.reduce_while(1..10_000, m, fn _, m ->
          case m.phase do
            :finished ->
              {:halt, m}

            :between_rounds ->
              {:ok, m, _} = Match.start_round(m, Deck.shuffled())
              {:cont, m}

            :playing ->
              {:ok, m, _} = Match.auto_play(m)
              cards = all_cards(m.round)
              assert length(cards) == 106
              assert length(Enum.uniq_by(cards, & &1.id)) == 106
              {:cont, m}
          end
        end)

      assert m.phase == :finished
      assert m.rounds_played == seats
    end
  end
end
