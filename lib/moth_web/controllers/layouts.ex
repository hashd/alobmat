defmodule MothWeb.Layouts do
  @moduledoc """
  Layout templates for the application.
  """
  use MothWeb, :html

  embed_templates "layouts/*"
end
