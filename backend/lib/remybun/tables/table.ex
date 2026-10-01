defmodule Remybun.Tables.Table do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tables" do
    field :invite_code, :string
    field :visibility, Ecto.Enum, values: [:public, :private]
    field :preset, :string
    field :rules, :map
    field :status, Ecto.Enum, values: [:waiting, :playing, :closed], default: :waiting
    belongs_to :host, Remybun.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def create_changeset(table, attrs) do
    table
    |> cast(attrs, [:invite_code, :visibility, :preset, :rules, :host_id])
    |> validate_required([:invite_code, :visibility, :preset, :rules])
    |> unique_constraint(:invite_code)
  end
end
