defmodule RemybunWeb.MatchFlowTest do
  use RemybunWeb.ChannelCase

  import Phoenix.ConnTest, only: [build_conn: 0, get: 2, json_response: 2]
  import Plug.Conn, only: [put_req_header: 3]

  alias Remybun.{Accounts, Tables}

  test "timeouts auto-play a whole match; results land in history and the lobby" do
    alice = user_fixture("alice")
    bob = user_fixture("bob")

    {:ok, %{tables: []}, _lobby} = subscribe_and_join(socket_for(bob), "lobby", %{})

    overrides = %{
      "match" => %{"type" => "single"},
      "turn_timer_ms" => 5_000
    }

    {:ok, table} =
      Tables.create_table(alice, %{"visibility" => "public", "overrides" => overrides})

    code = table.invite_code
    assert_push "table_updated", %{code: ^code, status: :waiting}

    {:ok, _, sa} = subscribe_and_join(socket_for(alice), "table:" <> code, %{})
    {:ok, _, sb} = subscribe_and_join(socket_for(bob), "table:" <> code, %{})
    assert_reply push(sa, "sit", %{"seat" => 0}), :ok
    assert_reply push(sb, "sit", %{"seat" => 1}), :ok
    assert_reply push(sb, "ready", %{"ready" => true}), :ok
    assert_reply push(sa, "start", %{}), :ok
    assert_push "table_updated", %{code: ^code, status: :playing}

    pid = Tables.whereis(code)

    # Fire every turn timer by hand until the match is over.
    Enum.reduce_while(1..500, nil, fn _, _ ->
      case :sys.get_state(pid) do
        %{status: :playing, timer: {ref, deadline}} ->
          assert deadline > System.system_time(:millisecond)
          send(pid, {:turn_timeout, ref})
          {:cont, nil}

        %{status: :waiting} ->
          {:halt, nil}
      end
    end)

    state = :sys.get_state(pid)
    assert state.status == :waiting
    assert %{winners: [_ | _], totals: totals} = state.last_result
    assert map_size(totals) == 2

    token = Accounts.create_api_token(alice)

    %{"games" => [game]} =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> token)
      |> get("/api/me/games")
      |> json_response(200)

    assert game["status"] == "finished"
    assert Enum.map(game["players"], & &1["username"]) == ["alice", "bob"]
    assert Enum.all?(game["players"], &is_integer(&1["final_score"]))
  end
end
