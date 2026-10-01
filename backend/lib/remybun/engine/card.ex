defmodule Remybun.Engine.Card do
  @moduledoc """
  A Remi tile. Numbers (`rank`) go 1..13 in four colors; jokers have `rank: nil`
  and `color: nil`. Every tile in a game has a unique `id`, since the set contains
  two copies of each tile.
  """

  @colors [:black, :yellow, :red, :blue]

  @enforce_keys [:id]
  defstruct [:id, :rank, :color]

  @type color :: :black | :yellow | :red | :blue
  @type t :: %__MODULE__{id: non_neg_integer(), rank: 1..13 | nil, color: color() | nil}

  def colors, do: @colors

  def new(id, rank, color) when rank in 1..13 and color in @colors,
    do: %__MODULE__{id: id, rank: rank, color: color}

  def joker(id), do: %__MODULE__{id: id}

  def joker?(%__MODULE__{rank: nil}), do: true
  def joker?(%__MODULE__{}), do: false

  @doc """
  Penalty value of a tile left in hand: 2–9 are 5, 10–13 are 10, a 1 is 25,
  a joker is `joker_value`.
  """
  def hand_value(tile, joker_value)
  def hand_value(%__MODULE__{rank: nil}, joker_value), do: joker_value
  def hand_value(%__MODULE__{rank: 1}, _), do: 25
  def hand_value(%__MODULE__{rank: rank}, _) when rank >= 10, do: 10
  def hand_value(%__MODULE__{}, _), do: 5

  @doc """
  Value of a meld position, used for the opening total. Positions go 1..14:
  1 is a 1 before 2, 14 is a 1 after 13 (worth 25, like a 1 in a set).
  Other tiles are worth their number.
  """
  def position_value(14), do: 25
  def position_value(rank), do: rank

  def to_map(%__MODULE__{rank: nil, id: id}), do: %{id: id, joker: true}
  def to_map(%__MODULE__{} = c), do: %{id: c.id, rank: c.rank, color: c.color, joker: false}
end
