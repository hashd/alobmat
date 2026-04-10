defmodule MothWeb.Components.Game do
  @moduledoc """
  Game-specific function components for Moth (Tambola/Housie).

  Provides: ticket_grid, ticket_cell, prize_chip, number_pill,
  board, and countdown_ring.
  """
  use Phoenix.Component

  # ── Helpers ──────────────────────────────────────────────────────────

  @doc false
  def prize_label(:early_five), do: "Early Five"
  def prize_label(:top_line), do: "Top Line"
  def prize_label(:middle_line), do: "Middle Line"
  def prize_label(:bottom_line), do: "Bottom Line"
  def prize_label(:full_house), do: "Full House"
  def prize_label("early_five"), do: "Early Five"
  def prize_label("top_line"), do: "Top Line"
  def prize_label("middle_line"), do: "Middle Line"
  def prize_label("bottom_line"), do: "Bottom Line"
  def prize_label("full_house"), do: "Full House"
  def prize_label(other), do: to_string(other)

  # ── Ticket Grid ────────────────────────────────────────────────────

  attr :ticket, :map, required: true
  attr :picks, :list, default: []
  attr :struck, :any, default: []
  attr :interactive, :boolean, default: false
  attr :status, :atom, default: :playing

  def ticket_grid(assigns) do
    rows = assigns.ticket["rows"] || assigns.ticket[:rows] || []
    picked_set = MapSet.new(assigns.picks)
    struck_set = if is_struct(assigns.struck, MapSet), do: assigns.struck, else: MapSet.new(assigns.struck)

    assigns =
      assigns
      |> assign(:rows, rows)
      |> assign(:picked_set, picked_set)
      |> assign(:struck_set, struck_set)

    ~H"""
    <div class="rounded-2xl border border bg-[var(--surface)] p-2 md:p-4">
      <h3 class="mb-2 text-center text-xs font-semibold uppercase tracking-wider text-[var(--text-muted)]">
        Your Ticket
      </h3>
      <div role="grid" class="grid grid-rows-3 gap-1">
        <div :for={row <- @rows} role="row" class="grid grid-cols-9 gap-1">
          <.ticket_cell
            :for={cell <- row}
            number={cell}
            picked={cell != nil and MapSet.member?(@picked_set, cell)}
            struck={cell != nil and MapSet.member?(@struck_set, cell)}
            interactive={@interactive}
          />
        </div>
      </div>
    </div>
    """
  end

  # ── Ticket Cell ────────────────────────────────────────────────────

  attr :number, :any, default: nil
  attr :picked, :boolean, default: false
  attr :struck, :boolean, default: false
  attr :interactive, :boolean, default: false

  def ticket_cell(%{number: nil} = assigns) do
    ~H"""
    <div
      role="gridcell"
      aria-label="empty cell"
      class="flex h-10 w-full items-center justify-center rounded border border-dashed border-[var(--border)] bg-[var(--elevated)]/30"
    />
    """
  end

  def ticket_cell(%{struck: true} = assigns) do
    ~H"""
    <div
      role="gridcell"
      aria-label={"Number #{@number}, struck"}
      aria-pressed="true"
      class="relative flex h-10 w-full items-center justify-center rounded bg-accent text-white font-bold text-sm"
    >
      <%= @number %>
      <svg
        class="absolute h-4 w-4 text-white/80"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="3"
        stroke-linecap="round"
        stroke-linejoin="round"
        aria-hidden="true"
      >
        <path d="M20 6 9 17l-5-5" />
      </svg>
    </div>
    """
  end

  def ticket_cell(%{picked: true, interactive: true} = assigns) do
    ~H"""
    <button
      role="gridcell"
      aria-label={"Number #{@number}, called, not struck"}
      phx-click="strike_out"
      phx-value-number={@number}
      phx-hook="TicketStrike"
      id={"cell-#{@number}"}
      class="flex h-10 w-full items-center justify-center rounded border-2 border-warning bg-warning/20 font-bold text-sm text-[var(--text-primary)] animate-pulse-border cursor-pointer"
    >
      <%= @number %>
    </button>
    """
  end

  def ticket_cell(assigns) do
    ~H"""
    <div
      role="gridcell"
      aria-label={"Number #{@number}, not called"}
      class="flex h-10 w-full items-center justify-center rounded bg-[var(--surface)] font-bold text-sm text-[var(--text-primary)]"
    >
      <%= @number %>
    </div>
    """
  end

  # ── Prize Chip ─────────────────────────────────────────────────────

  attr :prize, :string, required: true
  attr :label, :string, required: true
  attr :winner, :any, default: nil
  attr :progress, :any, default: nil
  attr :current_user_id, :any, default: nil
  attr :enabled, :boolean, default: true

  def prize_chip(%{winner: nil, enabled: true} = assigns) do
    progress_label =
      if assigns.progress,
        do: ", progress #{elem(assigns.progress, 0)}/#{elem(assigns.progress, 1)}",
        else: ""

    assigns = assign(assigns, :progress_label, progress_label)

    ~H"""
    <button
      role="button"
      phx-click="claim"
      phx-value-prize={@prize}
      aria-label={"Claim #{@label}#{@progress_label}"}
      class="inline-flex items-center gap-1.5 rounded-full border-2 border-accent px-3 py-1.5 text-sm font-semibold text-accent transition-all hover:bg-accent/10"
    >
      <span><%= @label %></span>
      <span :if={@progress} class="text-xs opacity-70">
        <%= elem(@progress, 0) %>/<%= elem(@progress, 1) %>
      </span>
    </button>
    """
  end

  def prize_chip(%{winner: nil, enabled: false} = assigns) do
    ~H"""
    <span
      aria-label={"#{@label}, not yet available"}
      class="inline-flex items-center gap-1.5 rounded-full border-2 border-[var(--border)] px-3 py-1.5 text-sm font-semibold text-[var(--text-muted)] opacity-50"
    >
      <span><%= @label %></span>
      <span :if={@progress} class="text-xs opacity-70">
        <%= elem(@progress, 0) %>/<%= elem(@progress, 1) %>
      </span>
    </span>
    """
  end

  def prize_chip(assigns) do
    claimed_by_me = assigns.winner == assigns.current_user_id

    assigns = assign(assigns, :claimed_by_me, claimed_by_me)

    ~H"""
    <span
      aria-label={"#{@label}, #{if @claimed_by_me, do: "claimed by you", else: "won"}"}
      class={[
        "inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-sm font-semibold",
        if(@claimed_by_me,
          do: "bg-accent text-white",
          else: "bg-[var(--elevated)] text-[var(--text-muted)] line-through"
        )
      ]}
    >
      <%= @label %>
    </span>
    """
  end

  # ── Number Pill ────────────────────────────────────────────────────

  attr :number, :integer, required: true
  attr :latest, :boolean, default: false

  def number_pill(assigns) do
    ~H"""
    <span class={[
      "inline-flex h-8 w-8 items-center justify-center rounded-full bg-accent text-white text-xs font-bold",
      @latest && "animate-bounce-in"
    ]}>
      <%= @number %>
    </span>
    """
  end

  # ── Board (9×10, numbers 1-90) ─────────────────────────────────────

  attr :picks, :list, default: []
  attr :ticket_numbers, :any, default: nil

  def board(assigns) do
    picks_set = MapSet.new(assigns.picks)
    latest = List.last(assigns.picks)

    ticket_set =
      case assigns.ticket_numbers do
        nil -> MapSet.new()
        %MapSet{} = ms -> ms
        list when is_list(list) -> MapSet.new(list)
        _ -> MapSet.new()
      end

    assigns =
      assigns
      |> assign(:picks_set, picks_set)
      |> assign(:latest, latest)
      |> assign(:ticket_set, ticket_set)

    ~H"""
    <div class="grid grid-cols-9 gap-1" role="grid" aria-label="Number board">
      <div
        :for={n <- 1..90}
        role="gridcell"
        class={[
          "relative flex h-8 w-full items-center justify-center rounded text-xs font-bold transition-colors",
          cond do
            n == @latest ->
              "bg-accent text-white ring-2 ring-accent/50"
            MapSet.member?(@picks_set, n) ->
              "bg-accent text-white"
            true ->
              "text-[var(--text-muted)] bg-[var(--surface)]"
          end
        ]}
      >
        <%= n %>
        <span
          :if={MapSet.member?(@ticket_set, n)}
          class="absolute top-0.5 right-0.5 h-1.5 w-1.5 rounded-full bg-warning"
          aria-hidden="true"
        />
      </div>
    </div>
    """
  end

  # ── Countdown Ring ─────────────────────────────────────────────────

  attr :next_pick_at, :string, default: nil
  attr :server_now, :string, default: nil
  attr :status, :string, default: nil

  def countdown_ring(assigns) do
    ~H"""
    <div
      id="countdown-ring"
      phx-hook="Countdown"
      data-next-pick-at={@next_pick_at}
      data-server-now={@server_now}
      data-status={@status}
    >
    </div>
    """
  end
end
