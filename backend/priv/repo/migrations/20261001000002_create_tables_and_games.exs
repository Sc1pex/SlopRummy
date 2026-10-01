defmodule Remybun.Repo.Migrations.CreateTablesAndGames do
  use Ecto.Migration

  def change do
    create table(:tables) do
      add :invite_code, :string, null: false
      add :visibility, :string, null: false
      add :preset, :string, null: false
      add :rules, :map, null: false
      add :status, :string, null: false, default: "waiting"
      add :host_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tables, [:invite_code])
    create index(:tables, [:visibility, :status])

    create table(:games) do
      add :table_id, references(:tables, on_delete: :nilify_all)
      add :rules, :map, null: false
      add :status, :string, null: false, default: "playing"
      add :started_at, :utc_datetime, null: false
      add :finished_at, :utc_datetime
      add :winner_id, references(:users, on_delete: :nilify_all)
    end

    create index(:games, [:table_id])

    create table(:game_players) do
      add :game_id, references(:games, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :seat, :integer, null: false
      add :final_score, :integer
    end

    create unique_index(:game_players, [:game_id, :seat])
    create index(:game_players, [:user_id])

    create table(:game_events) do
      add :game_id, references(:games, on_delete: :delete_all), null: false
      add :seq, :integer, null: false
      add :type, :string, null: false
      add :payload, :map, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:game_events, [:game_id, :seq])
  end
end
