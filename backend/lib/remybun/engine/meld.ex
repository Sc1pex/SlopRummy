defmodule Remybun.Engine.Meld do
  @moduledoc """
  Melds on the table.

    * `:set` — 3 or 4 cards of the same `rank`, all different colors.
    * `:run` — 3+ consecutive cards of one `color`. Cards are stored in order and the
      first card sits at position `start`. Positions go 1..14: 1 is a 1 before 2,
      14 a 1 after 13. No wrap-around.

  Jokers keep the position they were placed at; adding cards to a run never moves
  an existing joker.
  """

  alias Remybun.Engine.Card

  defstruct [:id, :owner, :type, :rank, :color, :start, cards: []]

  @type t :: %__MODULE__{}

  @doc """
  Builds a meld from a list of cards, picking the valid interpretation worth the
  most points.
  """
  def build(cards, max_jokers) do
    candidates = run_candidates(cards, max_jokers) ++ set_candidates(cards, max_jokers)

    case candidates do
      [] -> {:error, :invalid_meld}
      _ -> {:ok, Enum.max_by(candidates, &points/1)}
    end
  end

  @doc "Adds cards to an existing meld."
  def add(%__MODULE__{type: :set} = meld, cards, max_jokers) do
    case build_set(meld.cards ++ cards, max_jokers) do
      %__MODULE__{} = set -> {:ok, %{set | id: meld.id, owner: meld.owner}}
      nil -> {:error, :invalid_meld}
    end
  end

  def add(%__MODULE__{type: :run} = meld, cards, max_jokers) do
    {jokers, reals} = Enum.split_with(cards, &Card.joker?/1)
    fixed = run_slots(meld)

    candidates =
      if Enum.all?(reals, &(&1.color == meld.color)) do
        for placement <- placements(reals),
            map_size(Map.take(fixed, Map.keys(placement))) == 0,
            run <- [build_run(meld.color, Map.merge(fixed, placement), jokers, max_jokers)],
            run != nil,
            do: %{run | id: meld.id, owner: meld.owner}
      else
        []
      end

    case candidates do
      [] -> {:error, :invalid_meld}
      _ -> {:ok, Enum.max_by(candidates, &points/1)}
    end
  end

  @doc """
  Replaces a joker in the meld with `card`, the real card the joker stands for.
  Returns the updated meld and the freed joker.
  """
  def swap_joker(%__MODULE__{} = meld, %Card{} = card) do
    if Card.joker?(card) do
      {:error, :invalid_swap}
    else
      index =
        meld.cards
        |> Enum.with_index()
        |> Enum.find_value(fn {c, i} -> Card.joker?(c) and can_replace?(meld, i, card) and i end)

      case index do
        nil ->
          {:error, :invalid_swap}

        i ->
          joker = Enum.at(meld.cards, i)
          {:ok, %{meld | cards: List.replace_at(meld.cards, i, card)}, joker}
      end
    end
  end

  defp can_replace?(%__MODULE__{type: :run} = meld, i, card) do
    card.color == meld.color and rank_at(meld.start + i) == card.rank
  end

  defp can_replace?(%__MODULE__{type: :set} = meld, _i, card) do
    card.rank == meld.rank and card.color not in Enum.map(meld.cards, & &1.color)
  end

  @doc """
  Opening value of the meld (see `Card.position_value/1`; a set of 1s is 25 each).
  Jokers count as the tile they stand for.
  """
  def points(%__MODULE__{type: :run, start: start, cards: cards}) do
    start..(start + length(cards) - 1)//1 |> Enum.map(&Card.position_value/1) |> Enum.sum()
  end

  def points(%__MODULE__{type: :set, rank: 1, cards: cards}), do: 25 * length(cards)

  def points(%__MODULE__{type: :set, rank: rank, cards: cards}),
    do: Card.rank_value(rank) * length(cards)

  @doc """
  End-of-round value of each tile in the meld (`Card.rank_value/1` of the number it shows
  or, for a joker, the number it stands for).
  """
  def tile_values(%__MODULE__{type: :run, start: start, cards: cards}) do
    cards
    |> Enum.with_index(start)
    |> Enum.map(fn {card, pos} -> {card, Card.rank_value(rank_at(pos))} end)
  end

  def tile_values(%__MODULE__{type: :set, rank: rank, cards: cards}) do
    Enum.map(cards, &{&1, Card.rank_value(rank)})
  end

  @doc "JSON-friendly map. Jokers include an `as` key describing what they stand for."
  def to_map(%__MODULE__{} = meld) do
    cards =
      meld.cards
      |> Enum.with_index()
      |> Enum.map(fn {card, i} ->
        map = Card.to_map(card)

        cond do
          not Card.joker?(card) ->
            map

          meld.type == :run ->
            Map.put(map, :as, %{rank: rank_at(meld.start + i), color: meld.color})

          true ->
            Map.put(map, :as, %{rank: meld.rank})
        end
      end)

    %{
      id: meld.id,
      owner: meld.owner,
      type: meld.type,
      rank: meld.rank,
      color: meld.color,
      cards: cards,
      points: points(meld)
    }
  end

  ## Sets

  defp set_candidates(cards, max_jokers) do
    case build_set(cards, max_jokers) do
      nil -> []
      set -> [set]
    end
  end

  defp build_set(cards, max_jokers) do
    {jokers, reals} = Enum.split_with(cards, &Card.joker?/1)
    colors = Enum.map(reals, & &1.color)

    with true <- length(cards) in 3..4,
         true <- reals != [] and length(jokers) <= max_jokers,
         [rank] <- reals |> Enum.map(& &1.rank) |> Enum.uniq(),
         true <- Enum.uniq(colors) == colors do
      # Real cards first, jokers last.
      %__MODULE__{type: :set, rank: rank, cards: reals ++ jokers}
    else
      _ -> nil
    end
  end

  ## Runs

  defp run_candidates(cards, max_jokers) do
    {jokers, reals} = Enum.split_with(cards, &Card.joker?/1)

    case Enum.uniq(Enum.map(reals, & &1.color)) do
      [color] ->
        for placement <- placements(reals),
            run <- [build_run(color, placement, jokers, max_jokers)],
            run != nil,
            do: run

      _ ->
        []
    end
  end

  # All ways to assign positions to real cards (Aces may be 1 or 14).
  # Placements where two cards share a position are dropped.
  defp placements(reals) do
    reals
    |> Enum.reduce([%{}], fn card, acc ->
      positions = if card.rank == 1, do: [1, 14], else: [card.rank]

      for map <- acc, pos <- positions, not Map.has_key?(map, pos), do: Map.put(map, pos, card)
    end)
  end

  # `fixed` maps positions to cards; `free_jokers` fill gaps, then extend high, then low.
  defp build_run(color, fixed, free_jokers, max_jokers) when map_size(fixed) > 0 do
    {low, high} = fixed |> Map.keys() |> Enum.min_max()
    gaps = for pos <- low..high, not Map.has_key?(fixed, pos), do: pos

    if length(gaps) > length(free_jokers) do
      nil
    else
      {gap_jokers, extra} = Enum.split(free_jokers, length(gaps))
      slots = Map.merge(fixed, Map.new(Enum.zip(gaps, gap_jokers)))

      with {:ok, slots} <- extend(slots, extra) do
        {start, _} = slots |> Map.keys() |> Enum.min_max()
        cards = slots |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))
        joker_count = Enum.count(cards, &Card.joker?/1)

        if length(cards) >= 3 and joker_count <= max_jokers and joker_count < length(cards) do
          %__MODULE__{type: :run, color: color, start: start, cards: cards}
        end
      else
        _ -> nil
      end
    end
  end

  defp build_run(_color, _fixed, _jokers, _max), do: nil

  defp extend(slots, []), do: {:ok, slots}

  defp extend(slots, [joker | rest]) do
    {low, high} = slots |> Map.keys() |> Enum.min_max()

    cond do
      high < 14 -> extend(Map.put(slots, high + 1, joker), rest)
      low > 1 -> extend(Map.put(slots, low - 1, joker), rest)
      true -> :error
    end
  end

  defp run_slots(%__MODULE__{start: start, cards: cards}) do
    cards |> Enum.with_index(start) |> Map.new(fn {card, pos} -> {pos, card} end)
  end

  defp rank_at(14), do: 1
  defp rank_at(pos), do: pos
end
