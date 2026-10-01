defmodule Remybun.Engine.RulesViewTest do
  use ExUnit.Case, async: true

  alias Remybun.Engine.{Deck, Match, Rules, View}

  describe "rules" do
    test "builds a preset with JSON overrides" do
      assert {:ok, r} =
               Rules.build("classic", %{
                 "opening_min_points" => 51,
                 "joker_swap" => false,
                 "not_opened_penalty" => 150,
                 "closed_on_board_bonus" => 250,
                 "closed_on_board_add_hand" => true
               })

      assert r.opening_min_points == 51 and r.joker_swap == false
      assert r.not_opened_penalty == 150
      assert r.closed_on_board_bonus == 250 and r.closed_on_board_add_hand

      assert {:ok, %Rules{match: :single}} =
               Rules.build("classic", %{"match" => %{"type" => "single"}})
    end

    test "rejects unknown presets, fields and bad values" do
      assert {:error, :unknown_preset} = Rules.build("nope")
      assert {:error, {:invalid_rule, "bogus"}} = Rules.build("classic", %{"bogus" => 1})

      assert {:error, {:invalid_rule, "joker_swap"}} =
               Rules.build("classic", %{"joker_swap" => "maybe"})

      assert {:error, {:invalid_rule, "max_players"}} =
               Rules.build("classic", %{"max_players" => 1})
    end

    test "ignores settings removed since a snapshot was stored" do
      old = %{"discard_pickup" => "must_use", "atu" => "off", "opening_min_points" => 51}
      assert {:ok, %Rules{opening_min_points: 51, not_opened_penalty: 100}} = Rules.from_map(old)
    end

    test "round-trips through a JSON map" do
      {:ok, r} =
        Rules.build("classic", %{
          "turn_timer_ms" => nil,
          "match" => %{"type" => "points_limit", "n" => 500}
        })

      json = r |> Rules.to_map() |> Jason.encode!() |> Jason.decode!()
      assert {:ok, ^r} = Rules.from_map(json)
    end
  end

  describe "view" do
    setup do
      m = Match.new(Rules.preset("classic"), 3)
      {:ok, m, _} = Match.start_round(m, Deck.shuffled())
      %{m: m}
    end

    test "shows only the viewer's hand", %{m: m} do
      view = View.for_seat(m, 1)
      assert length(view.round.hand) == 14
      assert view.round.hand_counts == %{0 => 15, 1 => 14, 2 => 14}
      refute Map.has_key?(view.round, :stock)

      encoded = Jason.encode!(view)
      other_ids = Enum.map(m.round.hands[0] ++ m.round.stock, & &1.id)
      decoded = Jason.decode!(encoded)
      visible = Enum.map(decoded["round"]["hand"], & &1["id"])
      assert MapSet.disjoint?(MapSet.new(visible), MapSet.new(other_ids))
    end

    test "spectators see no hand", %{m: m} do
      assert View.for_seat(m, nil).round.hand == nil
    end
  end
end
