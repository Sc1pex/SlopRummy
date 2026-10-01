defmodule Remybun.Engine.View do
  @moduledoc """
  Projects a match into what a single seat is allowed to see.

  Only the viewer's own hand is included; other hands are reduced to card counts.
  The stock is a count only, and only the top discard is visible.
  Pass `nil` as the seat for spectators.
  """

  alias Remybun.Engine.{Card, Match, Meld}

  def for_seat(%Match{} = m, seat) do
    %{
      phase: m.phase,
      rounds_played: m.rounds_played,
      totals: m.totals,
      winners: m.winners,
      last_result: List.last(m.history),
      round: round_view(m.round, seat)
    }
  end

  defp round_view(nil, _seat), do: nil

  defp round_view(round, seat) do
    own_turn? = seat == round.current and round.phase != :finished

    %{
      phase: round.phase,
      current: round.current,
      starting_seat: round.starting_seat,
      stock_count: length(round.stock),
      discard_top: round.discard |> List.first() |> then(&(&1 && Card.to_map(&1))),
      discard_count: length(round.discard),
      melds: Enum.map(round.melds, &Meld.to_map/1),
      opened: round.opened,
      hand_counts: Map.new(round.hands, fn {s, hand} -> {s, length(hand)} end),
      hand: if(seat != nil, do: Enum.map(Map.get(round.hands, seat, []), &Card.to_map/1)),
      must_use: if(own_turn?, do: Map.take(round.turn, [:taken_discard, :pending_joker])),
      result: round.result
    }
  end
end
