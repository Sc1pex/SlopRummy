defmodule Remybun.Accounts.UserToken do
  @moduledoc """
  Bearer tokens for the API and the socket. Only a SHA-256 hash of the token is stored.
  """
  use Ecto.Schema
  import Ecto.Query

  @rand_size 32
  @hash :sha256
  @validity_days 60

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    belongs_to :user, Remybun.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Returns `{encoded_token, %UserToken{}}`; the encoded token is given to the client."
  def build_api_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{token: :crypto.hash(@hash, token), context: "api", user_id: user.id}}
  end

  def verify_api_token_query(encoded) do
    with {:ok, token} <- Base.url_decode64(encoded, padding: false) do
      query =
        from t in by_token_query(token),
          join: u in assoc(t, :user),
          where: t.inserted_at > ago(@validity_days, "day"),
          select: u

      {:ok, query}
    end
  end

  def by_encoded_token_query(encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, token} -> {:ok, by_token_query(token)}
      :error -> :error
    end
  end

  defp by_token_query(token) do
    from t in __MODULE__, where: t.token == ^:crypto.hash(@hash, token) and t.context == "api"
  end
end
