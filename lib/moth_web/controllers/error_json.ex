defmodule MothWeb.ErrorJSON do
  @moduledoc """
  Error pages rendered as JSON.
  """

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
