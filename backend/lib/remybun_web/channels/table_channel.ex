defmodule RemybunWeb.TableChannel do
  @moduledoc """
  `table:<invite_code>`. Every message from the client gets a reply of `ok` or
  `error` with `%{reason: string}`. The server pushes `update` (`%{events, state}`)
  after every change and `chat` messages.
  """
  use RemybunWeb, :channel

  alias Remybun.Tables
  alias Remybun.Tables.TableServer

  @impl true
  def join("table:" <> code, _params, socket) do
    user = socket.assigns.current_user

    with {:ok, _pid} <- Tables.ensure_started(code),
         {:ok, view} <- TableServer.connect(code, user) do
      {:ok, %{state: view}, assign(socket, :code, code)}
    else
      {:error, reason} -> {:error, %{reason: RemybunWeb.ErrorJSON.reason(reason)}}
    end
  end

  @impl true
  def handle_in(event, payload, socket) do
    case parse(event, payload) do
      {:ok, action} ->
        case TableServer.action(socket.assigns.code, socket.assigns.current_user, action) do
          :ok ->
            {:reply, :ok, socket}

          {:error, reason} ->
            {:reply, {:error, %{reason: RemybunWeb.ErrorJSON.reason(reason)}}, socket}
        end

      :error ->
        {:reply, {:error, %{reason: "invalid_payload"}}, socket}
    end
  end

  @impl true
  def handle_info({:table_update, events, view}, socket) do
    push(socket, "update", %{events: events, state: view})
    {:noreply, socket}
  end

  def handle_info({:table_chat, msg}, socket) do
    push(socket, "chat", msg)
    {:noreply, socket}
  end

  defp parse("sit", %{"seat" => seat}) when is_integer(seat), do: {:ok, {:sit, seat}}
  defp parse("stand", _), do: {:ok, :stand}
  defp parse("ready", %{"ready" => ready}) when is_boolean(ready), do: {:ok, {:ready, ready}}

  defp parse("update_rules", %{"preset" => preset} = p) when is_binary(preset) do
    case Map.get(p, "overrides", %{}) do
      overrides when is_map(overrides) -> {:ok, {:update_rules, preset, overrides}}
      _ -> :error
    end
  end

  defp parse("start", _), do: {:ok, :start}
  defp parse("draw_stock", _), do: {:ok, :draw_stock}

  # Taking from the discard pile always carries the melds/additions the tile goes into.
  defp parse("take_discard", %{"card" => card} = p) when is_integer(card) do
    melds = Map.get(p, "melds", [])
    additions = Map.get(p, "additions", [])

    with true <- is_list(melds) and Enum.all?(melds, &int_list?/1),
         {:ok, additions} <- parse_additions(additions) do
      {:ok, {:take_discard, card, melds, additions}}
    else
      _ -> :error
    end
  end

  defp parse("take_atu", p) do
    melds = Map.get(p, "melds", [])

    with true <- is_list(melds) and Enum.all?(melds, &int_list?/1),
         {:ok, additions} <- parse_additions(Map.get(p, "additions", [])) do
      {:ok, {:take_atu, melds, additions}}
    else
      _ -> :error
    end
  end

  defp parse("announce_atu", _), do: {:ok, :announce_atu}

  defp parse("offer_duplicate", %{"card" => card}) when is_integer(card),
    do: {:ok, {:offer_duplicate, card}}

  defp parse("withdraw_offer", %{"offer_id" => id}) when is_integer(id),
    do: {:ok, {:withdraw_offer, id}}

  defp parse("respond_offer", %{"offer_id" => id, "card" => card})
       when is_integer(id) and is_integer(card),
       do: {:ok, {:respond_offer, id, card}}

  defp parse("withdraw_response", %{"offer_id" => id}) when is_integer(id),
    do: {:ok, {:withdraw_response, id}}

  defp parse("accept_response", %{"offer_id" => id, "seat" => seat})
       when is_integer(id) and is_integer(seat),
       do: {:ok, {:accept_response, id, seat}}

  defp parse("exchange_done", _), do: {:ok, :exchange_done}
  defp parse("refuse_deal", _), do: {:ok, :refuse_deal}

  defp parse("lay_down", %{"melds" => melds}) when is_list(melds) do
    if melds != [] and Enum.all?(melds, &int_list?/1), do: {:ok, {:lay_down, melds}}, else: :error
  end

  defp parse("add_to_meld", %{"meld_id" => id, "cards" => cards}) when is_integer(id) do
    if int_list?(cards), do: {:ok, {:add_to_meld, id, cards}}, else: :error
  end

  defp parse("swap_joker", %{"meld_id" => id, "cards" => cards}) when is_integer(id) do
    if int_list?(cards), do: {:ok, {:swap_joker, id, cards}}, else: :error
  end

  defp parse("swap_joker", %{"meld_id" => id, "card" => card})
       when is_integer(id) and is_integer(card),
       do: {:ok, {:swap_joker, id, card}}

  defp parse("discard", %{"card" => card}) when is_integer(card), do: {:ok, {:discard, card}}
  defp parse("chat", %{"text" => text}) when is_binary(text), do: {:ok, {:chat, text}}
  defp parse(_, _), do: :error

  defp parse_additions(additions) when is_list(additions) do
    Enum.reduce_while(additions, {:ok, []}, fn
      %{"meld_id" => id, "cards" => cards}, {:ok, acc} when is_integer(id) ->
        if int_list?(cards), do: {:cont, {:ok, acc ++ [{id, cards}]}}, else: {:halt, :error}

      _, _ ->
        {:halt, :error}
    end)
  end

  defp parse_additions(_), do: :error

  defp int_list?(list), do: is_list(list) and list != [] and Enum.all?(list, &is_integer/1)
end
