defmodule Remybun.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :username, :string
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :guest, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def guest_changeset(user, attrs) do
    user
    |> cast(attrs, [:username])
    |> put_change(:guest, true)
    |> validate_username()
  end

  @doc "Registration of a new user, or upgrade of a guest to a full account."
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :password])
    |> put_change(:guest, false)
    |> validate_username()
    |> validate_required([:email, :password])
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
    |> validate_length(:password, min: 8, max: 72)
    |> hash_password()
  end

  defp validate_username(changeset) do
    changeset
    |> validate_required([:username])
    |> validate_length(:username, min: 3, max: 20)
    |> validate_format(:username, ~r/^[A-Za-z0-9_-]+$/, message: "only letters, numbers, - and _")
    |> unique_constraint(:username)
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      password when changeset.valid? and is_binary(password) ->
        changeset
        |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
        |> delete_change(:password)

      _ ->
        changeset
    end
  end

  @doc "Checks a password; runs a dummy check when there is no user to prevent timing attacks."
  def valid_password?(%__MODULE__{hashed_password: hashed}, password)
      when is_binary(hashed) and byte_size(password) > 0,
      do: Bcrypt.verify_pass(password, hashed)

  def valid_password?(_, _), do: Bcrypt.no_user_verify()
end
