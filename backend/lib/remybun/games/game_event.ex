defmodule Remybun.Games.GameEvent do
  use Ecto.Schema

  schema "game_events" do
    field :seq, :integer
    field :type, :string
    field :payload, :map
    belongs_to :game, Remybun.Games.Game

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
