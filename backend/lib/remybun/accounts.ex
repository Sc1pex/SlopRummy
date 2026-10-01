defmodule Remybun.Accounts do
  @moduledoc """
  Users (registered and guests) and API tokens.
  """

  alias Remybun.Repo
  alias Remybun.Accounts.{User, UserToken}

  def get_user(id), do: Repo.get(User, id)

  @doc "Creates a guest user with a generated `Guest-NNNNNN` username."
  def create_guest(attempts \\ 5) do
    username = "Guest-#{:rand.uniform(899_999) + 100_000}"

    case %User{} |> User.guest_changeset(%{username: username}) |> Repo.insert() do
      {:ok, user} -> {:ok, user}
      {:error, _} when attempts > 1 -> create_guest(attempts - 1)
      error -> error
    end
  end

  @doc """
  Registers a new user. When `current_user` is a guest, the guest is upgraded in place
  so their history is kept.
  """
  def register(attrs, current_user \\ nil)

  def register(attrs, %User{guest: true} = guest),
    do: guest |> User.registration_changeset(attrs) |> Repo.update()

  def register(attrs, _), do: %User{} |> User.registration_changeset(attrs) |> Repo.insert()

  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: {:ok, user}, else: {:error, :invalid_credentials}
  end

  def authenticate(_, _), do: {:error, :invalid_credentials}

  def create_api_token(%User{} = user) do
    {encoded, token} = UserToken.build_api_token(user)
    Repo.insert!(token)
    encoded
  end

  def get_user_by_api_token(encoded) when is_binary(encoded) do
    case UserToken.verify_api_token_query(encoded) do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end

  def get_user_by_api_token(_), do: nil

  def delete_api_token(encoded) do
    with {:ok, query} <- UserToken.by_encoded_token_query(encoded), do: Repo.delete_all(query)
    :ok
  end
end
