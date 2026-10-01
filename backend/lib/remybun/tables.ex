defmodule Remybun.Tables do
  @moduledoc """
  Game tables: the DB record (invite code, rules, visibility) and the live
  `TableServer` process that runs it. Tables are addressed by their invite code.
  """

  alias Remybun.Repo
  alias Remybun.Engine.Rules
  alias Remybun.Tables.{Table, TableServer}

  @registry Remybun.Tables.Registry
  @supervisor Remybun.Tables.Supervisor

  def registry, do: @registry

  @doc """
  Creates a table from `%{"preset" => key, "overrides" => map, "visibility" => "public" | "private"}`
  and starts its server.
  """
  def create_table(host, params) do
    preset = Map.get(params, "preset", "classic")
    visibility = Map.get(params, "visibility", "public")

    with {:ok, rules} <- Rules.build(preset, Map.get(params, "overrides") || %{}),
         true <- visibility in ["public", "private"] || {:error, :invalid_visibility},
         {:ok, table} <- insert_table(host, preset, rules, visibility),
         {:ok, _pid} <- ensure_started(table.invite_code) do
      {:ok, table}
    end
  end

  defp insert_table(host, preset, rules, visibility, attempts \\ 5) do
    attrs = %{
      invite_code: generate_code(),
      visibility: visibility,
      preset: preset,
      rules: Rules.to_map(rules),
      host_id: host.id
    }

    case %Table{} |> Table.create_changeset(attrs) |> Repo.insert() do
      {:error, %{errors: [invite_code: _]}} when attempts > 1 ->
        insert_table(host, preset, rules, visibility, attempts - 1)

      result ->
        result
    end
  end

  # Unambiguous characters only.
  @alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  defp generate_code, do: for(_ <- 1..8, into: "", do: <<Enum.random(@alphabet)>>)

  def get_by_code(code) when is_binary(code) do
    case Repo.get_by(Table, invite_code: code) do
      nil -> {:error, :not_found}
      table -> {:ok, table}
    end
  end

  def update_table(%Table{} = table, attrs) do
    table |> Ecto.Changeset.change(attrs) |> Repo.update()
  end

  @doc "Returns the pid of the table's server, starting it from the DB record if needed."
  def ensure_started(code) do
    case whereis(code) do
      pid when is_pid(pid) ->
        {:ok, pid}

      nil ->
        with {:ok, table} <- get_by_code(code),
             true <- table.status != :closed || {:error, :not_found} do
          case DynamicSupervisor.start_child(@supervisor, {TableServer, table}) do
            {:error, {:already_started, pid}} -> {:ok, pid}
            other -> other
          end
        end
    end
  end

  def whereis(code) do
    case Registry.lookup(@registry, code) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "Summaries of running public tables (kept up to date by each server in the registry)."
  def list_public do
    @registry
    |> Registry.select([{{:_, :_, :"$1"}, [], [:"$1"]}])
    |> Enum.filter(&(is_map(&1) and &1.visibility == :public))
    |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
  end
end
