defmodule Remybun.Engine.View do
  @moduledoc """
  Projects a match into what a single seat is allowed to see.

  Only the viewer's own hand is included; other hands are reduced to tile counts.
  The stock is a count only. During the duplicate exchange other players' offers show
  only their tier; the offered and answered tiles are visible to their owners only.
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
    own_turn? = seat == round.current and round.phase in [:awaiting_draw, :awaiting_discard]

    %{
      phase: round.phase,
      current: round.current,
      starting_seat: round.starting_seat,
      stock_count: length(round.stock),
      discard: Enum.map(round.discard, &Card.to_map/1),
      blocked_discard: round.blocked_discard,
      atu: Card.to_map(round.atu),
      atu_multiplier: round.multiplier,
      atu_announced: round.atu_announced,
      atu_taken: round.atu_taken,
      can_announce_atu:
        round.phase == :exchange and seat in round.atu_holders and seat not in round.atu_announced,
      last_tiles: round.last_tiles,
      melds: Enum.map(round.melds, &Meld.to_map/1),
      opened: round.opened,
      first_turn: Map.new(round.turns_taken, fn {s, n} -> {s, n == 0} end),
      hand_counts: Map.new(round.hands, fn {s, hand} -> {s, length(hand)} end),
      hand: if(seat != nil, do: Enum.map(Map.get(round.hands, seat, []), &Card.to_map/1)),
      turn: if(own_turn?, do: round.turn),
      exchange: exchange_view(round.exchange, seat),
      result: round.result
    }
  end

  defp exchange_view(nil, _seat), do: nil

  defp exchange_view(exchange, seat) do
    offers =
      exchange.offers
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.map(fn offer ->
        mine? = offer.seat == seat

        %{
          id: offer.id,
          seat: offer.seat,
          tier: offer.tier,
          tile: if(mine?, do: Card.to_map(offer.tile)),
          # The offerer sees every answer's tier; others only see their own answer.
          responses:
            for {s, tile} <- Enum.sort(offer.responses), mine? or s == seat do
              %{seat: s, tier: Card.tier(tile), tile: if(s == seat, do: Card.to_map(tile))}
            end,
          response_count: map_size(offer.responses)
        }
      end)

    %{
      offers: offers,
      done: exchange.done |> MapSet.to_list() |> Enum.sort(),
      can_refuse: seat != nil and seat in exchange.can_refuse
    }
  end
end
