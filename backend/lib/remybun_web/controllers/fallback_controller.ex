defmodule RemybunWeb.FallbackController do
  use RemybunWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: RemybunWeb.ChangesetJSON.errors(changeset)})
  end

  def call(conn, {:error, :not_found}) do
    conn |> put_status(:not_found) |> json(%{error: "not_found"})
  end

  def call(conn, {:error, :invalid_credentials}) do
    conn |> put_status(:unauthorized) |> json(%{error: "invalid_credentials"})
  end

  def call(conn, {:error, reason}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: RemybunWeb.ErrorJSON.reason(reason)})
  end
end
