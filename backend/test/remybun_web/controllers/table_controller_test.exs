defmodule RemybunWeb.TableControllerTest do
  use RemybunWeb.ConnCase

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Remybun.Repo, {:shared, self()})
    %{"token" => token} = conn |> post(~p"/api/guest") |> json_response(201)

    on_exit(fn ->
      for {_, child, _, _} <- DynamicSupervisor.which_children(Remybun.Tables.Supervisor) do
        DynamicSupervisor.terminate_child(Remybun.Tables.Supervisor, child)
      end
    end)

    %{authed: build_conn() |> put_req_header("authorization", "Bearer " <> token)}
  end

  test "lists presets", %{conn: conn} do
    assert %{"presets" => %{"classic" => %{"rules" => %{"opening_min_points" => 45}}}} =
             conn |> get(~p"/api/presets") |> json_response(200)
  end

  test "creates tables; private ones are only reachable by code", %{conn: conn, authed: authed} do
    assert conn |> post(~p"/api/tables", %{}) |> json_response(401)

    %{"table" => public} =
      authed |> post(~p"/api/tables", %{visibility: "public"}) |> json_response(201)

    %{"table" => private} =
      authed |> post(~p"/api/tables", %{visibility: "private"}) |> json_response(201)

    codes =
      conn
      |> get(~p"/api/tables")
      |> json_response(200)
      |> Map.fetch!("tables")
      |> Enum.map(& &1["code"])

    assert public["code"] in codes
    refute private["code"] in codes

    assert %{"table" => %{"code" => code}} =
             conn
             |> get(~p"/api/tables/#{String.downcase(private["code"])}")
             |> json_response(200)

    assert code == private["code"]
    assert conn |> get(~p"/api/tables/NOPE1234") |> json_response(404)
  end

  test "rejects invalid rules", %{authed: authed} do
    assert %{"error" => "invalid_rule:opening_min_points"} =
             authed
             |> post(~p"/api/tables", %{overrides: %{opening_min_points: "lots"}})
             |> json_response(422)

    assert %{"error" => "unknown_preset"} =
             authed |> post(~p"/api/tables", %{preset: "x"}) |> json_response(422)
  end
end
