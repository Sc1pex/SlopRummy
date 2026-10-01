defmodule Remybun.Engine.Rules do
  @moduledoc """
  Per-table rules. Built from a named preset plus optional overrides.

  `from_map/1` / `to_map/1` convert to and from a JSON-friendly map (string keys),
  used both for client-supplied overrides and for storing rule snapshots.
  """

  defstruct min_players: 2,
            max_players: 4,
            hand_size: 14,
            jokers: 4,
            opening_min_points: 45,
            discard_pickup: :must_use,
            max_jokers_per_meld: 1,
            joker_swap: true,
            lay_off_before_opening: false,
            atu: :off,
            joker_penalty: 50,
            not_opened_penalty: 100,
            joker_close_multiplier: 2,
            stock_exhausted: :reshuffle,
            match: {:rounds, 4},
            turn_timer_ms: 60_000

  @type t :: %__MODULE__{}

  @presets %{
    "classic" => %{
      name: "Classic",
      description: "Remi etalat: 45-point opening, discard pickup must be used, 4 rounds."
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
         {:ok, rules} <- merge(rules, overrides) do
      validate(rules)
    end
  end

  @doc "Rebuilds rules from a full map produced by `to_map/1`."
  def from_map(map) when is_map(map) do
    with {:ok, rules} <- merge(%__MODULE__{}, map), do: validate(rules)
  end

  def to_map(%__MODULE__{} = r) do
    r
    |> Map.from_struct()
    |> Map.new(fn
      {:match, {type, n}} ->
        {"match", %{"type" => Atom.to_string(type), "n" => n}}

      {:match, :single} ->
        {"match", %{"type" => "single"}}

      {k, v} when is_atom(v) and not is_boolean(v) and not is_nil(v) ->
        {Atom.to_string(k), Atom.to_string(v)}

      {k, v} ->
        {Atom.to_string(k), v}
    end)
  end

  defp merge(rules, overrides) do
    Enum.reduce_while(overrides, {:ok, rules}, fn {key, value}, {:ok, acc} ->
      case cast(to_string(key), value) do
        {:ok, field, cast_value} -> {:cont, {:ok, Map.put(acc, field, cast_value)}}
        :error -> {:halt, {:error, {:invalid_rule, to_string(key)}}}
      end
    end)
  end

  @int_fields ~w(min_players max_players hand_size jokers opening_min_points max_jokers_per_meld
                 joker_penalty not_opened_penalty joker_close_multiplier)
  @bool_fields ~w(joker_swap lay_off_before_opening)

  defp cast(key, v) when key in @int_fields and is_integer(v) and v >= 0,
    do: {:ok, String.to_existing_atom(key), v}

  defp cast(key, v) when key in @bool_fields and is_boolean(v),
    do: {:ok, String.to_existing_atom(key), v}

  defp cast("discard_pickup", v) when v in ["must_use", "free", :must_use, :free],
    do: {:ok, :discard_pickup, to_atom(v)}

  defp cast("stock_exhausted", v) when v in ["reshuffle", "end_round", :reshuffle, :end_round],
    do: {:ok, :stock_exhausted, to_atom(v)}

  defp cast("atu", v) when v in ["off", :off], do: {:ok, :atu, :off}

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
  defp cast(_, _), do: :error

  defp to_atom(v) when is_atom(v), do: v
  defp to_atom(v), do: String.to_existing_atom(v)

  @doc "Checks that the combination of fields makes a playable game."
  def validate(%__MODULE__{} = r) do
    cond do
      r.min_players < 2 ->
        {:error, {:invalid_rule, "min_players"}}

      r.max_players > 6 or r.max_players < r.min_players ->
        {:error, {:invalid_rule, "max_players"}}

      r.hand_size < 7 or r.hand_size > 20 ->
        {:error, {:invalid_rule, "hand_size"}}

      r.max_players * r.hand_size + 1 > 104 + r.jokers - 10 ->
        {:error, {:invalid_rule, "hand_size"}}

      r.jokers > 8 ->
        {:error, {:invalid_rule, "jokers"}}

      r.max_jokers_per_meld < 1 ->
        {:error, {:invalid_rule, "max_jokers_per_meld"}}

      r.joker_close_multiplier < 1 ->
        {:error, {:invalid_rule, "joker_close_multiplier"}}

      true ->
        {:ok, r}
    end
  end
end
