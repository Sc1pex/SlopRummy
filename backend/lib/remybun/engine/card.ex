defmodule Remybun.Engine.Card do
  @moduledoc """
  A playing card. Jokers have `rank: nil` and `suit: nil`.

  Ranks are integers 1..13 (1 = Ace, 11 = Jack, 12 = Queen, 13 = King).
  Every card in a game has a unique `id`, since the deck contains two copies of each card.
  """

  @suits [:clubs, :diamonds, :hearts, :spades]

  @enforce_keys [:id]
  defstruct [:id, :rank, :suit]

  @type suit :: :clubs | :diamonds | :hearts | :spades
  @type t :: %__MODULE__{id: non_neg_integer(), rank: 1..13 | nil, suit: suit() | nil}

  def suits, do: @suits

  def new(id, rank, suit) when rank in 1..13 and suit in @suits,
    do: %__MODULE__{id: id, rank: rank, suit: suit}

  def joker(id), do: %__MODULE__{id: id}

  def joker?(%__MODULE__{rank: nil}), do: true
  def joker?(%__MODULE__{}), do: false

  @doc """
  Penalty value of a card held in hand: Ace 11, face cards 10, others face value,
  jokers `joker_value`.
  """
  def hand_value(card, joker_value)
  def hand_value(%__MODULE__{rank: nil}, joker_value), do: joker_value
  def hand_value(%__MODULE__{rank: 1}, _), do: 11
  def hand_value(%__MODULE__{rank: rank}, _) when rank >= 11, do: 10
  def hand_value(%__MODULE__{rank: rank}, _), do: rank

  @doc """
  Value of a meld position (rank 1..14, where 1 is a low Ace and 14 a high Ace).
  """
  def position_value(1), do: 1
  def position_value(14), do: 11
  def position_value(rank) when rank >= 11, do: 10
  def position_value(rank), do: rank

  def to_map(%__MODULE__{rank: nil, id: id}), do: %{id: id, joker: true}
  def to_map(%__MODULE__{} = c), do: %{id: c.id, rank: c.rank, suit: c.suit, joker: false}
end
