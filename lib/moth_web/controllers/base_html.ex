defmodule MothWeb.BaseHTML do
  @moduledoc """
  Templates for the BaseController.
  """
  use MothWeb, :html

  embed_templates "base_html/*"
end
