defmodule MothWeb.MagicLinkLive do
  use MothWeb, :live_view

  alias Moth.Auth
  alias Moth.Auth.UserNotifier

  def mount(_params, _session, socket) do
    {:ok, assign(socket, state: :request, email: nil, resend_cooldown: 0)}
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center min-h-[80vh] px-4">
      <%!-- Back button --%>
      <div class="absolute top-4 left-4 animate-fade-in-up">
        <.link navigate={~p"/"}>
          <.button variant="ghost" size="sm">
            <svg class="h-4 w-4 mr-1" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18" />
            </svg>
            Back
          </.button>
        </.link>
      </div>

      <%= if @state == :sent do %>
        <%!-- Sent state --%>
        <div class="w-full max-w-sm text-center space-y-6 animate-fade-in-up">
          <%!-- Envelope icon --%>
          <div class="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-accent/10">
            <svg class="h-8 w-8 text-accent" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M21.75 6.75v10.5a2.25 2.25 0 0 1-2.25 2.25h-15a2.25 2.25 0 0 1-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0 0 19.5 4.5h-15a2.25 2.25 0 0 0-2.25 2.25m19.5 0v.243a2.25 2.25 0 0 1-1.07 1.916l-7.5 4.615a2.25 2.25 0 0 1-2.36 0L3.32 8.91a2.25 2.25 0 0 1-1.07-1.916V6.75" />
            </svg>
          </div>

          <div class="space-y-2">
            <h1 class="text-2xl font-bold text-primary">Check your inbox</h1>
            <p class="text-sm text-muted">
              We sent a sign-in link to <strong class="text-primary"><%= @email %></strong>
            </p>
            <p class="text-xs text-muted">The link expires in 15 minutes.</p>
          </div>

          <div class="space-y-3">
            <.button
              variant="secondary"
              size="md"
              disabled={@resend_cooldown > 0}
              phx-click="resend"
              class="w-full"
            >
              <%= if @resend_cooldown > 0 do %>
                Resend in <%= @resend_cooldown %>s
              <% else %>
                Resend link
              <% end %>
            </.button>

            <button
              type="button"
              phx-click="reset"
              class="text-sm text-accent hover:text-accent/80 transition-colors"
            >
              Try a different email
            </button>
          </div>
        </div>
      <% else %>
        <%!-- Request state --%>
        <.card class="w-full max-w-sm animate-fade-in-up">
          <div class="space-y-6">
            <div class="text-center">
              <h1 class="text-2xl font-bold text-primary">Sign in with Email</h1>
              <p class="mt-1 text-sm text-muted">Enter your email to receive a sign-in link</p>
            </div>

            <form phx-submit="send_link" class="space-y-4">
              <input
                type="email"
                name="email"
                placeholder="you@example.com"
                required
                autocomplete="email"
                class={[
                  "block w-full rounded-xl border bg-[var(--surface)] px-3 py-2.5 text-sm text-primary",
                  "placeholder:text-muted",
                  "focus:border-accent focus:ring-2 focus:ring-accent/20 focus:outline-none",
                  "transition-colors duration-150"
                ]}
              />
              <.button variant="primary" size="lg" type="submit" class="w-full" phx-disable-with="Sending...">
                Send sign-in link
              </.button>
            </form>

            <div class="relative">
              <div class="absolute inset-0 flex items-center">
                <div class="w-full border-t border" />
              </div>
              <div class="relative flex justify-center text-xs">
                <span class="bg-[var(--surface)] px-2 text-muted">or</span>
              </div>
            </div>

            <.link href={~p"/auth/google"} class="block">
              <.button variant="secondary" size="lg" class="w-full">
                Sign in with Google
              </.button>
            </.link>
          </div>
        </.card>
      <% end %>
    </div>
    """
  end

  def handle_event("send_link", %{"email" => email}, socket) do
    send_magic_link(email, socket)
  end

  def handle_event("resend", _params, socket) do
    socket = assign(socket, resend_cooldown: 30)
    Process.send_after(self(), :tick_cooldown, 1000)
    send_magic_link(socket.assigns.email, socket)
  end

  def handle_event("reset", _params, socket) do
    {:noreply, assign(socket, state: :request, email: nil, resend_cooldown: 0)}
  end

  def handle_info(:tick_cooldown, socket) do
    new_cooldown = socket.assigns.resend_cooldown - 1

    if new_cooldown > 0 do
      Process.send_after(self(), :tick_cooldown, 1000)
    end

    {:noreply, assign(socket, resend_cooldown: new_cooldown)}
  end

  defp send_magic_link(email, socket) do
    email = String.downcase(String.trim(email))
    {token, _} = Auth.build_magic_link_token(email)
    url = url(~p"/auth/magic/verify?token=#{token}")
    UserNotifier.deliver_magic_link(email, url)
    {:noreply, assign(socket, state: :sent, email: email)}
  end
end
