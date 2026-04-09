defmodule MothWeb.MagicLinkLive do
  use MothWeb, :live_view

  alias Moth.Auth
  alias Moth.Auth.UserNotifier

  def mount(_params, _session, socket) do
    {:ok, assign(socket, sent: false, email: nil)}
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center min-h-[60vh] space-y-6">
      <h1 class="text-2xl font-bold text-gray-900">Sign in with Email</h1>

      <%= if @sent do %>
        <div class="text-center space-y-4 max-w-sm">
          <p class="text-gray-700">We sent a sign-in link to <strong><%= @email %></strong></p>
          <p class="text-sm text-gray-500">Check your inbox (and spam folder). The link expires in 15 minutes.</p>
          <button phx-click="resend" class="text-sm text-indigo-600 hover:text-indigo-500">Resend link</button>
        </div>
      <% else %>
        <form phx-submit="send_link" class="w-full max-w-xs space-y-4">
          <input type="email" name="email" placeholder="you@example.com"
            class="w-full rounded-lg border-gray-300 px-4 py-3" required />
          <button type="submit" class="w-full rounded-lg bg-indigo-600 px-6 py-3 text-white font-semibold hover:bg-indigo-500">
            Send sign-in link
          </button>
        </form>
      <% end %>

      <.link navigate={~p"/"} class="text-sm text-gray-500 hover:text-gray-700">Back</.link>
    </div>
    """
  end

  def handle_event("send_link", %{"email" => email}, socket) do
    send_magic_link(email, socket)
  end

  def handle_event("resend", _params, socket) do
    send_magic_link(socket.assigns.email, socket)
  end

  defp send_magic_link(email, socket) do
    email = String.downcase(String.trim(email))
    {token, _} = Auth.build_magic_link_token(email)
    url = url(~p"/auth/magic/verify?token=#{token}")
    UserNotifier.deliver_magic_link(email, url)
    {:noreply, assign(socket, sent: true, email: email)}
  end
end
