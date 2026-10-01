defmodule Remybun.Engine.RoundTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Remybun.Engine.{Card, Deck, Match, Meld, Round, Rules}

  @rules Rules.preset("classic")

  defp c(id, rank, color), do: Card.new(id, rank, color)
  defp j(id), do: Card.joker(id)
  defp ids(cards), do: Enum.map(cards, & &1.id)

  # A round past the exchange, in seat 0's discard phase, not anyone's first turn.
  defp round_with(hands, opts \\ []) do
    seats = map_size(hands)
    all = fn v -> Map.new(0..(seats - 1), &{&1, v}) end

    %Round{
      Round.new(@rules, seats, 0, Deck.shuffled())
      | hands: hands,
        stock: Keyword.get(opts, :stock, [c(900, 2, :black), c(901, 3, :black)]),
        discard: Keyword.get(opts, :discard, []),
        blocked_discard: Keyword.get(opts, :blocked, nil),
        opened: Keyword.get(opts, :opened, all.(false)),
        turns_taken: Keyword.get(opts, :turns_taken, all.(1)),
        phase: Keyword.get(opts, :phase, :awaiting_discard),
        atu: Keyword.get(opts, :atu, c(950, 7, :blue)),
        atu_holders: Keyword.get(opts, :atu_holders, []),
        atu_announced: Keyword.get(opts, :atu_announced, []),
        multiplier: Keyword.get(opts, :multiplier, 1),
        exchange: nil
    }
  end

  # 10-11-12 red (30) + three 5s (15) = 45: a valid opening with a run and a set.
  defp opening_tiles do
    run = [c(1, 10, :red), c(2, 11, :red), c(3, 12, :red)]
    set = [c(4, 5, :black), c(5, 5, :blue), c(6, 5, :yellow)]
    {run, set}
  end

  describe "deal" do
    test "15 tiles to the starting seat, 14 to the others, then the atu" do
      deck = Deck.shuffled()
      r = Round.new(@rules, 3, 1, deck)
      assert length(r.hands[1]) == 15
      assert length(r.hands[0]) == 14 and length(r.hands[2]) == 14
      assert r.atu == Enum.at(deck, 43)
      assert length(r.stock) == 106 - 43 - 1
      assert r.phase == :exchange
    end

    test "atu holder and doubling" do
      # Deck order: seat 0 gets 15, seat 1 gets 14, then the atu.
      atu = c(200, 1, :red)
      twin = c(201, 1, :red)
      filler = for i <- 1..28, do: c(300 + i, rem(i, 12) + 2, Enum.at(Card.colors(), rem(i, 3)))
      deck = [twin | Enum.take(filler, 14)] ++ Enum.drop(filler, 14) ++ [atu, c(400, 9, :blue)]
      r = Round.new(@rules, 2, 0, deck)
      assert r.atu == atu
      assert r.atu_holders == [0]
      assert r.multiplier == 2
    end
  end

  describe "duplicate exchange" do
    setup do
      # seat 0: pair of 5 black (small); seat 1: pair of 11 red (big) and of 1 blue (nail)
      hands = %{
        0 => [c(1, 5, :black), c(2, 5, :black), c(3, 9, :red)],
        1 => [c(11, 11, :red), c(12, 11, :red), c(13, 1, :blue), c(14, 1, :blue)]
      }

      exchange = %{offers: %{}, next_offer_id: 1, done: MapSet.new(), can_refuse: [1]}
      %{r: %{round_with(hands) | phase: :exchange, exchange: exchange}}
    end

    test "offer, answer and accept swap one tile of each pair", %{r: r} do
      assert {:error, :not_a_duplicate} = Round.play(r, 0, {:offer_duplicate, 3})

      {:ok, r, [%{type: :duplicate_offered, tier: :small, offer_id: 1}]} =
        Round.play(r, 0, {:offer_duplicate, 1})

      assert {:error, :duplicate_already_offered} = Round.play(r, 0, {:offer_duplicate, 2})
      assert {:error, :own_offer} = Round.play(r, 0, {:respond_offer, 1, 1})

      {:ok, r, [%{type: :offer_answered, tier: :big}]} = Round.play(r, 1, {:respond_offer, 1, 11})
      assert {:error, :offer_not_found} = Round.play(r, 1, {:accept_response, 1, 0})

      {:ok, r, [%{type: :duplicates_swapped, tiers: [:small, :big]}]} =
        Round.play(r, 0, {:accept_response, 1, 1})

      assert 11 in ids(r.hands[0]) and 1 not in ids(r.hands[0])
      assert 1 in ids(r.hands[1]) and 11 not in ids(r.hands[1])
      assert r.exchange.offers == %{}
    end

    test "others see only the tier of an offer", %{r: r} do
      {:ok, r, _} = Round.play(r, 0, {:offer_duplicate, 1})
      m = %Match{rules: @rules, seats: 2, round: r, phase: :playing, totals: %{0 => 0, 1 => 0}}
      [offer] = Remybun.Engine.View.for_seat(m, 1).round.exchange.offers
      assert offer.tier == :small and offer.tile == nil
      [own] = Remybun.Engine.View.for_seat(m, 0).round.exchange.offers
      assert own.tile.id == 1
    end

    test "ends when everyone is done", %{r: r} do
      {:ok, r, [%{type: :exchange_ready}]} = Round.play(r, 0, :exchange_done)
      assert {:error, :exchange_done} = Round.play(r, 0, {:offer_duplicate, 1})
      {:ok, r, [%{type: :exchange_finished}]} = Round.play(r, 1, :exchange_done)
      assert r.phase == :awaiting_discard and r.current == 0
    end

    test "only a player dealt 3+ duplicate pairs may refuse", %{r: r} do
      assert {:error, :cannot_refuse} = Round.play(r, 0, :refuse_deal)

      assert {:ok, %Round{phase: :refused}, [%{type: :deal_refused}]} =
               Round.play(r, 1, :refuse_deal)
    end

    test "counts duplicate pairs, jokers included" do
      hand = [j(104), j(105), c(1, 3, :red), c(2, 3, :red), c(3, 3, :blue)]
      assert Round.duplicate_pairs(hand) == 2
    end
  end

  describe "first turn" do
    test "no melding on a player's first turn; the first discard is locked" do
      {run, set} = opening_tiles()
      seat1 = [c(20, 9, :blue), c(21, 3, :red), c(22, 4, :red), c(23, 5, :red)]
      hands = %{0 => run ++ set ++ [c(7, 2, :blue)], 1 => seat1}
      r = round_with(hands, turns_taken: %{0 => 0, 1 => 0})

      assert {:error, :first_turn} = Round.play(r, 0, {:lay_down, [ids(run), ids(set)]})
      {:ok, r, _} = Round.play(r, 0, {:discard, 7})
      assert r.blocked_discard == 7

      assert {:error, :first_turn} = Round.play(r, 1, {:take_discard, 7, [], []})
      r = %{r | turns_taken: %{0 => 1, 1 => 1}}
      assert {:error, :discard_blocked} = Round.play(r, 1, {:take_discard, 7, [[7, 20]], []})
    end
  end

  describe "opening" do
    test "needs the minimum points with a run and a set" do
      {run, set} = opening_tiles()
      long_run = [c(30, 9, :blue), c(31, 10, :blue), c(32, 11, :blue), c(33, 12, :blue)]
      r = round_with(%{0 => run ++ set ++ long_run ++ [c(9, 2, :blue)], 1 => []})

      assert {:error, :opening_too_low} = Round.play(r, 0, {:lay_down, [ids(set)]})

      assert {:error, :opening_needs_run_and_set} =
               Round.play(r, 0, {:lay_down, [ids(run), ids(long_run)]})

      assert {:ok, r, [%{type: :laid_down}]} = Round.play(r, 0, {:lay_down, [ids(run), ids(set)]})
      assert r.opened[0]
    end

    test "three 1s open on their own" do
      ones = [c(1, 1, :red), c(2, 1, :blue), c(3, 1, :black)]
      r = round_with(%{0 => ones ++ [c(4, 7, :red)], 1 => []})
      assert {:ok, %Round{}, _} = Round.play(r, 0, {:lay_down, [ids(ones)]})
    end

    test "no adding to table melds on the opening turn" do
      {run, set} = opening_tiles()

      table = %Meld{
        id: 1,
        owner: 1,
        type: :run,
        color: :black,
        start: 6,
        cards: [c(50, 6, :black), c(51, 7, :black), c(52, 8, :black)]
      }

      hands = %{0 => run ++ set ++ [c(9, 9, :black), c(10, 2, :blue)], 1 => []}
      r = %{round_with(hands) | melds: [table], next_meld_id: 2}

      {:ok, r, _} = Round.play(r, 0, {:lay_down, [ids(run), ids(set)]})
      assert {:error, :opening_turn} = Round.play(r, 0, {:add_to_meld, 1, [9]})

      # On a later turn it's allowed.
      r = %{r | turn: %{pending_joker: nil, opened_now: false}}
      assert {:ok, _, [%{type: :added_to_meld}]} = Round.play(r, 0, {:add_to_meld, 1, [9]})
    end

    test "must keep a tile to discard and rejects tiles not held" do
      {run, set} = opening_tiles()
      r = round_with(%{0 => run ++ set, 1 => []})

      assert {:error, :must_keep_card_to_discard} =
               Round.play(r, 0, {:lay_down, [ids(run), ids(set)]})

      assert {:error, :card_not_in_hand} = Round.play(r, 0, {:lay_down, [[1, 2, 999]]})
      assert {:error, :duplicate_cards} = Round.play(r, 0, {:lay_down, [[1, 2, 3], [3, 4, 5]]})
    end
  end

  describe "taking from the discard pile" do
    test "an unopened player takes only the last tile and must open with it" do
      {[r10, r11, r12], set} = opening_tiles()
      discard = [c(60, 3, :yellow), r12]
      hands = %{0 => [r10, r11 | set] ++ [c(9, 2, :blue)], 1 => []}
      r = round_with(hands, phase: :awaiting_draw, discard: discard)

      assert {:error, :only_last_discard} = Round.play(r, 0, {:take_discard, 60, [[60, 9]], []})
      assert {:error, :must_use_discard} = Round.play(r, 0, {:take_discard, 3, [], []})
      # Using it in melds that don't make a valid opening is rejected as a whole.
      assert {:error, :opening_too_low} = Round.play(r, 0, {:take_discard, 3, [[1, 2, 3]], []})

      assert {:ok, r, [%{type: :took_discard, count: 1}, %{type: :laid_down}]} =
               Round.play(r, 0, {:take_discard, 3, [[1, 2, 3], ids(set)], []})

      assert r.discard == [c(60, 3, :yellow)]
      assert r.phase == :awaiting_discard
    end

    test "an opened player takes any tile and everything after it, using the chosen one" do
      table = %Meld{
        id: 1,
        owner: 0,
        type: :run,
        color: :black,
        start: 6,
        cards: [c(50, 6, :black), c(51, 7, :black), c(52, 8, :black)]
      }

      discard = [c(70, 2, :red), c(71, 9, :black), c(72, 5, :black), c(73, 13, :yellow)]

      r = %{
        round_with(
          %{0 => [c(9, 3, :red), c(10, 4, :red), c(11, 6, :blue), c(12, 7, :yellow)], 1 => []},
          phase: :awaiting_draw,
          discard: discard,
          opened: %{0 => true, 1 => true}
        )
        | melds: [table],
          next_meld_id: 2
      }

      assert {:error, :must_use_discard} = Round.play(r, 0, {:take_discard, 71, [], [{1, [72]}]})

      assert {:ok, r, [%{type: :took_discard, count: 3}, %{type: :added_to_meld}]} =
               Round.play(r, 0, {:take_discard, 71, [], [{1, [71]}]})

      assert ids(r.discard) == [70]
      assert Enum.sort(ids(r.hands[0])) == [9, 10, 11, 12, 72, 73]
    end

    test "the pile is unchanged when the take is rejected" do
      r =
        round_with(
          %{0 => [c(9, 3, :red), c(10, 9, :blue), c(11, 5, :black), c(12, 8, :red)], 1 => []},
          phase: :awaiting_draw,
          discard: [c(70, 2, :red)]
        )

      assert {:error, _} = Round.play(r, 0, {:take_discard, 70, [[70, 9]], []})
      assert r.discard == [c(70, 2, :red)]
    end
  end

  describe "last tiles" do
    setup do
      table = %Meld{
        id: 1,
        owner: 0,
        type: :run,
        color: :black,
        start: 6,
        cards: [c(50, 6, :black), c(51, 7, :black), c(52, 8, :black)]
      }

      discard = [c(70, 2, :red), c(71, 9, :black), c(72, 5, :yellow)]
      %{table: table, discard: discard}
    end

    test "with 3 tiles only the last discard, and it must be added, not melded", ctx do
      hand = [c(1, 5, :red), c(2, 5, :blue), c(3, 10, :yellow)]

      r = %{
        round_with(%{0 => hand, 1 => []},
          phase: :awaiting_draw,
          discard: ctx.discard ++ [c(73, 9, :black)],
          opened: %{0 => true, 1 => true}
        )
        | melds: [ctx.table]
      }

      assert {:error, :only_last_discard} = Round.play(r, 0, {:take_discard, 71, [], [{1, [71]}]})

      assert {:error, :must_add_to_melds} =
               Round.play(r, 0, {:take_discard, 73, [[1, 2, 73]], []})

      r = %{r | discard: ctx.discard ++ [c(73, 9, :black)]}
      assert {:ok, r, _} = Round.play(r, 0, {:take_discard, 73, [], [{1, [73]}]})
      assert {:error, :must_add_to_melds} = Round.play(r, 0, {:lay_down, [[1, 2, 3]]})
    end

    test "with 1-2 tiles the player must draw", ctx do
      r =
        round_with(%{0 => [c(1, 5, :red), c(2, 9, :blue)], 1 => []},
          phase: :awaiting_draw,
          discard: ctx.discard,
          opened: %{0 => true, 1 => true}
        )

      assert {:error, :must_draw} = Round.play(r, 0, {:take_discard, 72, [], [{1, [72]}]})
      assert {:ok, %Round{turn: %{small_hand: true}}, _} = Round.play(r, 0, :draw_stock)
    end

    test "dropping to 3 tiles is announced once" do
      hand = [c(1, 5, :red), c(2, 9, :blue), c(3, 10, :yellow), c(4, 7, :black)]
      r = round_with(%{0 => hand, 1 => [c(9, 2, :red)]})
      {:ok, r, events} = Round.play(r, 0, {:discard, 4})
      assert %{type: :last_tiles, seat: 0, count: 3} in events
      assert r.last_tiles == [0]
    end
  end

  describe "jokers" do
    test "a joker can be added only to the player's own melds" do
      other = %Meld{
        id: 1,
        owner: 1,
        type: :run,
        color: :black,
        start: 6,
        cards: [c(50, 6, :black), c(51, 7, :black), c(52, 8, :black)]
      }

      own = %{
        other
        | id: 2,
          owner: 0,
          color: :red,
          cards: [c(60, 6, :red), c(61, 7, :red), c(62, 8, :red)]
      }

      hand = [j(104), c(1, 3, :blue), c(2, 4, :blue), c(3, 5, :blue)]

      r = %{
        round_with(%{0 => hand, 1 => []}, opened: %{0 => true, 1 => true})
        | melds: [other, own]
      }

      assert {:error, :joker_on_others_meld} = Round.play(r, 0, {:add_to_meld, 1, [104]})
      assert {:ok, _, _} = Round.play(r, 0, {:add_to_meld, 2, [104]})
    end

    test "a joker taken back and laid again scores 0" do
      joker = j(104)

      meld = %Meld{
        id: 1,
        owner: 1,
        type: :run,
        color: :black,
        start: 6,
        cards: [c(50, 6, :black), joker, c(52, 8, :black)]
      }

      hand = [c(1, 7, :black), c(2, 9, :red), c(3, 10, :red), c(4, 2, :blue), c(5, 3, :yellow)]

      r = %{
        round_with(%{0 => hand, 1 => []}, opened: %{0 => true, 1 => true})
        | melds: [meld],
          next_meld_id: 2
      }

      {:ok, r, _} = Round.play(r, 0, {:swap_joker, 1, [1]})
      {:ok, r, _} = Round.play(r, 0, {:lay_down, [[2, 3, 104]]})
      r = %{r | hands: %{r.hands | 0 => [c(4, 2, :blue)]}}
      {:ok, r, _} = Round.play(r, 0, {:discard, 4})
      # 7 black (5) + 9 red (5) + 10 red (10) + the re-used joker (0)
      assert r.result.breakdown[0].laid == 20
    end
  end

  describe "atu" do
    test "the holder must announce it during the exchange" do
      r = %{
        round_with(%{0 => [c(1, 5, :red)], 1 => [c(2, 9, :red)]}, atu_holders: [1])
        | phase: :exchange,
          exchange: %{offers: %{}, next_offer_id: 1, done: MapSet.new(), can_refuse: []}
      }

      assert {:error, :no_atu} = Round.play(r, 0, :announce_atu)
      assert {:ok, r, [%{type: :atu_announced, seat: 1}]} = Round.play(r, 1, :announce_atu)
      assert {:error, :atu_already_announced} = Round.play(r, 1, :announce_atu)
      assert r.atu_announced == [1]
    end

    test "the atu tile can be taken only to close" do
      table = %Meld{
        id: 1,
        owner: 0,
        type: :run,
        color: :blue,
        start: 4,
        cards: [c(50, 4, :blue), c(51, 5, :blue), c(52, 6, :blue)]
      }

      atu = c(950, 7, :blue)

      base = %{
        round_with(%{0 => [], 1 => []}, atu: atu, opened: %{0 => true, 1 => true})
        | melds: [table]
      }

      r = %{base | hands: %{0 => [c(1, 9, :red), c(2, 3, :black)], 1 => []}}
      assert {:error, :atu_only_when_closing} = Round.play(r, 0, {:take_atu, [], [{1, [950]}]})

      r = %{base | hands: %{0 => [c(1, 9, :red)], 1 => []}}
      assert {:ok, r, [%{type: :took_atu} | _]} = Round.play(r, 0, {:take_atu, [], [{1, [950]}]})
      assert r.atu_taken
      assert {:ok, %Round{phase: :finished}, _} = Round.play(r, 0, {:discard, 1})
    end
  end

  test "swapped joker must be used that turn" do
    joker = j(104)

    meld = %Meld{
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
    test "at the end a laid 1 is worth 25 even in a run, and a laid joker 50" do
      meld = %Meld{
        id: 1,
        owner: 0,
        type: :run,
        color: :red,
        start: 1,
        cards: [c(1, 1, :red), j(104), c(3, 3, :red)]
      }

      r = %{
        round_with(%{0 => [c(9, 9, :black)], 1 => []}, opened: %{0 => true, 1 => true})
        | melds: [meld],
          laid_by: %{1 => 0, 104 => 0, 3 => 0}
      }

      {:ok, r, _} = Round.play(r, 0, {:discard, 9})
      # 1 (25) + joker (50) + 3 (5), plus 50 for closing
      assert r.result.breakdown[0].laid == 80
      assert r.result.scores[0] == 130
    end

    test "laid tiles minus hand, closing and atu bonuses" do
      # Seat 0 laid 10-11-12 red (30) and closes; seat 1 laid three 5s (15) and holds a 1 (25)
      # and a joker (50), and was dealt the atu's twin.
      {run, set} = opening_tiles()
      m0 = %Meld{id: 1, owner: 0, type: :run, color: :red, start: 10, cards: run}
      m1 = %Meld{id: 2, owner: 1, type: :set, rank: 5, cards: set}
      hands = %{0 => [c(7, 9, :red)], 1 => [c(8, 1, :blue), j(104)]}

      r = %{
        round_with(hands, opened: %{0 => true, 1 => true}, atu_holders: [1], atu_announced: [1])
        | melds: [m0, m1],
          laid_by: Map.merge(Map.new(ids(run), &{&1, 0}), Map.new(ids(set), &{&1, 1}))
      }

      {:ok, r, _} = Round.play(r, 0, {:discard, 7})
      assert r.result.winner == 0
      assert r.result.scores == %{0 => 30 + 50, 1 => 15 - 75 + 50}

      assert r.result.breakdown[1] ==
               %{laid: 15, hand: 75, opened: true, closing: 0, atu: 50, multiplier: 1, total: -10}

      # The atu bonus needs the announcement.
      r = %{r | atu_announced: []}
      assert r.atu_holders == [1]
    end

    test "a laid joker scores 50; tiles added to others' melds count for the adder" do
      meld = %Meld{
        id: 1,
        owner: 1,
        type: :run,
        color: :black,
        start: 6,
        cards: [c(50, 6, :black), j(104), c(52, 8, :black)]
      }

      r = %{
        round_with(%{0 => [c(9, 9, :black), c(10, 2, :red)], 1 => []},
          opened: %{0 => true, 1 => true}
        )
        | melds: [meld],
          laid_by: %{50 => 1, 104 => 1, 52 => 1}
      }

      {:ok, r, _} = Round.play(r, 0, {:add_to_meld, 1, [9]})
      {:ok, r, _} = Round.play(r, 0, {:discard, 10})
      assert r.result.breakdown[1].laid == 5 + 50 + 5
      assert r.result.breakdown[0].laid == 5
    end

    test "closing with a 1 doubles the closer's score" do
      r =
        round_with(%{0 => [c(1, 1, :red)], 1 => [c(2, 9, :red)]}, opened: %{0 => true, 1 => true})

      {:ok, r, _} = Round.play(r, 0, {:discard, 1})
      assert r.result.double_close
      assert r.result.scores[0] == 100
    end

    test "the closing bonus is a setting" do
      r =
        round_with(%{0 => [c(1, 5, :red)], 1 => [c(2, 9, :red)]}, opened: %{0 => true, 1 => true})

      r = %{r | rules: %{r.rules | closing_bonus: 100}}
      {:ok, r, _} = Round.play(r, 0, {:discard, 1})
      assert r.result.scores[0] == 100
    end

    test "closing with a joker doubles the closer; a 1/joker atu doubles everyone" do
      hands = %{0 => [j(104)], 1 => [c(2, 9, :red)]}
      r = round_with(hands, opened: %{0 => true, 1 => true}, multiplier: 2)
      {:ok, r, _} = Round.play(r, 0, {:discard, 104})
      assert r.result.double_close
      assert r.result.scores == %{0 => 50 * 2 * 2, 1 => -5 * 2}
    end

    test "a player who never opened pays the configurable penalty instead of their hand" do
      hands = %{0 => [c(1, 5, :black)], 1 => [c(2, 1, :red), j(104)], 2 => [c(3, 6, :black)]}

      r =
        round_with(hands,
          opened: %{0 => true, 1 => false, 2 => false},
          atu_holders: [2],
          atu_announced: [2]
        )

      {:ok, r1, _} = Round.play(r, 0, {:discard, 1})
      assert r1.result.scores == %{0 => 50, 1 => -100, 2 => -100 + 50}
      refute r1.result.breakdown[1].opened

      r = %{r | rules: %{r.rules | not_opened_penalty: 200}}
      {:ok, r2, _} = Round.play(r, 0, {:discard, 1})
      assert r2.result.scores[1] == -200
    end

    test "when the stock runs out the round ends without a closing bonus" do
      hands = %{0 => [c(1, 5, :black)], 1 => [c(2, 6, :black)]}
      r = round_with(hands, phase: :awaiting_draw, stock: [], discard: [c(3, 2, :black)])
      assert {:ok, r, [%{type: :round_finished}]} = Round.play(r, 0, :draw_stock)
      assert r.result.winner == nil
      # Nobody opened: each pays the flat penalty.
      assert r.result.scores == %{0 => -100, 1 => -100}
    end
  end

  test "rejects actions out of turn or in the wrong phase" do
    r = round_with(%{0 => [c(1, 5, :black)], 1 => [c(2, 6, :black)]})
    assert {:error, :not_your_turn} = Round.play(r, 1, :draw_stock)
    assert {:error, :wrong_phase} = Round.play(r, 0, :draw_stock)
    assert {:error, :invalid_action} = Round.play(r, 0, :dance)
  end

  defp all_tiles(%Round{} = r) do
    Enum.flat_map(r.hands, &elem(&1, 1)) ++
      r.stock ++
      r.discard ++ Enum.flat_map(r.melds, & &1.cards) ++ if(r.atu_taken, do: [], else: [r.atu])
  end

  property "auto-played matches finish and conserve tiles" do
    check all(seats <- integer(2..4), seed <- integer(), max_runs: 30) do
      :rand.seed(:exsss, {seed, seed, seed})
      m = Match.new(%{@rules | match: {:rounds, seats}}, seats)

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

              if m.round do
                tiles = all_tiles(m.round)
                assert length(tiles) == 106
                assert length(Enum.uniq_by(tiles, & &1.id)) == 106
              end

              {:cont, m}
          end
        end)

      assert m.phase == :finished
      assert m.rounds_played == seats
    end
  end
end
