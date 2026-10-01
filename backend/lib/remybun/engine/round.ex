defmodule Remybun.Engine.Round do
  @moduledoc """
  State machine for a single deal.

  Phases: `:awaiting_draw` → `:awaiting_discard` → (next seat) … → `:finished`.
  The starting seat is dealt one extra card and begins in `:awaiting_discard`.

  Actions (`play/3`):

    * `:draw_stock`
    * `:take_discard`
    * `:return_discard` — undo `:take_discard` before doing anything else that turn
    * `{:lay_down, [[card_id]]}`
    * `{:add_to_meld, meld_id, [card_id]}`
    * `{:swap_joker, meld_id, card_id}`
    * `{:discard, card_id}`

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
    hands: %{},
    stock: [],
    discard: [],
    melds: [],
    opened: %{},
    next_meld_id: 1,
    turn: %{taken_discard: nil, pending_joker: nil, acted: false}
  ]

  @type t :: %__MODULE__{}
  @type seat :: non_neg_integer()

  @new_turn %{taken_discard: nil, pending_joker: nil, acted: false}

  @doc "Deals a new round from `deck` (already shuffled)."
  def new(%Rules{} = rules, seats, starting_seat, deck) when starting_seat in 0..(seats - 1)//1 do
    order = Enum.map(0..(seats - 1), &rem(starting_seat + &1, seats))

    {hands, stock} =
      Enum.reduce(order, {%{}, deck}, fn seat, {hands, deck} ->
        count = if seat == starting_seat, do: rules.hand_size + 1, else: rules.hand_size
        {hand, rest} = Enum.split(deck, count)
        {Map.put(hands, seat, hand), rest}
      end)

    %__MODULE__{
      rules: rules,
      seats: seats,
      starting_seat: starting_seat,
      current: starting_seat,
      phase: :awaiting_discard,
      hands: hands,
      stock: stock,
      opened: Map.new(0..(seats - 1), &{&1, false})
    }
  end

  def play(%__MODULE__{phase: :finished}, _seat, _action), do: {:error, :round_finished}

  def play(%__MODULE__{current: current}, seat, _action) when seat != current,
    do: {:error, :not_your_turn}

  def play(%__MODULE__{phase: :awaiting_draw} = r, seat, :draw_stock), do: draw_stock(r, seat)

  def play(%__MODULE__{phase: :awaiting_draw, discard: []}, _seat, :take_discard),
    do: {:error, :discard_empty}

  def play(%__MODULE__{phase: :awaiting_draw, discard: [top | rest]} = r, seat, :take_discard) do
    taken = if r.rules.discard_pickup == :must_use, do: top.id

    r = %{
      r
      | discard: rest,
        hands: Map.update!(r.hands, seat, &(&1 ++ [top])),
        phase: :awaiting_discard,
        turn: %{@new_turn | taken_discard: taken}
    }

    {:ok, r, [%{type: :took_discard, seat: seat, card: Card.to_map(top)}]}
  end

  def play(%__MODULE__{phase: :awaiting_discard} = r, seat, :return_discard) do
    with id when is_integer(id) <- r.turn.taken_discard || {:error, :nothing_to_return},
         :ok <- if(r.turn.acted, do: {:error, :already_acted}, else: :ok),
         {:ok, card, hand} <- take_from_hand(r.hands[seat], id) do
      r = %{
        r
        | discard: [card | r.discard],
          hands: Map.put(r.hands, seat, hand),
          phase: :awaiting_draw,
          turn: @new_turn
      }

      {:ok, r, [%{type: :returned_discard, seat: seat, card: Card.to_map(card)}]}
    end
  end

  def play(%__MODULE__{phase: :awaiting_discard} = r, seat, {:lay_down, groups})
      when is_list(groups) do
    with true <- groups != [] || {:error, :invalid_meld},
         {:ok, groups, hand} <- take_groups(r.hands[seat], groups),
         {:ok, melds} <- build_melds(groups, r.rules.max_jokers_per_meld),
         :ok <- check_opening(r, seat, melds),
         :ok <- check_hand_left(hand) do
      {melds, next_id} =
        Enum.map_reduce(melds, r.next_meld_id, fn m, id ->
          {%{m | id: id, owner: seat}, id + 1}
        end)

      r = %{
        r
        | hands: Map.put(r.hands, seat, hand),
          melds: r.melds ++ melds,
          next_meld_id: next_id,
          opened: Map.put(r.opened, seat, true),
          turn: %{r.turn | acted: true}
      }

      {:ok, r, [%{type: :laid_down, seat: seat, melds: Enum.map(melds, &Meld.to_map/1)}]}
    end
  end

  def play(%__MODULE__{phase: :awaiting_discard} = r, seat, {:add_to_meld, meld_id, ids})
      when is_list(ids) do
    with :ok <- check_can_lay_off(r, seat),
         {:ok, meld} <- find_meld(r, meld_id),
         {:ok, [cards], hand} <- take_groups(r.hands[seat], [ids]),
         true <- cards != [] || {:error, :invalid_meld},
         {:ok, meld} <- Meld.add(meld, cards, r.rules.max_jokers_per_meld),
         :ok <- check_hand_left(hand) do
      r = %{
        r
        | hands: Map.put(r.hands, seat, hand),
          melds: replace_meld(r.melds, meld),
          turn: %{r.turn | acted: true}
      }

      {:ok, r, [%{type: :added_to_meld, seat: seat, meld: Meld.to_map(meld)}]}
    end
  end

  def play(%__MODULE__{phase: :awaiting_discard} = r, seat, {:swap_joker, meld_id, card_id}) do
    with true <- r.rules.joker_swap || {:error, :joker_swap_disabled},
         true <- r.opened[seat] || {:error, :not_opened},
         {:ok, meld} <- find_meld(r, meld_id),
         {:ok, card, hand} <- take_from_hand(r.hands[seat], card_id),
         {:ok, meld, joker} <- Meld.swap_joker(meld, card) do
      r = %{
        r
        | hands: Map.put(r.hands, seat, hand ++ [joker]),
          melds: replace_meld(r.melds, meld),
          turn: %{r.turn | acted: true, pending_joker: joker.id}
      }

      {:ok, r, [%{type: :swapped_joker, seat: seat, meld: Meld.to_map(meld)}]}
    end
  end

  def play(%__MODULE__{phase: :awaiting_discard} = r, seat, {:discard, card_id}) do
    hand = r.hands[seat]

    cond do
      in_hand?(hand, r.turn.taken_discard) -> {:error, :must_use_discard}
      in_hand?(hand, r.turn.pending_joker) -> {:error, :must_use_joker}
      true -> do_discard(r, seat, card_id)
    end
  end

  def play(%__MODULE__{}, _seat, action)
      when action in [:draw_stock, :take_discard, :return_discard] or
             (is_tuple(action) and
                elem(action, 0) in [:lay_down, :add_to_meld, :swap_joker, :discard]),
      do: {:error, :wrong_phase}

  def play(%__MODULE__{}, _seat, _action), do: {:error, :invalid_action}

  @doc """
  Plays the current seat's turn automatically (turn timeout / disconnected player):
  draws from the stock and discards, ignoring the pickup and joker obligations if needed.
  """
  def auto_play(%__MODULE__{phase: :finished} = r), do: {:ok, r, []}

  def auto_play(%__MODULE__{phase: :awaiting_draw, current: seat} = r) do
    with {:ok, r, events} <- draw_stock(r, seat),
         {:ok, r, more} <- auto_play(r) do
      {:ok, r, events ++ more}
    end
  end

  def auto_play(%__MODULE__{phase: :awaiting_discard, current: seat, turn: turn} = r) do
    hand = r.hands[seat]

    if in_hand?(hand, turn.taken_discard) and not turn.acted do
      {:ok, r, events} = play(r, seat, :return_discard)
      {:ok, r, more} = auto_play(r)
      {:ok, r, events ++ more}
    else
      card =
        Enum.find(hand, &(&1.id == turn.taken_discard)) ||
          hand
          |> Enum.reject(&Card.joker?/1)
          |> Enum.max_by(&Card.hand_value(&1, 0), fn -> nil end) ||
          hd(hand)

      do_discard(r, seat, card.id)
    end
  end

  @doc "Penalty points of a seat's hand at the end of the round (before multipliers)."
  def hand_penalty(%__MODULE__{} = r, seat) do
    if r.opened[seat] do
      r.hands[seat] |> Enum.map(&Card.hand_value(&1, r.rules.joker_penalty)) |> Enum.sum()
    else
      r.rules.not_opened_penalty
    end
  end

  ## Internals

  defp draw_stock(%__MODULE__{stock: []} = r, seat) do
    case {r.rules.stock_exhausted, r.discard} do
      {:reshuffle, [top | rest]} when rest != [] ->
        r = %{r | stock: Enum.shuffle(rest), discard: [top]}
        {:ok, r, events} = draw_stock(r, seat)
        {:ok, r, [%{type: :stock_reshuffled} | events]}

      _ ->
        r = finish(r, nil, false)
        {:ok, r, [%{type: :round_finished, result: r.result}]}
    end
  end

  defp draw_stock(%__MODULE__{stock: [card | rest]} = r, seat) do
    r = %{
      r
      | stock: rest,
        hands: Map.update!(r.hands, seat, &(&1 ++ [card])),
        phase: :awaiting_discard,
        turn: @new_turn
    }

    {:ok, r, [%{type: :drew_stock, seat: seat}]}
  end

  defp do_discard(r, seat, card_id) do
    with {:ok, card, hand} <- take_from_hand(r.hands[seat], card_id) do
      r = %{r | hands: Map.put(r.hands, seat, hand), discard: [card | r.discard]}
      event = %{type: :discarded, seat: seat, card: Card.to_map(card)}

      if hand == [] do
        r = finish(r, seat, Card.joker?(card))
        {:ok, r, [event, %{type: :round_finished, result: r.result}]}
      else
        next = rem(seat + 1, r.seats)
        r = %{r | current: next, phase: :awaiting_draw, turn: @new_turn}
        {:ok, r, [event, %{type: :turn, seat: next}]}
      end
    end
  end

  defp finish(r, winner, joker_close) do
    multiplier = if joker_close, do: r.rules.joker_close_multiplier, else: 1

    scores =
      Map.new(0..(r.seats - 1), fn
        ^winner -> {winner, 0}
        seat -> {seat, hand_penalty(r, seat) * multiplier}
      end)

    result = %{
      winner: winner,
      joker_close: joker_close,
      scores: scores,
      hands: Map.new(r.hands, fn {seat, hand} -> {seat, Enum.map(hand, &Card.to_map/1)} end)
    }

    %{r | phase: :finished, result: result}
  end

  defp check_opening(r, seat, melds) do
    points = melds |> Enum.map(&Meld.points/1) |> Enum.sum()

    if r.opened[seat] or points >= r.rules.opening_min_points,
      do: :ok,
      else: {:error, :opening_too_low}
  end

  defp check_can_lay_off(r, seat) do
    if r.opened[seat] or r.rules.lay_off_before_opening, do: :ok, else: {:error, :not_opened}
  end

  # A player must always keep a card to discard; going out happens only by discarding.
  defp check_hand_left([]), do: {:error, :must_keep_card_to_discard}
  defp check_hand_left(_), do: :ok

  defp build_melds(groups, max_jokers) do
    Enum.reduce_while(groups, {:ok, []}, fn cards, {:ok, acc} ->
      case Meld.build(cards, max_jokers) do
        {:ok, meld} -> {:cont, {:ok, acc ++ [meld]}}
        error -> {:halt, error}
      end
    end)
  end

  # Removes each group of card ids from the hand. Ids must be distinct and held.
  defp take_groups(hand, groups) do
    ids = List.flatten(groups)

    cond do
      not Enum.all?(groups, &is_list/1) ->
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
