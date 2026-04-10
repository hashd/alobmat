defmodule MothWeb.Game.ActivityFeed do
  @moduledoc """
  Real-time activity feed for game events, chat messages, and system notices.

  Uses `Phoenix.LiveView.stream/3` for efficient DOM updates with a cap of
  50 entries. Parent LiveView pushes entries via `send_update/2`:

      send_update(MothWeb.Game.ActivityFeed, id: "feed", new_entry: %{
        id: System.unique_integer([:positive]),
        type: :pick,
        text: "Number 42 picked",
        number: 42,
        user_name: nil,
        user_id: nil,
        timestamp: DateTime.utc_now()
      })

  Supported entry types: `:pick`, `:prize_claimed`, `:bogey`, `:chat`, `:system`.
  """
  use MothWeb, :live_component

  def mount(socket) do
    {:ok, socket |> stream(:entries, []) |> assign(:filter, :all)}
  end

  def update(%{new_entry: entry}, socket) do
    {:ok, stream_insert(socket, :entries, entry, at: -1, limit: 50)}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def handle_event("filter", %{"type" => type}, socket) do
    {:noreply, assign(socket, :filter, String.to_existing_atom(type))}
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-[var(--surface)] rounded-2xl overflow-hidden">
      <%!-- Filter tabs --%>
      <div class="flex items-center gap-1 px-3 pt-3 pb-2">
        <button
          :for={
            {label, value} <- [
              {"All", :all},
              {"Chat", :chat},
              {"Events", :events}
            ]
          }
          phx-click="filter"
          phx-value-type={value}
          phx-target={@myself}
          class={[
            "px-3 py-1 rounded-full text-xs font-semibold transition-colors",
            if(@filter == value,
              do: "bg-accent text-white",
              else: "bg-[var(--elevated)] text-[var(--text-muted)] hover:text-[var(--text-secondary)]"
            )
          ]}
        >
          <%= label %>
        </button>
      </div>

      <%!-- Feed entries --%>
      <div
        id="feed-scroll"
        phx-hook="AutoScroll"
        aria-live="polite"
        class="flex-1 overflow-y-auto px-3 py-1 space-y-1"
      >
        <div id="feed-entries" phx-update="stream">
          <div
            :for={{dom_id, entry} <- @streams.entries}
            id={dom_id}
            class={[
              "animate-fade-in-up",
              not visible?(entry, @filter) && "hidden"
            ]}
          >
            <.entry entry={entry} />
          </div>
        </div>
      </div>

      <%!-- Chat input --%>
      <div class="px-3 py-2 border-t border-[var(--border)]">
        <form phx-submit="chat" class="flex items-center gap-2">
          <input
            type="text"
            name="message"
            placeholder="Send a message…"
            maxlength="200"
            autocomplete="off"
            class="flex-1 rounded-full bg-[var(--elevated)] px-4 py-2 text-sm text-[var(--text-primary)] placeholder:text-[var(--text-muted)] outline-none focus:ring-2 focus:ring-accent"
          />
          <button
            type="submit"
            class="inline-flex h-8 w-8 items-center justify-center rounded-full bg-accent text-white hover:opacity-90 transition-opacity"
            aria-label="Send message"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 20 20"
              fill="currentColor"
              class="h-4 w-4"
            >
              <path d="M3.105 2.29a.75.75 0 0 0-.826.95l1.414 4.925A1.5 1.5 0 0 0 5.135 9.25h6.115a.75.75 0 0 1 0 1.5H5.135a1.5 1.5 0 0 0-1.442 1.086L2.28 16.76a.75.75 0 0 0 .826.95l15.202-4.749a.75.75 0 0 0 0-1.422L3.105 2.289Z" />
            </svg>
          </button>
        </form>
      </div>
    </div>
    """
  end

  # ── Entry rendering ──────────────────────────────────────────────────

  defp entry(%{entry: %{type: :pick}} = assigns) do
    ~H"""
    <div class="flex items-center gap-2 py-1.5">
      <.number_pill number={@entry.number} latest={false} />
      <span class="text-sm text-[var(--text-secondary)]">
        Number <strong class="text-accent"><%= @entry.number %></strong> picked
      </span>
      <.timestamp time={@entry.timestamp} />
    </div>
    """
  end

  defp entry(%{entry: %{type: :prize_claimed}} = assigns) do
    ~H"""
    <div class="flex items-center gap-2 py-1.5 px-2 rounded-lg bg-prize-gold/10">
      <span class="text-sm font-semibold text-prize-gold">
        🏆 <%= @entry.user_name %> claimed <%= @entry.text %>!
      </span>
      <.timestamp time={@entry.timestamp} />
    </div>
    """
  end

  defp entry(%{entry: %{type: :bogey}} = assigns) do
    ~H"""
    <div class="flex items-center gap-2 py-1.5">
      <span class="text-sm font-medium text-danger">
        ✗ <%= @entry.user_name %> invalid claim — <%= @entry.text %>
      </span>
      <.timestamp time={@entry.timestamp} />
    </div>
    """
  end

  defp entry(%{entry: %{type: :chat}} = assigns) do
    ~H"""
    <div class="flex items-start gap-2 py-1.5">
      <.avatar id={to_string(@entry.user_id)} name={@entry.user_name || "?"} size="sm" />
      <div class="min-w-0 flex-1">
        <span class="text-xs font-semibold text-[var(--text-primary)]"><%= @entry.user_name %></span>
        <p class="text-sm text-[var(--text-secondary)] break-words"><%= @entry.text %></p>
      </div>
      <.timestamp time={@entry.timestamp} />
    </div>
    """
  end

  defp entry(%{entry: %{type: :system}} = assigns) do
    ~H"""
    <div class="py-1.5 text-center">
      <span class="text-xs italic text-[var(--text-muted)]"><%= @entry.text %></span>
    </div>
    """
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp visible?(%{type: :chat}, :events), do: false
  defp visible?(%{type: type}, :chat) when type != :chat, do: false
  defp visible?(_entry, _filter), do: true

  defp timestamp(assigns) do
    ~H"""
    <time class="ml-auto shrink-0 text-[10px] text-[var(--text-muted)] tabular-nums">
      <%= Calendar.strftime(@time, "%H:%M") %>
    </time>
    """
  end
end
