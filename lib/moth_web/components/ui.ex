defmodule MothWeb.Components.UI do
  @moduledoc """
  General-purpose UI function components for Moth.

  Provides reusable building blocks: button, card, badge, avatar,
  input_field, modal, toast, skeleton, segmented_control, bottom_sheet,
  and connection_status.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  # ── Avatar ──────────────────────────────────────────────────────────

  @avatar_colors ~w(
    bg-red-500 bg-orange-500 bg-amber-500 bg-emerald-500
    bg-cyan-500 bg-blue-500 bg-violet-500 bg-pink-500
  )

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :size, :string, default: "md", values: ~w(sm md lg)
  attr :class, :string, default: nil

  def avatar(assigns) do
    color_index = rem(:erlang.phash2(assigns.id), 8)
    bg_color = Enum.at(@avatar_colors, color_index)
    initials = extract_initials(assigns.name)

    size_classes =
      case assigns.size do
        "sm" -> "h-8 w-8 text-xs"
        "md" -> "h-10 w-10 text-sm"
        "lg" -> "h-14 w-14 text-lg"
      end

    assigns =
      assigns
      |> assign(:bg_color, bg_color)
      |> assign(:initials, initials)
      |> assign(:size_classes, size_classes)

    ~H"""
    <div class={[
      "inline-flex items-center justify-center rounded-full font-semibold text-white select-none",
      @size_classes,
      @bg_color,
      @class
    ]}>
      <%= @initials %>
    </div>
    """
  end

  defp extract_initials(name) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  defp extract_initials(_), do: "?"

  # ── Button ──────────────────────────────────────────────────────────

  attr :variant, :string, default: "primary", values: ~w(primary secondary ghost danger)
  attr :size, :string, default: "md", values: ~w(sm md lg)
  attr :loading, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :type, :string, default: "button"
  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def button(assigns) do
    variant_classes =
      case assigns.variant do
        "primary" ->
          "bg-accent text-white hover:opacity-90 focus-visible:ring-2 focus-visible:ring-accent/50"

        "secondary" ->
          "bg-elevated text-primary border border hover:opacity-80 focus-visible:ring-2 focus-visible:ring-accent/50"

        "ghost" ->
          "bg-transparent text-secondary hover:bg-elevated focus-visible:ring-2 focus-visible:ring-accent/50"

        "danger" ->
          "bg-danger text-white hover:opacity-90 focus-visible:ring-2 focus-visible:ring-danger/50"
      end

    size_classes =
      case assigns.size do
        "sm" -> "px-3 py-1.5 text-sm rounded-lg"
        "md" -> "px-4 py-2 text-sm rounded-xl"
        "lg" -> "px-6 py-3 text-base rounded-xl"
      end

    assigns =
      assigns
      |> assign(:variant_classes, variant_classes)
      |> assign(:size_classes, size_classes)

    ~H"""
    <button
      type={@type}
      disabled={@disabled || @loading}
      class={[
        "inline-flex items-center justify-center gap-2 font-semibold transition-all duration-150",
        "disabled:opacity-50 disabled:cursor-not-allowed",
        @variant_classes,
        @size_classes,
        @class
      ]}
      {@rest}
    >
      <svg
        :if={@loading}
        class="h-4 w-4 animate-spin"
        viewBox="0 0 24 24"
        fill="none"
        aria-hidden="true"
      >
        <circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" class="opacity-25" />
        <path
          d="M4 12a8 8 0 018-8"
          stroke="currentColor"
          stroke-width="4"
          stroke-linecap="round"
          class="opacity-75"
        />
      </svg>
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  # ── Badge ───────────────────────────────────────────────────────────

  attr :variant, :string, default: "default", values: ~w(live paused finished default)
  attr :class, :string, default: nil

  slot :inner_block, required: true

  def badge(assigns) do
    variant_classes =
      case assigns.variant do
        "live" ->
          "bg-success/20 text-[var(--success)] border border-success/40 animate-pulse-border"

        "paused" ->
          "bg-warning/20 text-[var(--warning)] border border-warning/40"

        "finished" ->
          "bg-elevated text-muted border border"

        "default" ->
          "bg-elevated text-secondary border border"
      end

    aria_label =
      case assigns.variant do
        "live" -> "Game is live"
        "paused" -> "Game is paused"
        "finished" -> "Game is finished"
        _ -> nil
      end

    assigns =
      assigns
      |> assign(:variant_classes, variant_classes)
      |> assign(:aria_label, aria_label)

    ~H"""
    <span
      class={[
        "inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium",
        @variant_classes,
        @class
      ]}
      aria-label={@aria_label}
    >
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  # ── Skeleton ────────────────────────────────────────────────────────

  attr :variant, :string, default: "text", values: ~w(text card avatar ticket)
  attr :class, :string, default: nil

  def skeleton(assigns) do
    ~H"""
    <div
      class={[
        "animate-shimmer rounded",
        skeleton_classes(@variant),
        @class
      ]}
      aria-hidden="true"
    />
    """
  end

  defp skeleton_classes("text"), do: "h-4 w-full rounded"
  defp skeleton_classes("card"), do: "h-32 w-full rounded-xl"
  defp skeleton_classes("avatar"), do: "h-10 w-10 rounded-full"
  defp skeleton_classes("ticket"), do: "h-48 w-full rounded-xl"

  # ── Segmented Control ──────────────────────────────────────────────

  attr :options, :list, required: true
  attr :selected, :string, required: true
  attr :name, :string, required: true
  attr :on_select, :string, default: "select_segment"
  attr :class, :string, default: nil

  def segmented_control(assigns) do
    ~H"""
    <div
      class={["inline-flex rounded-xl bg-elevated p-1 gap-1", @class]}
      role="tablist"
    >
      <button
        :for={option <- @options}
        type="button"
        role="tab"
        aria-selected={to_string(option.value == @selected)}
        phx-click={@on_select}
        phx-value-value={option.value}
        phx-value-name={@name}
        class={[
          "rounded-lg px-4 py-1.5 text-sm font-medium transition-all duration-150",
          if(option.value == @selected,
            do: "bg-accent text-white shadow-sm",
            else: "text-secondary hover:text-primary"
          )
        ]}
      >
        <%= option.label %>
      </button>
    </div>
    """
  end

  # ── Toast ───────────────────────────────────────────────────────────

  attr :id, :string, required: true
  attr :variant, :string, default: "info", values: ~w(success error info)
  attr :message, :string, required: true

  def toast(assigns) do
    variant_classes =
      case assigns.variant do
        "success" -> "bg-success text-white"
        "error" -> "bg-danger text-white"
        "info" -> "bg-accent text-white"
      end

    icon =
      case assigns.variant do
        "success" -> "M9 12.75 11.25 15 15 9.75"
        "error" -> "M6 18 18 6M6 6l12 12"
        "info" -> "M11.25 11.25l.041-.02a.75.75 0 0 1 1.063.852l-.708 2.836a.75.75 0 0 0 1.063.853l.041-.021M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9-3.75h.008v.008H12V8.25Z"
      end

    assigns =
      assigns
      |> assign(:variant_classes, variant_classes)
      |> assign(:icon, icon)

    ~H"""
    <div
      id={@id}
      class={[
        "flex items-center gap-2 rounded-xl px-4 py-3 text-sm font-medium shadow-lg",
        "animate-fade-in-up",
        @variant_classes
      ]}
      role="status"
      aria-live="polite"
      phx-hook="AutoDismiss"
    >
      <svg class="h-5 w-5 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" aria-hidden="true">
        <path stroke-linecap="round" stroke-linejoin="round" d={@icon} />
      </svg>
      <span><%= @message %></span>
      <button
        type="button"
        class="ml-auto -mr-1 opacity-70 hover:opacity-100"
        aria-label="Dismiss"
        phx-click={JS.hide(to: "##{@id}", transition: {"ease-in duration-150", "opacity-100", "opacity-0"})}
      >
        <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
    """
  end

  # ── Modal ───────────────────────────────────────────────────────────

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :class, :string, default: nil

  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      class={["relative z-50", unless(@show, do: "hidden")]}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
      role="dialog"
    >
      <%!-- Backdrop --%>
      <div
        id={"#{@id}-backdrop"}
        class="fixed inset-0 bg-black/50 transition-opacity"
        aria-hidden="true"
      />
      <%!-- Panel --%>
      <div class="fixed inset-0 flex items-center justify-center p-4">
        <div
          id={"#{@id}-panel"}
          class={[
            "w-full max-w-md rounded-2xl bg-[var(--surface)] border border p-6 shadow-xl",
            "animate-scale-in",
            @class
          ]}
          phx-click-away={hide_modal(@id)}
          phx-window-keydown={hide_modal(@id)}
          phx-key="Escape"
        >
          <%= render_slot(@inner_block) %>
        </div>
      </div>
    </div>
    """
  end

  defp show_modal(id) do
    JS.show(to: "##{id}")
    |> JS.show(to: "##{id}-backdrop", transition: {"ease-out duration-200", "opacity-0", "opacity-100"})
    |> JS.show(to: "##{id}-panel", transition: {"ease-out duration-200", "opacity-0 scale-95", "opacity-100 scale-100"})
    |> JS.focus_first(to: "##{id}-panel")
  end

  defp hide_modal(id) do
    JS.hide(to: "##{id}-backdrop", transition: {"ease-in duration-150", "opacity-100", "opacity-0"})
    |> JS.hide(to: "##{id}-panel", transition: {"ease-in duration-150", "opacity-100 scale-100", "opacity-0 scale-95"})
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"}, time: 200)
  end

  # ── Card ────────────────────────────────────────────────────────────

  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div
      class={[
        "rounded-2xl border border bg-[var(--surface)] p-4",
        @class
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  # ── Input Field ─────────────────────────────────────────────────────

  attr :id, :string, default: nil
  attr :name, :string, required: true
  attr :label, :string, default: nil
  attr :value, :string, default: nil
  attr :type, :string, default: "text"
  attr :placeholder, :string, default: nil
  attr :error, :string, default: nil
  attr :icon, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global

  def input_field(assigns) do
    ~H"""
    <div class={@class}>
      <label :if={@label} for={@id || @name} class="block text-sm font-medium text-primary mb-1">
        <%= @label %>
      </label>
      <div class="relative">
        <div :if={@icon} class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3 text-muted">
          <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" d={@icon} />
          </svg>
        </div>
        <input
          type={@type}
          id={@id || @name}
          name={@name}
          value={@value}
          placeholder={@placeholder}
          class={[
            "block w-full rounded-xl border bg-[var(--surface)] px-3 py-2.5 text-sm text-primary",
            "placeholder:text-muted",
            "focus:border-accent focus:ring-2 focus:ring-accent/20 focus:outline-none",
            "transition-colors duration-150",
            @icon && "pl-10",
            @error && "border-danger focus:border-danger focus:ring-danger/20"
          ]}
          {@rest}
        />
      </div>
      <p :if={@error} class="mt-1 text-xs text-[var(--danger)]"><%= @error %></p>
    </div>
    """
  end

  # ── Bottom Sheet ────────────────────────────────────────────────────

  attr :id, :string, required: true
  attr :class, :string, default: nil

  slot :inner_block, required: true

  def bottom_sheet(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="BottomSheet"
      class={[
        "fixed inset-x-0 bottom-0 z-40 translate-y-full transition-transform duration-300 ease-out",
        "rounded-t-2xl bg-[var(--surface)] border-t border shadow-xl",
        @class
      ]}
    >
      <div class="mx-auto mt-2 h-1 w-10 rounded-full bg-[var(--border)]" />
      <div class="p-4">
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  # ── Connection Status ──────────────────────────────────────────────

  def connection_status(assigns) do
    ~H"""
    <div
      id="connection-status-component"
      class="hidden fixed top-0 inset-x-0 z-50 flex items-center justify-center gap-2 bg-accent/90 text-white py-2 text-sm font-medium"
      role="alert"
    >
      <svg class="h-4 w-4 animate-spin" viewBox="0 0 24 24" fill="none" aria-hidden="true">
        <circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" class="opacity-25" />
        <path d="M4 12a8 8 0 018-8" stroke="currentColor" stroke-width="4" stroke-linecap="round" class="opacity-75" />
      </svg>
      Connection lost. Reconnecting...
    </div>
    """
  end
end
