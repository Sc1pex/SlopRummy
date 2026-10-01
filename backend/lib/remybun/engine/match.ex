defmodule Remybun.Engine.Match do
  @moduledoc """
  A match is a series of rounds with cumulative points (higher is better).

  Phases: `:between_rounds` (including before the first round) → `:playing` → … → `:finished`.
  The starting seat rotates every round. A refused deal goes back to `:between_rounds`
  without counting as a round, so the same seat starts the redeal.
  """

  alias Remybun.Engine.{Card, Round, Rules}

  defstruct [
    :rules,
    :seats,
    :round,
    phase: :between_rounds,
    rounds_played: 0,
    totals: %{},
    history: [],
    winners: []
  ]

  @type t :: %__MODULE__{}

  def new(%Rules{} = rules, seats) do
    %__MODULE__{rules: rules, seats: seats, totals: Map.new(0..(seats - 1), &{&1, 0})}
  end

  @doc "Deals the next round from a shuffled `deck`."
  def start_round(%__MODULE__{phase: :between_rounds} = m, deck) do
    starting = rem(m.rounds_played, m.seats)
    round = Round.new(m.rules, m.seats, starting, deck)

    event = %{
      type: :round_started,
      round: m.rounds_played + 1,
      starting_seat: starting,
      atu: Card.to_map(round.atu)
    }

    {:ok, %{m | round: round, phase: :playing}, [event]}
  end

  def start_round(%__MODULE__{}, _deck), do: {:error, :wrong_phase}

  def play(%__MODULE__{phase: :playing} = m, seat, action) do
    with {:ok, round, events} <- Round.play(m.round, seat, action) do
      after_round(%{m | round: round}, events)
    end
  end

  def play(%__MODULE__{}, _seat, _action), do: {:error, :no_round_in_progress}

  def auto_play(%__MODULE__{phase: :playing} = m) do
    with {:ok, round, events} <- Round.auto_play(m.round) do
      after_round(%{m | round: round}, events)
    end
  end

  def auto_play(%__MODULE__{} = m), do: {:ok, m, []}

  @doc "Seat whose turn it is, or nil (also nil during the duplicate exchange)."
  def current_seat(%__MODULE__{phase: :playing, round: %Round{phase: phase} = round})
      when phase in [:awaiting_draw, :awaiting_discard],
      do: round.current

  def current_seat(_), do: nil

  defp after_round(%__MODULE__{round: %Round{phase: :refused}} = m, events) do
    {:ok, %{m | phase: :between_rounds, round: nil}, events}
  end

  defp after_round(%__MODULE__{round: %Round{phase: :finished, result: result}} = m, events) do
    totals = Map.merge(m.totals, result.scores, fn _seat, a, b -> a + b end)
    m = %{m | totals: totals, rounds_played: m.rounds_played + 1, history: m.history ++ [result]}

    if match_over?(m) do
      max = totals |> Map.values() |> Enum.max()
      winners = for {seat, total} <- totals, total == max, do: seat
      m = %{m | phase: :finished, winners: Enum.sort(winners)}
      {:ok, m, events ++ [%{type: :match_finished, totals: totals, winners: m.winners}]}
    else
      {:ok, %{m | phase: :between_rounds}, events}
    end
  end

  defp after_round(m, events), do: {:ok, m, events}

  defp match_over?(%__MODULE__{rules: %Rules{match: :single}}), do: true
  defp match_over?(%__MODULE__{rules: %Rules{match: {:rounds, n}}} = m), do: m.rounds_played >= n

  defp match_over?(%__MODULE__{rules: %Rules{match: {:points_limit, n}}} = m),
    do: Enum.any?(m.totals, fn {_, total} -> total >= n end)
end
