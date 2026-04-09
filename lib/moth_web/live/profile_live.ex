defmodule MothWeb.ProfileLive do
  use MothWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">Profile</h1>
      <p>Signed in as <strong><%= @current_user.email %></strong></p>
    </div>
    """
  end
end
