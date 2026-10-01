defmodule RemybunWeb.TableController do
  use RemybunWeb, :controller

  alias Remybun.Engine.Rules
  alias Remybun.Tables

  action_fallback RemybunWeb.FallbackController

  def presets(conn, _params) do
    presets =
      Map.new(Rules.presets(), fn {key, p} ->
        {key, %{name: p.name, description: p.description, rules: Rules.to_map(p.rules)}}
      end)

    json(conn, %{presets: presets})
  end

  def index(conn, _params), do: json(conn, %{tables: Tables.list_public()})

  def create(conn, params) do
    with {:ok, table} <- Tables.create_table(conn.assigns.current_user, params) do
      conn |> put_status(:created) |> json(%{table: table_json(table)})
    end
  end

  def show(conn, %{"code" => code}) do
    with {:ok, table} <- Tables.get_by_code(String.upcase(code)),
         true <- table.status != :closed || {:error, :not_found} do
      json(conn, %{table: table_json(table)})
    end
  end

  defp table_json(table) do
    %{
      code: table.invite_code,
      visibility: table.visibility,
      preset: table.preset,
      rules: table.rules,
      status: table.status,
      host_id: table.host_id
    }
  end
end
