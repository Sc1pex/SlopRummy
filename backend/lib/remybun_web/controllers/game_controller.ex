defmodule RemybunWeb.GameController do
  use RemybunWeb, :controller

  alias Remybun.Games

  def history(conn, _params) do
    games =
      for game <- Games.history(conn.assigns.current_user.id) do
        %{
          id: game.id,
          status: game.status,
          started_at: game.started_at,
          finished_at: game.finished_at,
          winner_id: game.winner_id,
          players:
            game.players
            |> Enum.sort_by(& &1.seat)
            |> Enum.map(fn p ->
              %{
                seat: p.seat,
                user_id: p.user_id,
                username: p.user && p.user.username,
                final_score: p.final_score
              }
            end)
        }
      end

    json(conn, %{games: games})
  end
end
