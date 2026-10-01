defmodule Remybun.Engine.Deck do
  @moduledoc """
  Builds the card set for a game: two standard 52-card decks plus jokers.
  """

  alias Remybun.Engine.Card

  @doc "Unshuffled deck: ids 0..103 are regular cards, 104.. are jokers."
  def new(jokers \\ 4) do
    regular =
      for copy <- 0..1, {suit, s} <- Enum.with_index(Card.suits()), rank <- 1..13 do
        Card.new(copy * 52 + s * 13 + rank - 1, rank, suit)
      end

    regular ++ Enum.map(Range.new(104, 104 + jokers - 1, 1), &Card.joker/1)
  end

  def shuffled(jokers \\ 4), do: Enum.shuffle(new(jokers))
end
