defmodule Remybun.Games.GamePlayer do
  use Ecto.Schema

  schema "game_players" do
    field :seat, :integer
    field :final_score, :integer
    belongs_to :game, Remybun.Games.Game
    belongs_to :user, Remybun.Accounts.User
  end
end
