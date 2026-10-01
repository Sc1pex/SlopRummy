defmodule Remybun.Engine.Meld do
  @moduledoc """
  Melds on the table.

    * `:set` — 3 or 4 cards of the same `rank`, all different colors.
    * `:run` — 3+ consecutive cards of one `color`. Cards are stored in order and the
      first card sits at position `start`. Positions go 1..14: 1 is a 1 before 2,
      14 a 1 after 13. No wrap-around.

  Jokers keep the position they were placed at; adding cards to a run never moves
  an existing joker. A meld with one joker needs at least two real tiles; a meld with two
  jokers needs at least four real tiles and the jokers may not be next to each other
  (so sets, at most 4 tiles, hold at most one joker).
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
  Takes a joker back by putting the real tiles it stands for in its place.

    * In a run, one tile: the one at the joker's position.
    * In a set of 4 (3 real + joker), one tile of the missing color.
    * In a set of 3 (2 real + joker), both missing colors must be added (two tiles).

  Returns the updated meld and the freed joker.
  """
  def swap_joker(%__MODULE__{} = meld, cards) when is_list(cards) do
    cond do
      cards == [] or Enum.any?(cards, &Card.joker?/1) -> {:error, :invalid_swap}
      meld.type == :run -> swap_in_run(meld, cards)
      true -> swap_in_set(meld, cards)
    end
  end

  defp swap_in_run(meld, [card]) do
    index =
      meld.cards
      |> Enum.with_index(meld.start)
      |> Enum.find_value(fn {c, pos} ->
        Card.joker?(c) and card.color == meld.color and rank_at(pos) == card.rank and
          pos - meld.start
      end)

    case index do
      nil -> {:error, :invalid_swap}
      i -> {:ok, %{meld | cards: List.replace_at(meld.cards, i, card)}, Enum.at(meld.cards, i)}
    end
  end

  defp swap_in_run(_meld, _cards), do: {:error, :invalid_swap}

  defp swap_in_set(meld, cards) do
    {jokers, reals} = Enum.split_with(meld.cards, &Card.joker?/1)
    missing = Card.colors() -- Enum.map(reals, & &1.color)
    colors = Enum.map(cards, & &1.color)
    needed = if length(meld.cards) == 3, do: 2, else: 1

    valid? =
      jokers != [] and length(cards) == needed and Enum.all?(cards, &(&1.rank == meld.rank)) and
        Enum.uniq(colors) == colors and Enum.all?(colors, &(&1 in missing))

    if valid?,
      do: {:ok, %{meld | cards: reals ++ cards}, hd(jokers)},
      else: {:error, :invalid_swap}
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
  End-of-round value of each tile in the meld: `Card.rank_value/1` of its number, and
  `joker_value` for a joker (unlike the opening total, where a joker counts as its tile).
  A joker that was taken back and laid again (in `reused`) is worth 0.
  """
  def tile_values(%__MODULE__{cards: cards}, joker_value, reused \\ MapSet.new()) do
    Enum.map(cards, fn card ->
      value = if MapSet.member?(reused, card.id), do: 0, else: Card.hand_value(card, joker_value)
      {card, value}
    end)
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
         true <- reals != [] and length(jokers) <= max_jokers and jokers_ok?(cards),
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

        if length(cards) >= 3 and joker_count <= max_jokers and jokers_ok?(cards) do
          %__MODULE__{type: :run, color: color, start: start, cards: cards}
        end
      else
        _ -> nil
      end
    end
  end

  defp build_run(_color, _fixed, _jokers, _max), do: nil

  defp extend(slots, []), do: {:ok, slots}

  # Prefer the end that keeps jokers apart: high first, then low.
  defp extend(slots, [joker | rest]) do
    {low, high} = slots |> Map.keys() |> Enum.min_max()
    beside_joker? = fn pos -> Card.joker?(Map.fetch!(slots, pos)) end

    cond do
      high < 14 and not beside_joker?.(high) -> extend(Map.put(slots, high + 1, joker), rest)
      low > 1 and not beside_joker?.(low) -> extend(Map.put(slots, low - 1, joker), rest)
      high < 14 -> extend(Map.put(slots, high + 1, joker), rest)
      low > 1 -> extend(Map.put(slots, low - 1, joker), rest)
      true -> :error
    end
  end

  # One joker needs two real tiles; two jokers need four real tiles and may not touch.
  defp jokers_ok?(cards) do
    jokers = Enum.count(cards, &Card.joker?/1)
    reals = length(cards) - jokers

    case jokers do
      0 -> true
      1 -> reals >= 2
      2 -> reals >= 4 and not adjacent_jokers?(cards)
      _ -> false
    end
  end

  defp adjacent_jokers?(cards) do
    cards
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [a, b] -> Card.joker?(a) and Card.joker?(b) end)
  end

  defp run_slots(%__MODULE__{start: start, cards: cards}) do
    cards |> Enum.with_index(start) |> Map.new(fn {card, pos} -> {pos, card} end)
  end

  defp rank_at(14), do: 1
  defp rank_at(pos), do: pos
end
