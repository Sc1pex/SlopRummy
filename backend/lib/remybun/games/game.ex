defmodule Remybun.Games.Game do
  use Ecto.Schema

  schema "games" do
    field :rules, :map
    field :status, Ecto.Enum, values: [:playing, :finished, :abandoned], default: :playing
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    belongs_to :table, Remybun.Tables.Table
    belongs_to :winner, Remybun.Accounts.User
    has_many :players, Remybun.Games.GamePlayer
  end
end
