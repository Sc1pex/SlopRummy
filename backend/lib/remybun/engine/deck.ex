defmodule Remybun.Engine.Deck do
  @moduledoc """
  Builds the tile set: numbers 1..13 in four colors, two copies of each, plus jokers.
  """

  alias Remybun.Engine.Card

  @doc "Unshuffled set: ids 0..103 are numbered tiles, 104.. are jokers."
  def new(jokers \\ 2) do
    regular =
      for copy <- 0..1, {color, s} <- Enum.with_index(Card.colors()), rank <- 1..13 do
        Card.new(copy * 52 + s * 13 + rank - 1, rank, color)
      end

    regular ++ Enum.map(Range.new(104, 104 + jokers - 1, 1), &Card.joker/1)
  end

  def shuffled(jokers \\ 2), do: Enum.shuffle(new(jokers))
end
