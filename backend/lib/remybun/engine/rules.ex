defmodule Remybun.Engine.Rules do
  @moduledoc """
  Per-table settings, built from a named preset plus optional overrides.

  Only the settings tables may change live here. The rules of Remi etalat itself
  (tile set, deal, atu, discard pickup, opening requirements, scoring) are fixed and
  implemented in `Round`; their constants are exposed below.

  `from_map/1` / `to_map/1` convert to and from a JSON-friendly map (string keys),
  used both for client-supplied overrides and for storing rule snapshots.
  """

  defstruct min_players: 2,
            max_players: 4,
            opening_min_points: 45,
            max_jokers_per_meld: 2,
            joker_swap: true,
            not_opened_penalty: 100,
            closing_bonus: 50,
            closed_on_board_bonus: 200,
            closed_on_board_add_hand: false,
            match: {:rounds, 4},
            turn_timer_ms: 60_000

  @type t :: %__MODULE__{}

  # Fixed rules.
  def hand_size, do: 14
  def jokers, do: 2
  def joker_penalty, do: 50
  def atu_bonus, do: 50

  @presets %{
    "classic" => %{
      name: "Classic",
      description: "Remi etalat: 106 tiles, atu, 45-point opening with a run and a set, 4 rounds."
    }
  }

  @doc "Available presets as `%{key => %{name, description, rules}}`."
  def presets do
    Map.new(@presets, fn {key, meta} -> {key, Map.put(meta, :rules, preset(key))} end)
  end

  @doc "Rules for a preset key. Unknown keys return `nil`."
  def preset("classic"), do: %__MODULE__{}
  def preset(_), do: nil

  @doc "Builds rules from a preset key and a map of (string-keyed) overrides."
  def build(preset_key, overrides \\ %{}) do
    with %__MODULE__{} = rules <- preset(preset_key) || {:error, :unknown_preset},
         {:ok, rules} <- merge(rules, overrides, :strict) do
      validate(rules)
    end
  end

  @doc """
  Rebuilds rules from a stored map produced by `to_map/1`. Keys that are no longer
  settings (from older snapshots) are ignored.
  """
  def from_map(map) when is_map(map) do
    with {:ok, rules} <- merge(%__MODULE__{}, map, :lenient), do: validate(rules)
  end

  def to_map(%__MODULE__{} = r) do
    r
    |> Map.from_struct()
    |> Map.new(fn
      {:match, {type, n}} -> {"match", %{"type" => Atom.to_string(type), "n" => n}}
      {:match, :single} -> {"match", %{"type" => "single"}}
      {k, v} -> {Atom.to_string(k), v}
    end)
  end

  defp merge(rules, overrides, mode) do
    Enum.reduce_while(overrides, {:ok, rules}, fn {key, value}, {:ok, acc} ->
      key = to_string(key)

      case cast(key, value) do
        {:ok, field, cast_value} -> {:cont, {:ok, Map.put(acc, field, cast_value)}}
        :unknown when mode == :lenient -> {:cont, {:ok, acc}}
        _ -> {:halt, {:error, {:invalid_rule, key}}}
      end
    end)
  end

  @int_fields ~w(min_players max_players opening_min_points max_jokers_per_meld not_opened_penalty closing_bonus closed_on_board_bonus)
  @bool_fields ~w(joker_swap closed_on_board_add_hand)
  @fields @int_fields ++ @bool_fields ++ ~w(turn_timer_ms match)

  defp cast(key, v) when key in @int_fields and is_integer(v) and v >= 0,
    do: {:ok, String.to_existing_atom(key), v}

  defp cast(key, v) when key in @bool_fields and is_boolean(v),
    do: {:ok, String.to_existing_atom(key), v}

  defp cast("turn_timer_ms", nil), do: {:ok, :turn_timer_ms, nil}

  defp cast("turn_timer_ms", v) when is_integer(v) and v >= 5_000 and v <= 600_000,
    do: {:ok, :turn_timer_ms, v}

  defp cast("match", %{"type" => "single"}), do: {:ok, :match, :single}

  defp cast("match", %{"type" => type, "n" => n})
       when type in ["rounds", "points_limit"] and is_integer(n) and n > 0,
       do: {:ok, :match, {String.to_existing_atom(type), n}}

  defp cast("match", {type, n} = v) when type in [:rounds, :points_limit] and is_integer(n),
    do: {:ok, :match, v}

  defp cast("match", :single), do: {:ok, :match, :single}
  defp cast(key, _) when key in @fields, do: :error
  defp cast(_, _), do: :unknown

  @doc "Checks that the combination of fields makes a playable game."
  def validate(%__MODULE__{} = r) do
    cond do
      r.min_players < 2 ->
        {:error, {:invalid_rule, "min_players"}}

      r.max_players > 4 or r.max_players < r.min_players ->
        {:error, {:invalid_rule, "max_players"}}

      r.max_jokers_per_meld < 1 or r.max_jokers_per_meld > 2 ->
        {:error, {:invalid_rule, "max_jokers_per_meld"}}

      true ->
        {:ok, r}
    end
  end
end
