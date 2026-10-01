defmodule Remybun.Engine.Round do
  @moduledoc """
  State machine for a single deal of Remi etalat.

  ## Deal
  The starting seat gets 15 tiles, the others 14. The next tile of the stock is the
  **atu**: it is taken out of play and shown. A player dealt the atu's twin gets a bonus;
  an atu that is a 1 or a joker doubles every score of the round.

  ## Phases
    * `:exchange` — before the first discard, players may swap duplicates (see below)
      and a player dealt 3+ duplicate pairs may refuse the deal (`:refused`).
    * `:awaiting_draw` → `:awaiting_discard` → next seat … → `:finished`.
      The starting seat begins in `:awaiting_discard`.

  ## Actions (`play/3`)
  Exchange phase (any seat): `{:offer_duplicate, tile_id}`, `{:withdraw_offer, offer_id}`,
  `{:respond_offer, offer_id, tile_id}`, `{:withdraw_response, offer_id}`,
  `{:accept_response, offer_id, seat}`, `:announce_atu`, `:exchange_done`, `:refuse_deal`.

  Turns: `:draw_stock`, `{:take_discard, tile_id, melds, additions}`,
  `{:lay_down, [[tile_id]]}`, `{:add_to_meld, meld_id, [tile_id]}`,
  `{:swap_joker, meld_id, [tile_id]}`, `{:take_atu, melds, additions}`, `{:discard, tile_id}`.

  ## Atu
  The player dealt the atu's twin must announce it during the exchange phase to get the
  bonus. The atu tile itself can be taken only on the turn a player closes: it must be used
  in the same action, which must leave just the closing tile in hand.

  ## Discard pile
  A row in the order tiles were discarded. The starting player's first discard can never
  be taken. A player who hasn't opened may take only the last tile; a player who has
  opened and holds at least 4 tiles may take any tile and gets every tile after it too.
  The chosen tile must be used in the same action (`take_discard` carries the melds and
  additions it goes into).

  ## Last tiles
  Holding 3 or fewer tiles is announced automatically (`:last_tiles` event). With 3 tiles
  at the start of the turn a player may take only the last discard; with 1–2 they must draw.
  With 3 or fewer they may not lay down new melds, only add to melds on the table.

  ## Restrictions
  No melding (laying down, adding, swapping jokers, taking a discard) on a player's first
  turn. On the turn a player opens they may not add to melds already on the table.
  An opening needs `opening_min_points` with at least one run and one set, unless it
  includes a set of 1s. A joker may be added only to the player's own melds.

  ## Scoring
  Per player: value of the tiles they laid minus the tiles left in hand (2–9 = 5,
  10–13 = 10, 1 = 25, joker = 50 either way; a joker that was taken back and laid again is
  worth 0); a player who never opened pays `not_opened_penalty` instead of counting their
  hand. Plus `closing_bonus` for the closer and the atu bonus if announced. Then closing
  with a joker or a 1 doubles the closer's score and a 1/joker atu doubles everyone's.
  If the stock runs out the round ends and nobody gets the closing bonus.

  **Închis pe tablă**: a player who opens and closes on the same turn gets
  `closed_on_board_bonus` instead of the closing bonus and the value of the tiles they laid
  (which is added too when `closed_on_board_add_hand` is set). Atu and multipliers still apply.

  Every action returns `{:ok, round, events}` or `{:error, reason}`. Events are
  JSON-friendly maps that are safe to show to every player.
  """

  alias Remybun.Engine.{Card, Meld, Rules}

  defstruct [
    :rules,
    :seats,
    :starting_seat,
    :current,
    :phase,
    :result,
    :atu,
    :blocked_discard,
    hands: %{},
    stock: [],
    # Oldest first; the last element is the top.
    discard: [],
    melds: [],
    opened: %{},
    turns_taken: %{},
    laid_by: %{},
    atu_holders: [],
    atu_announced: [],
    atu_taken: false,
    reused_jokers: MapSet.new(),
    last_tiles: [],
    multiplier: 1,
    next_meld_id: 1,
    exchange: nil,
    turn: %{pending_joker: nil, opened_now: false, small_hand: false}
  ]

  @type t :: %__MODULE__{}

  @new_turn %{pending_joker: nil, opened_now: false, small_hand: false}

  @doc "Deals a new round from `deck` (already shuffled)."
  def new(%Rules{} = rules, seats, starting_seat, deck) when starting_seat in 0..(seats - 1)//1 do
    order = Enum.map(0..(seats - 1), &rem(starting_seat + &1, seats))

    {hands, [atu | stock]} =
      Enum.reduce(order, {%{}, deck}, fn seat, {hands, deck} ->
        count = if seat == starting_seat, do: Rules.hand_size() + 1, else: Rules.hand_size()
        {hand, rest} = Enum.split(deck, count)
        {Map.put(hands, seat, hand), rest}
      end)

    holders = for {seat, hand} <- hands, Enum.any?(hand, &Card.twin?(&1, atu)), do: seat
    seat_map = fn value -> Map.new(0..(seats - 1), &{&1, value}) end

    %__MODULE__{
      rules: rules,
      seats: seats,
      starting_seat: starting_seat,
      current: starting_seat,
      phase: :exchange,
      hands: hands,
      stock: stock,
      atu: atu,
      atu_holders: Enum.sort(holders),
      multiplier: if(atu.rank in [nil, 1], do: 2, else: 1),
      opened: seat_map.(false),
      turns_taken: seat_map.(0),
      exchange: %{
        offers: %{},
        next_offer_id: 1,
        done: MapSet.new(),
        can_refuse:
          for({seat, hand} <- hands, duplicate_pairs(hand) >= 3, do: seat) |> Enum.sort()
      }
    }
  end

  @doc "Number of duplicate pairs (two identical tiles) in a hand."
  def duplicate_pairs(hand) do
    hand |> Enum.frequencies_by(&{&1.rank, &1.color}) |> Enum.count(fn {_, n} -> n >= 2 end)
  end

  ## ---- Exchange phase ----

  def play(%__MODULE__{phase: :exchange} = r, seat, action) when is_integer(seat) do
    if seat in 0..(r.seats - 1), do: exchange(r, seat, action), else: {:error, :not_a_player}
  end

  def play(%__MODULE__{phase: phase}, _seat, _action) when phase in [:finished, :refused],
    do: {:error, :round_finished}

  def play(%__MODULE__{current: current}, seat, _action) when seat != current,
    do: {:error, :not_your_turn}

  ## ---- Turns ----

  def play(%__MODULE__{phase: :awaiting_draw} = r, seat, :draw_stock), do: draw_stock(r, seat)

  def play(
        %__MODULE__{phase: :awaiting_draw} = r,
        seat,
        {:take_discard, tile_id, melds, additions}
      )
      when is_list(melds) and is_list(additions) do
    held = length(r.hands[seat])

    with :ok <- check_not_first_turn(r, seat),
         :ok <- if(held <= 2, do: {:error, :must_draw}, else: :ok),
         {:ok, index} <- discard_index(r, seat, tile_id, held),
         :ok <- if(held <= 3 and melds != [], do: {:error, :must_add_to_melds}, else: :ok) do
      {kept, taken} = Enum.split(r.discard, index)
      opened_before = r.opened[seat]

      r = %{
        r
        | discard: kept,
          hands: Map.update!(r.hands, seat, &(&1 ++ taken)),
          phase: :awaiting_discard,
          turn: %{@new_turn | small_hand: held <= 3}
      }

      event = %{
        type: :took_discard,
        seat: seat,
        card: Card.to_map(hd(taken)),
        count: length(taken)
      }

      with :ok <- if(melds == [] and additions == [], do: {:error, :must_use_discard}, else: :ok),
           :ok <- if(additions != [] and not opened_before, do: {:error, :not_opened}, else: :ok),
           {:ok, r, e1} <- if(melds == [], do: {:ok, r, []}, else: lay_down(r, seat, melds)),
           {:ok, r, e2} <- apply_additions(r, seat, additions),
           :ok <- if(in_hand?(r.hands[seat], tile_id), do: {:error, :must_use_discard}, else: :ok) do
        {:ok, r, [event | e1 ++ e2]}
      end
    end
  end

  def play(%__MODULE__{phase: :awaiting_discard} = r, seat, {:lay_down, groups})
      when is_list(groups) do
    with :ok <- check_not_first_turn(r, seat),
         :ok <- check_not_small_hand(r) do
      lay_down(r, seat, groups)
    end
  end

  def play(%__MODULE__{phase: :awaiting_discard} = r, seat, {:add_to_meld, meld_id, ids})
      when is_list(ids) do
    with :ok <- check_not_first_turn(r, seat), do: apply_additions(r, seat, [{meld_id, ids}])
  end

  def play(%__MODULE__{phase: :awaiting_discard} = r, seat, {:swap_joker, meld_id, ids})
      when is_list(ids) do
    with :ok <- check_not_first_turn(r, seat),
         :ok <- check_can_touch_table(r, seat),
         true <- r.rules.joker_swap || {:error, :joker_swap_disabled},
         {:ok, meld} <- find_meld(r, meld_id),
         {:ok, [cards], hand} <- take_groups(r.hands[seat], [ids]),
         {:ok, meld, joker} <- Meld.swap_joker(meld, cards) do
      r = %{
        r
        | hands: Map.put(r.hands, seat, hand ++ [joker]),
          melds: replace_meld(r.melds, meld),
          laid_by:
            cards
            |> Enum.reduce(r.laid_by, &Map.put(&2, &1.id, seat))
            |> Map.delete(joker.id),
          reused_jokers: MapSet.put(r.reused_jokers, joker.id),
          turn: %{r.turn | pending_joker: joker.id}
      }

      {:ok, r, [%{type: :swapped_joker, seat: seat, meld: Meld.to_map(meld)}]}
    end
  end

  def play(%__MODULE__{phase: :awaiting_discard} = r, seat, {:swap_joker, meld_id, id})
      when is_integer(id),
      do: play(r, seat, {:swap_joker, meld_id, [id]})

  # The atu can be taken only to close: used right away, leaving just the closing tile.
  def play(%__MODULE__{phase: :awaiting_discard} = r, seat, {:take_atu, melds, additions})
      when is_list(melds) and is_list(additions) do
    with :ok <- check_not_first_turn(r, seat),
         :ok <- if(r.atu_taken, do: {:error, :atu_taken}, else: :ok),
         :ok <- if(melds == [] and additions == [], do: {:error, :must_use_atu}, else: :ok),
         :ok <- if(melds != [], do: check_not_small_hand(r), else: :ok) do
      r = %{r | hands: Map.update!(r.hands, seat, &(&1 ++ [r.atu]))}

      with {:ok, r, e1} <- if(melds == [], do: {:ok, r, []}, else: lay_down(r, seat, melds)),
           {:ok, r, e2} <- apply_additions(r, seat, additions),
           :ok <- if(in_hand?(r.hands[seat], r.atu.id), do: {:error, :must_use_atu}, else: :ok),
           :ok <- if(length(r.hands[seat]) == 1, do: :ok, else: {:error, :atu_only_when_closing}) do
        event = %{type: :took_atu, seat: seat, card: Card.to_map(r.atu)}
        {:ok, %{r | atu_taken: true}, [event | e1 ++ e2]}
      end
    end
  end

  def play(%__MODULE__{phase: :awaiting_discard} = r, seat, {:discard, card_id}) do
    if in_hand?(r.hands[seat], r.turn.pending_joker),
      do: {:error, :must_use_joker},
      else: do_discard(r, seat, card_id)
  end

  def play(%__MODULE__{}, _seat, action)
      when action in [:draw_stock, :exchange_done, :refuse_deal, :announce_atu] or
             (is_tuple(action) and
                elem(action, 0) in [
                  :take_discard,
                  :lay_down,
                  :add_to_meld,
                  :swap_joker,
                  :take_atu,
                  :discard
                ]),
      do: {:error, :wrong_phase}

  def play(%__MODULE__{}, _seat, _action), do: {:error, :invalid_action}

  @doc """
  Plays automatically on a timeout: ends the exchange phase, or draws from the stock and
  discards the highest tile (ignoring a pending joker obligation).
  """
  def auto_play(%__MODULE__{phase: phase} = r) when phase in [:finished, :refused],
    do: {:ok, r, []}

  def auto_play(%__MODULE__{phase: :exchange} = r),
    do: {:ok, end_exchange(r), [%{type: :exchange_finished}]}

  def auto_play(%__MODULE__{phase: :awaiting_draw, current: seat} = r) do
    with {:ok, r, events} <- draw_stock(r, seat),
         {:ok, r, more} <- auto_play(r) do
      {:ok, r, events ++ more}
    end
  end

  def auto_play(%__MODULE__{phase: :awaiting_discard, current: seat} = r) do
    hand = r.hands[seat]

    card =
      hand |> Enum.reject(&Card.joker?/1) |> Enum.max_by(&Card.hand_value(&1, 0), fn -> nil end) ||
        hd(hand)

    do_discard(r, seat, card.id)
  end

  ## ---- Exchange internals ----

  defp exchange(r, seat, {:offer_duplicate, tile_id}) do
    with :ok <- check_not_done(r, seat),
         {:ok, tile} <- duplicate_tile(r, seat, tile_id),
         :ok <- check_uncommitted(r, seat, tile) do
      id = r.exchange.next_offer_id
      offer = %{id: id, seat: seat, tile: tile, tier: Card.tier(tile), responses: %{}}

      r =
        put_exchange(r, %{
          r.exchange
          | offers: Map.put(r.exchange.offers, id, offer),
            next_offer_id: id + 1
        })

      {:ok, r, [%{type: :duplicate_offered, seat: seat, offer_id: id, tier: offer.tier}]}
    end
  end

  defp exchange(r, seat, {:withdraw_offer, offer_id}) do
    case r.exchange.offers[offer_id] do
      %{seat: ^seat} ->
        r = put_exchange(r, %{r.exchange | offers: Map.delete(r.exchange.offers, offer_id)})
        {:ok, r, [%{type: :offer_withdrawn, seat: seat, offer_id: offer_id}]}

      _ ->
        {:error, :offer_not_found}
    end
  end

  defp exchange(r, seat, {:respond_offer, offer_id, tile_id}) do
    with :ok <- check_not_done(r, seat),
         {:ok, offer} <- find_offer(r, offer_id),
         true <- offer.seat != seat || {:error, :own_offer},
         {:ok, tile} <- duplicate_tile(r, seat, tile_id),
         :ok <- check_uncommitted(r, seat, tile, offer_id) do
      offer = put_in(offer.responses[seat], tile)
      r = put_in(r.exchange.offers[offer_id], offer)
      {:ok, r, [%{type: :offer_answered, seat: seat, offer_id: offer_id, tier: Card.tier(tile)}]}
    end
  end

  defp exchange(r, seat, {:withdraw_response, offer_id}) do
    with {:ok, offer} <- find_offer(r, offer_id),
         true <- Map.has_key?(offer.responses, seat) || {:error, :response_not_found} do
      r = put_in(r.exchange.offers[offer_id].responses, Map.delete(offer.responses, seat))
      {:ok, r, [%{type: :response_withdrawn, seat: seat, offer_id: offer_id}]}
    end
  end

  defp exchange(r, seat, {:accept_response, offer_id, from_seat}) do
    with {:ok, %{seat: ^seat} = offer} <- find_offer(r, offer_id),
         %Card{} = received <- offer.responses[from_seat] || {:error, :response_not_found} do
      given = offer.tile

      hands =
        r.hands
        |> Map.update!(seat, &(Enum.reject(&1, fn t -> t.id == given.id end) ++ [received]))
        |> Map.update!(from_seat, &(Enum.reject(&1, fn t -> t.id == received.id end) ++ [given]))

      r = %{r | hands: hands}
      offers = r.exchange.offers |> Map.delete(offer_id) |> prune_offers(r)
      r = put_exchange(r, %{r.exchange | offers: offers})

      {:ok, r,
       [
         %{
           type: :duplicates_swapped,
           seats: [seat, from_seat],
           tiers: [offer.tier, Card.tier(received)]
         }
       ]}
    else
      {:ok, _} -> {:error, :offer_not_found}
      error -> error
    end
  end

  defp exchange(r, seat, :exchange_done) do
    r = put_exchange(r, %{r.exchange | done: MapSet.put(r.exchange.done, seat)})

    if MapSet.size(r.exchange.done) == r.seats do
      {:ok, end_exchange(r), [%{type: :exchange_finished}]}
    else
      {:ok, r, [%{type: :exchange_ready, seat: seat}]}
    end
  end

  defp exchange(r, seat, :announce_atu) do
    cond do
      seat not in r.atu_holders ->
        {:error, :no_atu}

      seat in r.atu_announced ->
        {:error, :atu_already_announced}

      true ->
        {:ok, %{r | atu_announced: [seat | r.atu_announced]},
         [%{type: :atu_announced, seat: seat}]}
    end
  end

  defp exchange(r, seat, :refuse_deal) do
    if seat in r.exchange.can_refuse do
      {:ok, %{r | phase: :refused}, [%{type: :deal_refused, seat: seat}]}
    else
      {:error, :cannot_refuse}
    end
  end

  defp exchange(_r, _seat, _action), do: {:error, :wrong_phase}

  defp end_exchange(r), do: %{r | phase: :awaiting_discard, exchange: nil}

  defp put_exchange(r, exchange), do: %{r | exchange: exchange}

  defp check_not_done(r, seat) do
    if MapSet.member?(r.exchange.done, seat), do: {:error, :exchange_done}, else: :ok
  end

  defp duplicate_tile(r, seat, tile_id) do
    hand = r.hands[seat]

    case Enum.find(hand, &(&1.id == tile_id)) do
      nil ->
        {:error, :card_not_in_hand}

      tile ->
        if Enum.any?(hand, &Card.twin?(&1, tile)),
          do: {:ok, tile},
          else: {:error, :not_a_duplicate}
    end
  end

  # A pair may back only one offer or response at a time.
  defp check_uncommitted(r, seat, tile, replacing_offer \\ nil) do
    committed =
      Enum.flat_map(r.exchange.offers, fn {id, offer} ->
        own = if offer.seat == seat, do: [offer.tile], else: []

        response =
          if id != replacing_offer and offer.responses[seat],
            do: [offer.responses[seat]],
            else: []

        own ++ response
      end)

    if Enum.any?(committed, &(&1.id == tile.id or Card.twin?(&1, tile))),
      do: {:error, :duplicate_already_offered},
      else: :ok
  end

  defp find_offer(r, id) do
    case r.exchange.offers[id] do
      nil -> {:error, :offer_not_found}
      offer -> {:ok, offer}
    end
  end

  # After a swap, drop offers and responses whose tile is no longer a duplicate in hand.
  defp prune_offers(offers, r) do
    still_duplicate? = fn seat, tile ->
      hand = r.hands[seat]
      in_hand?(hand, tile.id) and Enum.any?(hand, &Card.twin?(&1, tile))
    end

    offers
    |> Enum.filter(fn {_, o} -> still_duplicate?.(o.seat, o.tile) end)
    |> Map.new(fn {id, o} ->
      {id, %{o | responses: Map.filter(o.responses, fn {s, t} -> still_duplicate?.(s, t) end)}}
    end)
  end

  ## ---- Turn internals ----

  defp draw_stock(%__MODULE__{stock: []} = r, _seat) do
    r = finish(r, nil, false)
    {:ok, r, [%{type: :round_finished, result: r.result}]}
  end

  defp draw_stock(%__MODULE__{stock: [card | rest]} = r, seat) do
    r = %{
      r
      | stock: rest,
        hands: Map.update!(r.hands, seat, &(&1 ++ [card])),
        phase: :awaiting_discard,
        turn: %{@new_turn | small_hand: length(r.hands[seat]) <= 3}
    }

    {:ok, r, [%{type: :drew_stock, seat: seat}]}
  end

  # Only the last tile, unless the player has opened and holds at least 4 tiles.
  defp discard_index(r, seat, tile_id, held) do
    index = Enum.find_index(r.discard, &(&1.id == tile_id))
    last = length(r.discard) - 1

    cond do
      index == nil -> {:error, :card_not_found}
      tile_id == r.blocked_discard -> {:error, :discard_blocked}
      index != last and not (r.opened[seat] and held >= 4) -> {:error, :only_last_discard}
      true -> {:ok, index}
    end
  end

  defp lay_down(r, seat, groups) do
    with true <- groups != [] || {:error, :invalid_meld},
         {:ok, groups, hand} <- take_groups(r.hands[seat], groups),
         {:ok, melds} <- build_melds(groups, r.rules.max_jokers_per_meld),
         :ok <- check_opening(r, seat, melds),
         :ok <- check_hand_left(hand) do
      {melds, next_id} =
        Enum.map_reduce(melds, r.next_meld_id, fn m, id ->
          {%{m | id: id, owner: seat}, id + 1}
        end)

      laid_by = for(m <- melds, c <- m.cards, into: r.laid_by, do: {c.id, seat})
      opening? = not r.opened[seat]

      r = %{
        r
        | hands: Map.put(r.hands, seat, hand),
          melds: r.melds ++ melds,
          next_meld_id: next_id,
          laid_by: laid_by,
          opened: Map.put(r.opened, seat, true),
          turn: %{r.turn | opened_now: r.turn.opened_now or opening?}
      }

      {:ok, r, [%{type: :laid_down, seat: seat, melds: Enum.map(melds, &Meld.to_map/1)}]}
    end
  end

  defp apply_additions(r, _seat, []), do: {:ok, r, []}

  defp apply_additions(r, seat, additions) do
    with :ok <- check_can_touch_table(r, seat) do
      Enum.reduce_while(additions, {:ok, r, []}, fn
        {meld_id, ids}, {:ok, r, events} when is_list(ids) ->
          case add_to_meld(r, seat, meld_id, ids) do
            {:ok, r, more} -> {:cont, {:ok, r, events ++ more}}
            error -> {:halt, error}
          end

        _, _ ->
          {:halt, {:error, :invalid_action}}
      end)
    end
  end

  defp add_to_meld(r, seat, meld_id, ids) do
    with {:ok, meld} <- find_meld(r, meld_id),
         {:ok, [cards], hand} <- take_groups(r.hands[seat], [ids]),
         true <- cards != [] || {:error, :invalid_meld},
         :ok <-
           if(meld.owner != seat and Enum.any?(cards, &Card.joker?/1),
             do: {:error, :joker_on_others_meld},
             else: :ok
           ),
         {:ok, meld} <- Meld.add(meld, cards, r.rules.max_jokers_per_meld),
         :ok <- check_hand_left(hand) do
      r = %{
        r
        | hands: Map.put(r.hands, seat, hand),
          melds: replace_meld(r.melds, meld),
          laid_by: for(c <- cards, into: r.laid_by, do: {c.id, seat})
      }

      {:ok, r, [%{type: :added_to_meld, seat: seat, meld: Meld.to_map(meld)}]}
    end
  end

  defp do_discard(r, seat, card_id) do
    with {:ok, card, hand} <- take_from_hand(r.hands[seat], card_id) do
      first_discard? = r.discard == [] and r.blocked_discard == nil

      r = %{
        r
        | hands: Map.put(r.hands, seat, hand),
          discard: r.discard ++ [card],
          blocked_discard: if(first_discard?, do: card.id, else: r.blocked_discard),
          turns_taken: Map.update!(r.turns_taken, seat, &(&1 + 1))
      }

      event = %{type: :discarded, seat: seat, card: Card.to_map(card)}

      if hand == [] do
        # Closing with a joker or a 1 doubles the closer's score.
        r = finish(r, seat, Card.joker?(card) or card.rank == 1)
        {:ok, r, [event, %{type: :round_finished, result: r.result}]}
      else
        # Holding 3 or fewer tiles is announced automatically.
        {r, announce} =
          if length(hand) <= 3 and seat not in r.last_tiles,
            do:
              {%{r | last_tiles: [seat | r.last_tiles]},
               [%{type: :last_tiles, seat: seat, count: length(hand)}]},
            else: {r, []}

        next = rem(seat + 1, r.seats)
        r = %{r | current: next, phase: :awaiting_draw, turn: @new_turn}
        {:ok, r, [event | announce] ++ [%{type: :turn, seat: next}]}
      end
    end
  end

  defp finish(r, closer, double_close) do
    # Opened and closed on the same turn.
    on_board? = closer != nil and r.turn.opened_now

    laid =
      for meld <- r.melds,
          {card, value} <- Meld.tile_values(meld, Rules.joker_penalty(), r.reused_jokers),
          reduce: %{} do
        acc -> Map.update(acc, r.laid_by[card.id], value, &(&1 + value))
      end

    breakdown =
      Map.new(0..(r.seats - 1), fn seat ->
        laid_points = Map.get(laid, seat, 0)

        # A player who never opened pays a flat penalty instead of counting their hand.
        hand_points =
          if r.opened[seat],
            do:
              r.hands[seat] |> Enum.map(&Card.hand_value(&1, Rules.joker_penalty())) |> Enum.sum(),
            else: r.rules.not_opened_penalty

        on_board = on_board? and seat == closer

        {laid_points, closing} =
          cond do
            on_board and r.rules.closed_on_board_add_hand ->
              {laid_points, r.rules.closed_on_board_bonus}

            on_board ->
              {0, r.rules.closed_on_board_bonus}

            seat == closer ->
              {laid_points, r.rules.closing_bonus}

            true ->
              {laid_points, 0}
          end

        atu = if seat in r.atu_announced, do: Rules.atu_bonus(), else: 0
        sum = laid_points - hand_points + closing + atu
        multiplier = r.multiplier * if(seat == closer and double_close, do: 2, else: 1)

        {seat,
         %{
           laid: laid_points,
           hand: hand_points,
           opened: r.opened[seat],
           closed_on_board: on_board,
           closing: closing,
           atu: atu,
           multiplier: multiplier,
           total: sum * multiplier
         }}
      end)

    result = %{
      winner: closer,
      double_close: double_close,
      closed_on_board: on_board?,
      atu_multiplier: r.multiplier,
      scores: Map.new(breakdown, fn {seat, b} -> {seat, b.total} end),
      breakdown: breakdown,
      hands: Map.new(r.hands, fn {seat, hand} -> {seat, Enum.map(hand, &Card.to_map/1)} end)
    }

    %{r | phase: :finished, result: result}
  end

  ## ---- Checks ----

  defp check_not_first_turn(r, seat) do
    if r.turns_taken[seat] == 0, do: {:error, :first_turn}, else: :ok
  end

  # Adding to or swapping in table melds needs an opened player, and not on the opening turn.
  defp check_can_touch_table(r, seat) do
    cond do
      not r.opened[seat] -> {:error, :not_opened}
      r.turn.opened_now -> {:error, :opening_turn}
      true -> :ok
    end
  end

  defp check_opening(r, seat, melds) do
    points = melds |> Enum.map(&Meld.points/1) |> Enum.sum()
    has = fn type -> Enum.any?(melds, &(&1.type == type)) end

    cond do
      r.opened[seat] -> :ok
      Enum.any?(melds, &(&1.type == :set and &1.rank == 1)) -> :ok
      points < r.rules.opening_min_points -> {:error, :opening_too_low}
      not (has.(:run) and has.(:set)) -> {:error, :opening_needs_run_and_set}
      true -> :ok
    end
  end

  # With 3 or fewer tiles at the start of the turn, no new melds; only additions.
  defp check_not_small_hand(r) do
    if r.turn.small_hand, do: {:error, :must_add_to_melds}, else: :ok
  end

  # A player must always keep a tile to discard; going out happens only by discarding.
  defp check_hand_left([]), do: {:error, :must_keep_card_to_discard}
  defp check_hand_left(_), do: :ok

  ## ---- Helpers ----

  defp build_melds(groups, max_jokers) do
    Enum.reduce_while(groups, {:ok, []}, fn cards, {:ok, acc} ->
      case Meld.build(cards, max_jokers) do
        {:ok, meld} -> {:cont, {:ok, acc ++ [meld]}}
        error -> {:halt, error}
      end
    end)
  end

  # Removes each group of tile ids from the hand. Ids must be distinct and held.
  defp take_groups(hand, groups) do
    ids = if Enum.all?(groups, &is_list/1), do: List.flatten(groups), else: nil

    cond do
      ids == nil ->
        {:error, :invalid_action}

      length(Enum.uniq(ids)) != length(ids) ->
        {:error, :duplicate_cards}

      not Enum.all?(ids, &in_hand?(hand, &1)) ->
        {:error, :card_not_in_hand}

      true ->
        by_id = Map.new(hand, &{&1.id, &1})
        cards = Enum.map(groups, fn group -> Enum.map(group, &Map.fetch!(by_id, &1)) end)
        id_set = MapSet.new(ids)
        {:ok, cards, Enum.reject(hand, &MapSet.member?(id_set, &1.id))}
    end
  end

  defp take_from_hand(hand, id) do
    case Enum.split_with(hand, &(&1.id == id)) do
      {[card], rest} -> {:ok, card, rest}
      _ -> {:error, :card_not_in_hand}
    end
  end

  defp in_hand?(_hand, nil), do: false
  defp in_hand?(hand, id), do: Enum.any?(hand, &(&1.id == id))

  defp find_meld(r, id) do
    case Enum.find(r.melds, &(&1.id == id)) do
      nil -> {:error, :meld_not_found}
      meld -> {:ok, meld}
    end
  end

  defp replace_meld(melds, meld), do: Enum.map(melds, &if(&1.id == meld.id, do: meld, else: &1))
end
