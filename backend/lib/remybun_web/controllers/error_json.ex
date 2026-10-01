defmodule RemybunWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  # If you want to customize a particular status code,
  # you may add your own clauses, such as:
  #
  # def render("500.json", _assigns) do
  #   %{errors: %{detail: "Internal Server Error"}}
  # end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end

  @doc "Turns an internal error reason into a string for API and channel replies."
  def reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  def reason({tag, detail}) when is_atom(tag), do: "#{tag}:#{detail}"
  def reason(_), do: "error"
end
