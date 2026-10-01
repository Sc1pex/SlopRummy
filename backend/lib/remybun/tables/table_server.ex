defmodule Remybun.Tables.TableServer do
  @moduledoc """
  One process per table. Holds the authoritative state: the waiting room (seats,
  ready flags, rules) and the match in progress.

  Connected clients (channel processes) register with `connect/2`. After every change
  each one is sent `{:table_update, events, view}` with a view tailored to its user,
  so hidden information never leaves this process. Chat is sent as `{:table_chat, msg}`.

  Public tables publish their summary on the `"lobby:tables"` PubSub topic as
  `{:table_summary, summary}` and `{:table_closed, code}`.
  """
  use GenServer, restart: :transient

  require Logger

  alias Remybun.{Games, Tables}
  alias Remybun.Engine.{Deck, Match, Rules, View}

  @lobby_topic "lobby:tables"

  def lobby_topic, do: @lobby_topic

  ## API

  def start_link(table) do
    GenServer.start_link(__MODULE__, table,
      name: {:via, Registry, {Tables.registry(), table.invite_code, nil}}
    )
  end

  @doc "Registers the calling process as a connection for `user`. Returns the initial view."
  def connect(code, user), do: call(code, {:connect, user, self()})

  @doc """
  Performs an action as `user`. Waiting room: `{:sit, seat}`, `:stand`, `{:ready, bool}`,
  `{:update_rules, preset, overrides}`, `:start`. Chat: `{:chat, text}`.
  Anything else is passed to the engine as a game action.
  """
  def action(code, user, action), do: call(code, {:action, user, action})

  def view(code, user_id), do: call(code, {:view, user_id})

  defp call(code, msg) do
    case Tables.whereis(code) do
      nil -> {:error, :table_not_found}
      pid -> GenServer.call(pid, msg)
    end
  catch
    :exit, _ -> {:error, :table_not_found}
  end

  ## Server

  @impl true
  def init(table) do
    {:ok, rules} = Rules.from_map(table.rules)

    state = %{
      table: table,
      code: table.invite_code,
      rules: rules,
      status: :waiting,
      seats: Map.new(0..(rules.max_players - 1), &{&1, nil}),
      players: [],
      match: nil,
      game_id: nil,
      seq: 0,
      last_result: nil,
      conns: %{},
      timer: nil,
      idle_timer: nil,
      last_summary: nil
    }

    {:ok, state |> schedule_idle() |> publish_summary()}
  end

  @impl true
  def handle_call({:connect, user, pid}, _from, state) do
    ref = Process.monitor(pid)
    state = put_in(state.conns[pid], %{user_id: user.id, username: user.username, ref: ref})
    state = cancel_idle(state)
    # Others see the player as connected again; a disconnect grace timer may no longer apply.
    state = state |> schedule_turn_timer(false) |> broadcast([])
    {:reply, {:ok, view_for(state, user.id)}, state}
  end

  def handle_call({:view, user_id}, _from, state),
    do: {:reply, {:ok, view_for(state, user_id)}, state}

  def handle_call({:action, user, {:chat, text}}, _from, state) do
    text = String.trim(to_string(text))

    if text != "" and String.length(text) <= 300 do
      msg = %{user_id: user.id, username: user.username, text: text}
      for pid <- Map.keys(state.conns), do: send(pid, {:table_chat, msg})
      {:reply, :ok, state}
    else
      {:reply, {:error, :invalid_message}, state}
    end
  end

  def handle_call({:action, user, action}, _from, state) do
    case handle_action(state, user, action) do
      {:ok, state, events} ->
        {:reply, :ok, after_change(state, events)}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {_, state} = pop_in(state.conns[pid])
    state = if state.conns == %{}, do: schedule_idle(state), else: state
    {:noreply, state |> broadcast([]) |> schedule_turn_timer(false)}
  end

  def handle_info({:turn_timeout, ref}, %{timer: {ref, _}} = state) do
    seat = Match.current_seat(state.match)
    {:ok, match, events} = Match.auto_play(state.match)
    state = %{state | match: match, timer: nil}
    state = persist(state, [%{type: :auto_played, seat: seat} | events])
    {:noreply, after_change(state, events, true)}
  end

  def handle_info({:turn_timeout, _stale}, state), do: {:noreply, state}

  def handle_info(:next_round, %{status: :playing, match: %Match{phase: :between_rounds}} = state) do
    {:ok, state, events} = start_round(state)
    {:noreply, after_change(state, events)}
  end

  def handle_info(:next_round, state), do: {:noreply, state}

  def handle_info(:idle_stop, %{conns: conns} = state) when conns == %{} do
    if state.game_id && state.status == :playing, do: Games.abandon_game(state.game_id)
    {:ok, _} = Tables.update_table(state.table, %{status: :closed})
    Phoenix.PubSub.broadcast(Remybun.PubSub, @lobby_topic, {:table_closed, state.code})
    {:stop, :normal, state}
  end

  def handle_info(:idle_stop, state), do: {:noreply, state}

  ## Waiting room

  defp handle_action(%{status: :waiting} = state, user, {:sit, seat}) do
    cond do
      not Map.has_key?(state.seats, seat) ->
        {:error, :invalid_seat}

      state.seats[seat] != nil ->
        {:error, :seat_taken}

      true ->
        seats =
          state.seats
          |> Map.new(fn {s, p} -> if p && p.user_id == user.id, do: {s, nil}, else: {s, p} end)
          |> Map.put(seat, %{user_id: user.id, username: user.username, ready: false})

        {:ok, %{state | seats: seats}, []}
    end
  end

  defp handle_action(%{status: :waiting} = state, user, :stand) do
    case seat_of(state, user.id) do
      nil -> {:error, :not_seated}
      seat -> {:ok, put_in(state.seats[seat], nil), []}
    end
  end

  defp handle_action(%{status: :waiting} = state, user, {:ready, ready}) when is_boolean(ready) do
    case seat_of(state, user.id) do
      nil -> {:error, :not_seated}
      seat -> {:ok, put_in(state.seats[seat].ready, ready), []}
    end
  end

  defp handle_action(%{status: :waiting} = state, user, {:update_rules, preset, overrides}) do
    with :ok <- check_host(state, user),
         {:ok, rules} <- Rules.build(preset, overrides),
         :ok <- check_seats_fit(state, rules) do
      seats =
        Map.new(
          0..(rules.max_players - 1),
          &{&1, state.seats[&1] && %{state.seats[&1] | ready: false}}
        )

      {:ok, table} =
        Tables.update_table(state.table, %{preset: preset, rules: Rules.to_map(rules)})

      {:ok, %{state | rules: rules, seats: seats, table: table}, [%{type: :rules_updated}]}
    end
  end

  defp handle_action(%{status: :waiting} = state, user, :start) do
    seated = state.seats |> Enum.filter(&elem(&1, 1)) |> Enum.sort()

    with :ok <- check_host(state, user),
         true <- length(seated) >= state.rules.min_players || {:error, :not_enough_players},
         true <-
           Enum.all?(seated, fn {_, p} -> p.ready or p.user_id == user.id end) ||
             {:error, :players_not_ready} do
      players = Enum.map(seated, fn {_, p} -> Map.take(p, [:user_id, :username]) end)

      {:ok, game} =
        Games.start_game(
          state.table.id,
          Rules.to_map(state.rules),
          Enum.map(players, & &1.user_id)
        )

      {:ok, table} = Tables.update_table(state.table, %{status: :playing})

      state = %{
        state
        | status: :playing,
          table: table,
          players: players,
          match: Match.new(state.rules, length(players)),
          game_id: game.id,
          seq: 0,
          last_result: nil
      }

      start_round(state)
    end
  end

  defp handle_action(%{status: :waiting}, _user, _action), do: {:error, :game_not_started}

  ## In game

  defp handle_action(%{status: :playing} = state, user, action) do
    case Enum.find_index(state.players, &(&1.user_id == user.id)) do
      nil ->
        {:error, :not_a_player}

      seat ->
        with {:ok, match, events} <- Match.play(state.match, seat, action) do
          state =
            persist(%{state | match: match}, [
              %{type: :action, seat: seat, action: inspect(action)} | events
            ])

          {:ok, state, events}
        end
    end
  end

  defp start_round(state) do
    deck = Deck.shuffled(state.rules.jokers)
    {:ok, match, events} = Match.start_round(state.match, deck)

    state =
      persist(%{state | match: match}, [%{type: :deal, deck: Enum.map(deck, & &1.id)} | events])

    {:ok, state, events}
  end

  ## After every change

  defp after_change(state, events, turn_reset? \\ false) do
    turn_reset? = turn_reset? or Enum.any?(events, &(&1.type in [:turn, :round_started]))

    state
    |> handle_match_progress()
    |> schedule_turn_timer(turn_reset?)
    |> broadcast(events)
    |> publish_summary()
  end

  defp handle_match_progress(%{status: :playing, match: %Match{phase: :between_rounds}} = state) do
    Process.send_after(
      self(),
      :next_round,
      Application.get_env(:remybun, :next_round_delay_ms, 8_000)
    )

    state
  end

  defp handle_match_progress(%{status: :playing, match: %Match{phase: :finished} = match} = state) do
    winner_user = state.players |> Enum.at(hd(match.winners)) |> Map.get(:user_id)
    Games.finish_game(state.game_id, match.totals, winner_user)
    {:ok, table} = Tables.update_table(state.table, %{status: :waiting})

    result = %{
      totals: match.totals,
      winners: match.winners,
      players: state.players,
      rounds: match.history
    }

    seats = Map.new(state.seats, fn {s, p} -> {s, p && %{p | ready: false}} end)

    %{
      state
      | status: :waiting,
        table: table,
        match: nil,
        game_id: nil,
        last_result: result,
        seats: seats
    }
  end

  defp handle_match_progress(state), do: state

  defp schedule_turn_timer(
         %{status: :playing, match: %Match{phase: :playing} = match} = state,
         reset?
       ) do
    seat = Match.current_seat(match)
    %{user_id: user_id} = Enum.at(state.players, seat)
    connected? = Enum.any?(state.conns, fn {_, c} -> c.user_id == user_id end)

    timeout =
      state.rules.turn_timer_ms ||
        if(connected?, do: nil, else: Application.get_env(:remybun, :disconnect_grace_ms, 60_000))

    cond do
      state.timer != nil and timeout != nil and not reset? ->
        state

      timeout == nil ->
        cancel_timer(state)

      true ->
        ref = make_ref()
        Process.send_after(self(), {:turn_timeout, ref}, timeout)
        %{state | timer: {ref, System.system_time(:millisecond) + timeout}}
    end
  end

  defp schedule_turn_timer(state, _reset?), do: cancel_timer(state)

  # Stale timeout messages are ignored because their ref no longer matches.
  defp cancel_timer(state), do: %{state | timer: nil}

  defp schedule_idle(state) do
    state = cancel_idle(state)

    ref =
      Process.send_after(
        self(),
        :idle_stop,
        Application.get_env(:remybun, :idle_timeout_ms, 300_000)
      )

    %{state | idle_timer: ref}
  end

  defp cancel_idle(%{idle_timer: nil} = state), do: state

  defp cancel_idle(state) do
    Process.cancel_timer(state.idle_timer)
    %{state | idle_timer: nil}
  end

  defp broadcast(state, events) do
    for {pid, %{user_id: user_id}} <- state.conns do
      send(pid, {:table_update, events, view_for(state, user_id)})
    end

    state
  end

  defp persist(%{game_id: nil} = state, _events), do: state

  defp persist(state, events) do
    numbered = Enum.with_index(events, state.seq + 1) |> Enum.map(fn {e, i} -> {i, e} end)

    try do
      Games.append_events(state.game_id, numbered)
    rescue
      e -> Logger.error("failed to persist game events: #{Exception.message(e)}")
    end

    %{state | seq: state.seq + length(events)}
  end

  defp publish_summary(state) do
    case summary(state) do
      summary when summary == state.last_summary ->
        state

      summary ->
        Registry.update_value(Tables.registry(), state.code, fn _ -> summary end)

        if state.table.visibility == :public do
          Phoenix.PubSub.broadcast(Remybun.PubSub, @lobby_topic, {:table_summary, summary})
        end

        %{state | last_summary: summary}
    end
  end

  ## Views

  defp summary(state) do
    %{
      code: state.code,
      visibility: state.table.visibility,
      preset: state.table.preset,
      status: state.status,
      host_id: state.table.host_id,
      max_players: state.rules.max_players,
      min_players: state.rules.min_players,
      players:
        for({_, p} <- Enum.sort(state.seats), p, do: %{id: p.user_id, username: p.username}),
      created_at: state.table.inserted_at
    }
  end

  defp view_for(state, user_id) do
    connected = state.conns |> Map.values() |> MapSet.new(& &1.user_id)
    my_seat = Enum.find_index(state.players, &(&1.user_id == user_id))

    %{
      code: state.code,
      visibility: state.table.visibility,
      preset: state.table.preset,
      rules: Rules.to_map(state.rules),
      host_id: state.table.host_id,
      status: state.status,
      seats:
        for {seat, p} <- Enum.sort(state.seats) do
          %{
            seat: seat,
            user:
              p &&
                %{
                  id: p.user_id,
                  username: p.username,
                  connected: MapSet.member?(connected, p.user_id)
                },
            ready: (p && p.ready) || false
          }
        end,
      players:
        state.players
        |> Enum.with_index()
        |> Enum.map(fn {p, seat} ->
          %{
            seat: seat,
            id: p.user_id,
            username: p.username,
            connected: MapSet.member?(connected, p.user_id)
          }
        end),
      my_seat: if(state.status == :playing, do: my_seat),
      game:
        if(state.match, do: View.for_seat(state.match, if(state.status == :playing, do: my_seat))),
      turn_deadline: with({_, deadline} <- state.timer, do: deadline),
      last_result: state.last_result
    }
  end

  ## Helpers

  defp seat_of(state, user_id) do
    Enum.find_value(state.seats, fn {seat, p} -> p && p.user_id == user_id && seat end)
  end

  # The host manages the table; if the host isn't connected, any seated player may.
  defp check_host(state, user) do
    host_connected = Enum.any?(state.conns, fn {_, c} -> c.user_id == state.table.host_id end)

    cond do
      user.id == state.table.host_id -> :ok
      not host_connected and seat_of(state, user.id) != nil -> :ok
      true -> {:error, :not_host}
    end
  end

  defp check_seats_fit(state, rules) do
    if Enum.any?(state.seats, fn {seat, p} -> p && seat >= rules.max_players end),
      do: {:error, :seats_occupied},
      else: :ok
  end
end
