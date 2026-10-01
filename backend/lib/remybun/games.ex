defmodule Remybun.Games do
  @moduledoc """
  Persistence of played games: participants, an append-only event log and results.
  """

  import Ecto.Query

  alias Remybun.Repo
  alias Remybun.Games.{Game, GameEvent, GamePlayer}

  @doc "Records the start of a game. `user_ids` are ordered by seat."
  def start_game(table_id, rules_map, user_ids) do
    Repo.transaction(fn ->
      game =
        Repo.insert!(%Game{
          table_id: table_id,
          rules: rules_map,
          started_at: DateTime.utc_now(:second)
        })

      players =
        user_ids
        |> Enum.with_index()
        |> Enum.map(fn {user_id, seat} -> %{game_id: game.id, user_id: user_id, seat: seat} end)

      Repo.insert_all(GamePlayer, players)
      game
    end)
  end

  @doc "Appends events. Each event is `{seq, map_with_type}`."
  def append_events(_game_id, []), do: :ok

  def append_events(game_id, events) do
    now = DateTime.utc_now()

    rows =
      Enum.map(events, fn {seq, event} ->
        payload = event |> Map.delete(:type) |> json_safe()

        %{
          game_id: game_id,
          seq: seq,
          type: to_string(event.type),
          payload: payload,
          inserted_at: now
        }
      end)

    Repo.insert_all(GameEvent, rows)
    :ok
  end

  @doc "Stores final scores (`%{seat => total}`) and the winning seat's user."
  def finish_game(game_id, totals, winner_user_id) do
    Repo.transaction(fn ->
      from(g in Game, where: g.id == ^game_id)
      |> Repo.update_all(
        set: [
          status: :finished,
          finished_at: DateTime.utc_now(:second),
          winner_id: winner_user_id
        ]
      )

      for {seat, total} <- totals do
        from(p in GamePlayer, where: p.game_id == ^game_id and p.seat == ^seat)
        |> Repo.update_all(set: [final_score: total])
      end
    end)

    :ok
  end

  def abandon_game(game_id) do
    from(g in Game, where: g.id == ^game_id and g.status == :playing)
    |> Repo.update_all(set: [status: :abandoned, finished_at: DateTime.utc_now(:second)])

    :ok
  end

  @doc "Recent games a user played in, newest first, with all players."
  def history(user_id, limit \\ 50) do
    from(g in Game,
      join: p in assoc(g, :players),
      where: p.user_id == ^user_id and g.status != :playing,
      order_by: [desc: g.started_at, desc: g.id],
      limit: ^limit,
      preload: [players: :user]
    )
    |> Repo.all()
  end

  def events(game_id) do
    from(e in GameEvent, where: e.game_id == ^game_id, order_by: e.seq) |> Repo.all()
  end

  # Ecto's :map type needs JSON-encodable values; tuples and structs are converted.
  defp json_safe(value), do: value |> Jason.encode!() |> Jason.decode!()
end
