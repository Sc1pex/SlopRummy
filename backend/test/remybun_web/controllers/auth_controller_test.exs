defmodule RemybunWeb.AuthControllerTest do
  use RemybunWeb.ConnCase, async: true

  defp authed(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  test "guest flow and upgrade keeps the same user", %{conn: conn} do
    %{"user" => guest, "token" => token} = conn |> post(~p"/api/guest") |> json_response(201)
    assert guest["guest"]
    assert guest["username"] =~ ~r/^Guest-\d{6}$/

    assert %{"user" => %{"id" => id}} =
             build_conn() |> authed(token) |> get(~p"/api/me") |> json_response(200)

    assert id == guest["id"]

    params = %{username: "andreea", email: "a@example.com", password: "supersecret"}

    %{"user" => user, "token" => ^token} =
      build_conn() |> authed(token) |> post(~p"/api/register", params) |> json_response(201)

    assert user["id"] == guest["id"]
    refute user["guest"]
  end

  test "register, login, logout", %{conn: conn} do
    params = %{username: "bob_1", email: "bob@example.com", password: "supersecret"}
    assert %{"token" => _} = conn |> post(~p"/api/register", params) |> json_response(201)

    assert %{"error" => "invalid_credentials"} =
             build_conn()
             |> post(~p"/api/login", %{email: "bob@example.com", password: "nope"})
             |> json_response(401)

    %{"token" => token} =
      build_conn()
      |> post(~p"/api/login", %{email: "bob@example.com", password: "supersecret"})
      |> json_response(200)

    assert build_conn() |> authed(token) |> delete(~p"/api/logout") |> response(204)
    assert build_conn() |> authed(token) |> get(~p"/api/me") |> json_response(401)
  end

  test "validation errors", %{conn: conn} do
    assert %{"errors" => errors} =
             conn
             |> post(~p"/api/register", %{username: "x", email: "bad", password: "short"})
             |> json_response(422)

    assert Map.keys(errors) |> Enum.sort() == ["email", "password", "username"]
  end
end
