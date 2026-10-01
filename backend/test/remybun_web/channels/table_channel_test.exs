defmodule RemybunWeb.TableChannelTest do
  use RemybunWeb.ChannelCase

  alias Remybun.{Games, Tables}

  setup do
    alice = user_fixture("alice")
    bob = user_fixture("bob")

    {:ok, table} =
      Tables.create_table(alice, %{
        "visibility" => "private",
        "overrides" => %{"match" => %{"type" => "single"}}
      })

    {:ok, %{state: state}, sa} =
      subscribe_and_join(socket_for(alice), "table:" <> table.invite_code, %{})

    {:ok, _, sb} = subscribe_and_join(socket_for(bob), "table:" <> table.invite_code, %{})

    %{alice: alice, bob: bob, table: table, sa: sa, sb: sb, state: state}
  end

  test "initial state is the waiting room", %{state: state} do
    assert state.status == :waiting
    assert length(state.seats) == 4
    assert state.game == nil
  end

  test "unknown table" do
    assert {:error, %{reason: "not_found"}} =
             subscribe_and_join(socket_for(user_fixture("carol")), "table:NOPE", %{})
  end

  test "sit, ready, start and play", %{sa: sa, sb: sb, alice: alice, bob: bob, table: table} do
    assert_reply push(sa, "sit", %{"seat" => 0}), :ok
    assert_reply push(sb, "sit", %{"seat" => 0}), :error, %{reason: "seat_taken"}
    assert_reply push(sb, "sit", %{"seat" => 2}), :ok

    assert_reply push(sb, "start", %{}), :error, %{reason: "not_host"}
    assert_reply push(sa, "start", %{}), :error, %{reason: "players_not_ready"}
    assert_reply push(sb, "ready", %{"ready" => true}), :ok
    assert_reply push(sa, "start", %{}), :ok

    # Each player gets a personal view.
    states = drain_states()
    alice_state = last_state(states, alice.id)
    bob_state = last_state(states, bob.id)
    assert alice_state.status == :playing
    assert alice_state.my_seat == 0 and bob_state.my_seat == 1
    assert length(alice_state.game.round.hand) == 15
    assert length(bob_state.game.round.hand) == 14
    assert MapSet.disjoint?(ids(alice_state.game.round.hand), ids(bob_state.game.round.hand))

    # Alice starts by discarding; Bob can't act out of turn.
    assert_reply push(sb, "draw_stock", %{}), :error, %{reason: "not_your_turn"}
    [card | _] = alice_state.game.round.hand
    assert_reply push(sa, "discard", %{"card" => card.id}), :ok
    assert_reply push(sb, "draw_stock", %{}), :ok
    assert_reply push(sb, "discard", %{"card" => "x"}), :error, %{reason: "invalid_payload"}

    {:ok, game_table} = Tables.get_by_code(table.invite_code)
    assert game_table.status == :playing

    [game] = Remybun.Repo.all(Games.Game)
    types = game.id |> Games.events() |> Enum.map(& &1.type)
    assert "deal" in types and "discarded" in types and "drew_stock" in types
  end

  test "chat is relayed to everyone", %{sa: sa} do
    assert_reply push(sa, "chat", %{"text" => "salut"}), :ok
    assert_push "chat", %{text: "salut", username: "alice"}
    assert_push "chat", %{text: "salut"}
  end

  test "host can update rules in the waiting room", %{sa: sa, sb: sb} do
    assert_reply push(sa, "sit", %{"seat" => 3}), :ok

    assert_reply push(sa, "update_rules", %{
                   "preset" => "classic",
                   "overrides" => %{"max_players" => 2}
                 }),
                 :error,
                 %{reason: "seats_occupied"}

    assert_reply push(sb, "update_rules", %{"preset" => "classic", "overrides" => %{}}),
                 :error,
                 %{reason: "not_host"}

    assert_reply push(sa, "update_rules", %{
                   "preset" => "classic",
                   "overrides" => %{"opening_min_points" => 51}
                 }),
                 :ok
  end

  # Both channel processes push to the test process; collect every view pushed so far.
  defp drain_states do
    Stream.repeatedly(fn ->
      receive do
        %Phoenix.Socket.Message{event: "update", payload: %{state: state}} -> state
      after
        200 -> nil
      end
    end)
    |> Enum.take_while(& &1)
  end

  defp last_state(states, user_id) do
    states
    |> Enum.filter(&(&1.status == :playing and my_hand_owner(&1) == user_id))
    |> List.last()
  end

  defp my_hand_owner(state), do: state.my_seat && Enum.at(state.players, state.my_seat).id
  defp ids(cards), do: MapSet.new(cards, & &1.id)
end
