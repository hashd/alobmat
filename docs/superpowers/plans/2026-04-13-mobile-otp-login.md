# Mobile OTP Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to sign up and log in using just their Indian mobile number + 6-digit SMS OTP.

**Architecture:** A dedicated `phone_otp_codes` table stores hashed OTPs pre-authentication. Phone normalization is a pure function in `Moth.Auth.Phone`. SMS delivery uses a behaviour (`SMSProvider`) with swappable adapters (MSG91 for prod, Log for dev, Test for tests). The existing `users` table gains an optional `phone` column; `email` becomes optional. The Vue frontend adds a phone/OTP tab to the existing Auth page.

**Tech Stack:** Elixir/Phoenix (backend), Ecto + Postgres (data), Finch (HTTP to MSG91), Vue 3 + TypeScript + Pinia (frontend), Vitest (frontend tests)

**Spec:** `docs/superpowers/specs/2026-04-13-mobile-otp-login-design.md`

---

## File Structure

**New backend files:**
- `priv/repo/migrations/<ts>_add_phone_otp.exs` — migration
- `lib/moth/auth/phone.ex` — phone normalization pure function
- `lib/moth/auth/phone_otp_code.ex` — Ecto schema for `phone_otp_codes`
- `lib/moth/auth/sms_provider.ex` — behaviour definition
- `lib/moth/auth/sms_provider/msg91.ex` — production SMS adapter
- `lib/moth/auth/sms_provider/log.ex` — dev SMS adapter
- `lib/moth/auth/sms_provider/test.ex` — test SMS adapter

**Modified backend files:**
- `lib/moth/auth/user.ex` — add phone field, update changesets, update Jason.Encoder
- `lib/moth/auth/auth.ex` — add `request_phone_otp/1`, `verify_phone_otp/2`, `get_user_by_phone/1`
- `lib/moth_web/controllers/api/auth_controller.ex` — add `request_otp/2`, `verify_otp/2`
- `lib/moth_web/router.ex` — add two OTP routes
- `config/dev.exs` — SMS provider config
- `config/test.exs` — SMS provider config
- `config/runtime.exs` — production SMS provider + MSG91 keys

**New test files:**
- `test/moth/auth/phone_test.exs`
- `test/moth/auth/phone_otp_code_test.exs`
- `test/moth/auth/user_test.exs`

**Modified test files:**
- `test/support/fixtures/auth_fixtures.ex` — add `phone_user_fixture/1`, `unique_user_phone/0`
- `test/moth/auth/auth_test.exs` — add OTP context tests
- `test/moth_web/controllers/api/auth_controller_test.exs` — add OTP endpoint tests

**Modified frontend files:**
- `assets/js/types/domain.ts` — add `phone` to `User`
- `assets/js/api/client.ts` — add `requestOtp`, `verifyOtp`
- `assets/js/pages/Auth.vue` — phone tab + 3-state OTP flow

---

### Task 1: Database Migration

**Files:**
- Create: `priv/repo/migrations/<ts>_add_phone_otp.exs`

- [ ] **Step 1: Create the migration file**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix ecto.gen.migration add_phone_otp`

- [ ] **Step 2: Write the migration**

Replace the generated migration contents with:

```elixir
defmodule Moth.Repo.Migrations.AddPhoneOtp do
  use Ecto.Migration

  def change do
    # Add phone to users, make email nullable
    alter table(:users) do
      add :phone, :string, size: 20
      modify :email, :string, null: true, from: {:string, null: false}
    end

    create unique_index(:users, [:phone])

    # OTP codes table
    create table(:phone_otp_codes) do
      add :phone, :string, size: 20, null: false
      add :hashed_code, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime
      add :attempt_count, :integer, null: false, default: 0

      timestamps(updated_at: false)
    end

    create index(:phone_otp_codes, [:phone, :expires_at])
  end
end
```

- [ ] **Step 3: Run the migration**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix ecto.migrate`

Expected: migration succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add priv/repo/migrations/*_add_phone_otp.exs
git commit -m "feat: add phone column to users and phone_otp_codes table"
```

---

### Task 2: Phone Normalization Module

**Files:**
- Create: `lib/moth/auth/phone.ex`
- Create: `test/moth/auth/phone_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/moth/auth/phone_test.exs`:

```elixir
defmodule Moth.Auth.PhoneTest do
  use ExUnit.Case, async: true

  alias Moth.Auth.Phone

  describe "normalize/1" do
    test "bare 10-digit Indian number gets +91 prefix" do
      assert {:ok, "+919876543210"} = Phone.normalize("9876543210")
    end

    test "already E.164 passes through" do
      assert {:ok, "+919876543210"} = Phone.normalize("+919876543210")
    end

    test "strips spaces and dashes" do
      assert {:ok, "+919876543210"} = Phone.normalize("98765 43210")
      assert {:ok, "+919876543210"} = Phone.normalize("98765-43210")
      assert {:ok, "+919876543210"} = Phone.normalize("+91 98765 43210")
    end

    test "strips parentheses" do
      assert {:ok, "+919876543210"} = Phone.normalize("(+91) 98765 43210")
    end

    test "91 prefix without + gets corrected" do
      assert {:ok, "+919876543210"} = Phone.normalize("919876543210")
    end

    test "rejects numbers starting with 0-5" do
      assert {:error, :invalid_phone} = Phone.normalize("5876543210")
      assert {:error, :invalid_phone} = Phone.normalize("0876543210")
    end

    test "rejects too short numbers" do
      assert {:error, :invalid_phone} = Phone.normalize("98765")
    end

    test "rejects too long numbers" do
      assert {:error, :invalid_phone} = Phone.normalize("98765432101234")
    end

    test "rejects alphabetic input" do
      assert {:error, :invalid_phone} = Phone.normalize("abcdefghij")
    end

    test "rejects non-Indian country codes" do
      assert {:error, :invalid_phone} = Phone.normalize("+14155551234")
      assert {:error, :invalid_phone} = Phone.normalize("+449876543210")
    end

    test "rejects empty and nil" do
      assert {:error, :invalid_phone} = Phone.normalize("")
      assert {:error, :invalid_phone} = Phone.normalize(nil)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix test test/moth/auth/phone_test.exs`

Expected: compilation error — `Moth.Auth.Phone` module not found.

- [ ] **Step 3: Implement the module**

Create `lib/moth/auth/phone.ex`:

```elixir
defmodule Moth.Auth.Phone do
  @moduledoc "Phone number normalization and validation for Indian mobile numbers."

  @indian_mobile_regex ~r/^\+91[6-9]\d{9}$/

  @doc """
  Normalizes a phone number to E.164 format (+91XXXXXXXXXX).

  Strips whitespace, dashes, parentheses. Prepends +91 if bare 10-digit Indian number.
  Only Indian mobile numbers (starting with 6/7/8/9) are accepted.

  Returns `{:ok, normalized}` or `{:error, :invalid_phone}`.
  """
  def normalize(nil), do: {:error, :invalid_phone}
  def normalize(""), do: {:error, :invalid_phone}

  def normalize(phone) when is_binary(phone) do
    cleaned =
      phone
      |> String.replace(~r/[\s\-\(\)]/, "")

    normalized =
      cond do
        # Already E.164: +91XXXXXXXXXX
        String.starts_with?(cleaned, "+") ->
          cleaned

        # 91 prefix without +: 91XXXXXXXXXX (12 digits)
        String.starts_with?(cleaned, "91") and byte_size(cleaned) == 12 ->
          "+" <> cleaned

        # Bare 10-digit number
        byte_size(cleaned) == 10 ->
          "+91" <> cleaned

        true ->
          cleaned
      end

    if Regex.match?(@indian_mobile_regex, normalized) do
      {:ok, normalized}
    else
      {:error, :invalid_phone}
    end
  end

  def normalize(_), do: {:error, :invalid_phone}
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix test test/moth/auth/phone_test.exs`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/moth/auth/phone.ex test/moth/auth/phone_test.exs
git commit -m "feat: add phone number normalization module with tests"
```

---

### Task 3: PhoneOtpCode Ecto Schema

**Files:**
- Create: `lib/moth/auth/phone_otp_code.ex`
- Create: `test/moth/auth/phone_otp_code_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/moth/auth/phone_otp_code_test.exs`:

```elixir
defmodule Moth.Auth.PhoneOtpCodeTest do
  use Moth.DataCase, async: true

  alias Moth.Auth.PhoneOtpCode

  describe "changeset/2" do
    test "valid attrs produce valid changeset" do
      attrs = %{
        phone: "+919876543210",
        hashed_code: :crypto.hash(:sha256, "123456"),
        expires_at: DateTime.add(DateTime.utc_now(), 600)
      }

      changeset = PhoneOtpCode.changeset(%PhoneOtpCode{}, attrs)
      assert changeset.valid?
    end

    test "requires phone" do
      attrs = %{
        hashed_code: :crypto.hash(:sha256, "123456"),
        expires_at: DateTime.add(DateTime.utc_now(), 600)
      }

      changeset = PhoneOtpCode.changeset(%PhoneOtpCode{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).phone
    end

    test "requires hashed_code" do
      attrs = %{
        phone: "+919876543210",
        expires_at: DateTime.add(DateTime.utc_now(), 600)
      }

      changeset = PhoneOtpCode.changeset(%PhoneOtpCode{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).hashed_code
    end

    test "requires expires_at" do
      attrs = %{
        phone: "+919876543210",
        hashed_code: :crypto.hash(:sha256, "123456")
      }

      changeset = PhoneOtpCode.changeset(%PhoneOtpCode{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).expires_at
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix test test/moth/auth/phone_otp_code_test.exs`

Expected: compilation error — `Moth.Auth.PhoneOtpCode` not found.

- [ ] **Step 3: Implement the schema**

Create `lib/moth/auth/phone_otp_code.ex`:

```elixir
defmodule Moth.Auth.PhoneOtpCode do
  use Ecto.Schema
  import Ecto.Changeset

  schema "phone_otp_codes" do
    field :phone, :string
    field :hashed_code, :binary
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime
    field :attempt_count, :integer, default: 0

    timestamps(updated_at: false)
  end

  def changeset(otp_code, attrs) do
    otp_code
    |> cast(attrs, [:phone, :hashed_code, :expires_at])
    |> validate_required([:phone, :hashed_code, :expires_at])
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix test test/moth/auth/phone_otp_code_test.exs`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/moth/auth/phone_otp_code.ex test/moth/auth/phone_otp_code_test.exs
git commit -m "feat: add PhoneOtpCode Ecto schema with tests"
```

---

### Task 4: User Schema Changes

**Files:**
- Modify: `lib/moth/auth/user.ex`
- Create: `test/moth/auth/user_test.exs`
- Modify: `test/support/fixtures/auth_fixtures.ex`

- [ ] **Step 1: Write failing tests**

Create `test/moth/auth/user_test.exs`:

```elixir
defmodule Moth.Auth.UserTest do
  use Moth.DataCase, async: true

  alias Moth.Auth.User

  describe "changeset/2" do
    test "accepts email-only user (regression)" do
      changeset = User.changeset(%User{}, %{email: "test@example.com", name: "Test"})
      assert changeset.valid?
    end

    test "accepts phone-only user" do
      changeset = User.changeset(%User{}, %{phone: "+919876543210", name: "Test"})
      assert changeset.valid?
    end

    test "accepts user with both email and phone" do
      changeset = User.changeset(%User{}, %{email: "test@example.com", phone: "+919876543210", name: "Test"})
      assert changeset.valid?
    end

    test "rejects user with neither phone nor email" do
      changeset = User.changeset(%User{}, %{name: "Test"})
      refute changeset.valid?
      assert "must have at least a phone or email" in errors_on(changeset).base
    end

    test "validates email format when present" do
      changeset = User.changeset(%User{}, %{email: "bad", name: "Test"})
      refute changeset.valid?
      assert errors_on(changeset).email != []
    end

    test "allows updating name on phone-only user" do
      user = %User{phone: "+919876543210", name: "+919876543210"}
      changeset = User.changeset(user, %{name: "Priya"})
      assert changeset.valid?
    end
  end

  describe "phone_registration_changeset/2" do
    test "accepts valid Indian phone" do
      changeset = User.phone_registration_changeset(%User{}, %{phone: "+919876543210", name: "+919876543210"})
      assert changeset.valid?
    end

    test "requires phone" do
      changeset = User.phone_registration_changeset(%User{}, %{name: "Test"})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).phone
    end

    test "rejects invalid Indian number" do
      changeset = User.phone_registration_changeset(%User{}, %{phone: "+915876543210", name: "Test"})
      refute changeset.valid?
      assert errors_on(changeset).phone != []
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix test test/moth/auth/user_test.exs`

Expected: failures — `phone_registration_changeset` not defined, `changeset` still requires email.

- [ ] **Step 3: Update User schema**

Modify `lib/moth/auth/user.ex` to:

```elixir
defmodule Moth.Auth.User do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :email, :name, :avatar_url, :phone]}
  schema "users" do
    field :email, :string
    field :name, :string
    field :avatar_url, :string
    field :phone, :string

    has_many :identities, Moth.Auth.UserIdentity
    has_many :tokens, Moth.Auth.UserToken

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :avatar_url, :phone])
    |> validate_required([:name])
    |> maybe_validate_email()
    |> validate_contact_present()
    |> unique_constraint(:email)
    |> unique_constraint(:phone)
  end

  def phone_registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:phone, :name])
    |> validate_required([:phone, :name])
    |> validate_format(:phone, ~r/^\+91[6-9]\d{9}$/, message: "must be a valid Indian mobile number")
    |> unique_constraint(:phone)
  end

  defp maybe_validate_email(changeset) do
    case get_field(changeset, :email) do
      nil -> changeset
      _ -> validate_format(changeset, :email, ~r/^[^\s]+@[^\s]+$/)
    end
  end

  defp validate_contact_present(changeset) do
    email = get_field(changeset, :email)
    phone = get_field(changeset, :phone)

    if is_nil(email) and is_nil(phone) do
      add_error(changeset, :base, "must have at least a phone or email")
    else
      changeset
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix test test/moth/auth/user_test.exs`

Expected: all tests pass.

- [ ] **Step 5: Verify no regressions in existing tests**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix test test/moth/auth/auth_test.exs`

Expected: all existing auth tests still pass.

- [ ] **Step 6: Update auth fixtures**

Modify `test/support/fixtures/auth_fixtures.ex`:

```elixir
defmodule Moth.AuthFixtures do
  @moduledoc "Test helpers for creating auth entities."

  alias Moth.Auth

  def unique_user_email, do: "user#{System.unique_integer([:positive])}@example.com"
  def unique_user_phone, do: "+91#{Enum.random(6..9)}#{:rand.uniform(999_999_999) |> Integer.to_string() |> String.pad_leading(9, "0")}"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      name: "Test User",
      avatar_url: "https://example.com/avatar.png"
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Auth.register()

    user
  end

  def phone_user_fixture(attrs \\ %{}) do
    phone = attrs[:phone] || unique_user_phone()

    {:ok, user} =
      %Moth.Auth.User{}
      |> Moth.Auth.User.phone_registration_changeset(%{phone: phone, name: phone})
      |> Moth.Repo.insert()

    user
  end
end
```

- [ ] **Step 7: Run full test suite**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix test`

Expected: all tests pass (no regressions).

- [ ] **Step 8: Commit**

```bash
git add lib/moth/auth/user.ex test/moth/auth/user_test.exs test/support/fixtures/auth_fixtures.ex
git commit -m "feat: make email optional on User, add phone field and phone_registration_changeset"
```

---

### Task 5: SMS Provider Behaviour + Adapters

**Files:**
- Create: `lib/moth/auth/sms_provider.ex`
- Create: `lib/moth/auth/sms_provider/msg91.ex`
- Create: `lib/moth/auth/sms_provider/log.ex`
- Create: `lib/moth/auth/sms_provider/test.ex`
- Modify: `config/dev.exs`
- Modify: `config/test.exs`
- Modify: `config/runtime.exs`

- [ ] **Step 1: Create the behaviour**

Create `lib/moth/auth/sms_provider.ex`:

```elixir
defmodule Moth.Auth.SMSProvider do
  @moduledoc "Behaviour for SMS delivery. Swapped per environment."

  @callback deliver_otp(phone :: String.t(), code :: String.t()) :: :ok | {:error, term()}

  def deliver_otp(phone, code) do
    impl().deliver_otp(phone, code)
  end

  defp impl do
    Application.get_env(:moth, :sms_provider, Moth.Auth.SMSProvider.Log)
  end
end
```

- [ ] **Step 2: Create the Log adapter (dev)**

Create `lib/moth/auth/sms_provider/log.ex`:

```elixir
defmodule Moth.Auth.SMSProvider.Log do
  @moduledoc "Dev adapter — logs OTP to console."
  @behaviour Moth.Auth.SMSProvider

  require Logger

  @impl true
  def deliver_otp(phone, code) do
    Logger.info("[dev] OTP for #{phone}: #{code}")
    :ok
  end
end
```

- [ ] **Step 3: Create the Test adapter**

Create `lib/moth/auth/sms_provider/test.ex`:

```elixir
defmodule Moth.Auth.SMSProvider.Test do
  @moduledoc "Test adapter — sends message to calling process."
  @behaviour Moth.Auth.SMSProvider

  @impl true
  def deliver_otp(phone, code) do
    send(self(), {:otp_sent, phone, code})
    :ok
  end
end
```

- [ ] **Step 4: Create the MSG91 adapter (production)**

Create `lib/moth/auth/sms_provider/msg91.ex`:

```elixir
defmodule Moth.Auth.SMSProvider.MSG91 do
  @moduledoc "Production adapter — sends OTP via MSG91 HTTP API."
  @behaviour Moth.Auth.SMSProvider

  require Logger

  @url "https://api.msg91.com/api/v5/otp"

  @impl true
  def deliver_otp(phone, code) do
    config = Application.get_env(:moth, :msg91)
    auth_key = Keyword.fetch!(config, :auth_key)
    template_id = Keyword.fetch!(config, :template_id)

    # MSG91 expects mobile without leading '+'
    mobile = String.trim_leading(phone, "+")

    body =
      Jason.encode!(%{
        "authkey" => auth_key,
        "template_id" => template_id,
        "mobile" => mobile,
        "otp" => code
      })

    request =
      Finch.build(:post, @url, [{"Content-Type", "application/json"}], body)

    case Finch.request(request, Moth.Finch) do
      {:ok, %Finch.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Finch.Response{status: status, body: resp_body}} ->
        Logger.error("MSG91 OTP delivery failed: status=#{status} body=#{resp_body}")
        {:error, :sms_delivery_failed}

      {:error, reason} ->
        Logger.error("MSG91 OTP delivery error: #{inspect(reason)}")
        {:error, :sms_delivery_failed}
    end
  end
end
```

- [ ] **Step 5: Add Finch to application supervisor (if not already present)**

Check `lib/moth/application.ex` for `{Finch, name: Moth.Finch}` in the children list. If missing, add it:

```elixir
# In the children list of lib/moth/application.ex:
{Finch, name: Moth.Finch}
```

- [ ] **Step 6: Update config files**

Append to `config/dev.exs`:

```elixir
config :moth, :sms_provider, Moth.Auth.SMSProvider.Log
```

Append to `config/test.exs`:

```elixir
config :moth, :sms_provider, Moth.Auth.SMSProvider.Test
```

Add to `config/runtime.exs` inside the `if config_env() == :prod do` block, after the Ueberauth config:

```elixir
  config :moth, :sms_provider, Moth.Auth.SMSProvider.MSG91
  config :moth, :msg91,
    auth_key: System.get_env("MSG91_AUTH_KEY") || raise("MSG91_AUTH_KEY not set"),
    template_id: System.get_env("MSG91_TEMPLATE_ID") || raise("MSG91_TEMPLATE_ID not set")
```

- [ ] **Step 7: Verify compilation**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix compile --warnings-as-errors`

Expected: compiles with no errors.

- [ ] **Step 8: Commit**

```bash
git add lib/moth/auth/sms_provider.ex lib/moth/auth/sms_provider/ config/dev.exs config/test.exs config/runtime.exs lib/moth/application.ex
git commit -m "feat: add SMSProvider behaviour with MSG91, Log, and Test adapters"
```

---

### Task 6: Auth Context — OTP Functions

**Files:**
- Modify: `lib/moth/auth/auth.ex`
- Modify: `test/moth/auth/auth_test.exs`

- [ ] **Step 1: Write failing tests for request_phone_otp**

Append to `test/moth/auth/auth_test.exs`, inside the module but after existing describes. First, update the alias line at the top of the module from:

```elixir
alias Moth.Auth.{User, UserToken}
```

to:

```elixir
alias Moth.Auth.{User, UserToken, PhoneOtpCode}
```

Then add these test blocks:

```elixir
  describe "request_phone_otp/1" do
    test "creates OTP record and returns :ok" do
      assert :ok = Auth.request_phone_otp("+919876543210")
      assert_received {:otp_sent, "+919876543210", code}
      assert String.length(code) == 6
      assert String.match?(code, ~r/^\d{6}$/)
    end

    test "invalidates previous unexpired OTPs on resend" do
      assert :ok = Auth.request_phone_otp("+919876543210")
      assert :ok = Auth.request_phone_otp("+919876543210")

      # Only one active (unused) OTP should exist
      active =
        Repo.all(
          from o in Moth.Auth.PhoneOtpCode,
            where: o.phone == "+919876543210" and is_nil(o.used_at)
        )

      assert length(active) == 1
    end

    test "rate-limits at 3 requests per 10 minutes" do
      phone = "+919876543210"
      assert :ok = Auth.request_phone_otp(phone)
      assert :ok = Auth.request_phone_otp(phone)
      assert :ok = Auth.request_phone_otp(phone)
      assert {:error, :rate_limited} = Auth.request_phone_otp(phone)
    end

    test "returns :ok even for unknown phones (anti-enumeration)" do
      assert :ok = Auth.request_phone_otp("+919999999999")
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix test test/moth/auth/auth_test.exs --only describe:"request_phone_otp/1"`

Expected: failures — `request_phone_otp/1` not defined.

- [ ] **Step 3: Implement request_phone_otp/1**

Add to `lib/moth/auth/auth.ex`, after the existing `## Helpers` section at the bottom (before the final `end`):

```elixir
  ## Phone OTP

  alias Moth.Auth.{Phone, PhoneOtpCode}

  @otp_expiry_seconds 600
  @otp_rate_limit 3

  def request_phone_otp(phone) do
    with {:ok, normalized} <- Phone.normalize(phone) do
      # Invalidate old unexpired OTPs for this phone
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      from(o in PhoneOtpCode,
        where: o.phone == ^normalized and is_nil(o.used_at) and o.expires_at > ^now
      )
      |> Repo.update_all(set: [used_at: now])

      # Rate-limit: count OTPs inserted in last 10 minutes
      ten_min_ago = DateTime.add(now, -@otp_expiry_seconds)

      count =
        Repo.one(
          from o in PhoneOtpCode,
            where: o.phone == ^normalized and o.inserted_at > ^ten_min_ago,
            select: count(o.id)
        )

      if count >= @otp_rate_limit do
        {:error, :rate_limited}
      else
        code = generate_otp_code()
        hashed = :crypto.hash(:sha256, code)
        expires_at = DateTime.add(now, @otp_expiry_seconds)

        %PhoneOtpCode{}
        |> PhoneOtpCode.changeset(%{
          phone: normalized,
          hashed_code: hashed,
          expires_at: expires_at
        })
        |> Repo.insert!()

        case Moth.Auth.SMSProvider.deliver_otp(normalized, code) do
          :ok -> :ok
          {:error, _reason} -> {:error, :sms_delivery_failed}
        end
      end
    end
  end

  defp generate_otp_code do
    :crypto.strong_rand_bytes(4)
    |> :binary.decode_unsigned()
    |> rem(900_000)
    |> Kernel.+(100_000)
    |> Integer.to_string()
  end
```

- [ ] **Step 4: Run request tests to verify they pass**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix test test/moth/auth/auth_test.exs --only describe:"request_phone_otp/1"`

Expected: all pass.

- [ ] **Step 5: Write failing tests for verify_phone_otp**

Append to `test/moth/auth/auth_test.exs`:

```elixir
  describe "verify_phone_otp/2" do
    test "correct code for new phone creates user and returns needs_name: true" do
      phone = "+919876543210"
      :ok = Auth.request_phone_otp(phone)
      assert_received {:otp_sent, ^phone, code}

      assert {:ok, %{user: user, token: token, needs_name: true}} =
               Auth.verify_phone_otp(phone, code)

      assert user.phone == phone
      assert user.name == phone
      assert is_binary(token)
    end

    test "correct code for existing phone user returns needs_name: false" do
      phone = "+919876543210"

      {:ok, existing} =
        %User{}
        |> User.phone_registration_changeset(%{phone: phone, name: "Priya"})
        |> Repo.insert()

      :ok = Auth.request_phone_otp(phone)
      assert_received {:otp_sent, ^phone, code}

      assert {:ok, %{user: user, token: _token, needs_name: false}} =
               Auth.verify_phone_otp(phone, code)

      assert user.id == existing.id
    end

    test "wrong code returns error with attempts_remaining" do
      phone = "+919876543210"
      :ok = Auth.request_phone_otp(phone)
      assert_received {:otp_sent, ^phone, _code}

      assert {:error, :invalid_otp, 2} = Auth.verify_phone_otp(phone, "000000")
      assert {:error, :invalid_otp, 1} = Auth.verify_phone_otp(phone, "000000")
      assert {:error, :invalid_otp, 0} = Auth.verify_phone_otp(phone, "000000")
    end

    test "exhausted attempts returns too_many_attempts" do
      phone = "+919876543210"
      :ok = Auth.request_phone_otp(phone)
      assert_received {:otp_sent, ^phone, code}

      # Exhaust 3 attempts
      Auth.verify_phone_otp(phone, "000000")
      Auth.verify_phone_otp(phone, "000000")
      Auth.verify_phone_otp(phone, "000000")

      # 4th attempt with correct code still fails
      assert {:error, :too_many_attempts} = Auth.verify_phone_otp(phone, code)
    end

    test "expired OTP returns invalid_otp" do
      phone = "+919876543210"
      :ok = Auth.request_phone_otp(phone)
      assert_received {:otp_sent, ^phone, code}

      # Manually expire the OTP
      Repo.update_all(
        from(o in PhoneOtpCode, where: o.phone == ^phone),
        set: [expires_at: DateTime.add(DateTime.utc_now(), -1)]
      )

      assert {:error, :invalid_otp} = Auth.verify_phone_otp(phone, code)
    end

    test "already-used OTP returns invalid_otp" do
      phone = "+919876543210"
      :ok = Auth.request_phone_otp(phone)
      assert_received {:otp_sent, ^phone, code}

      assert {:ok, _} = Auth.verify_phone_otp(phone, code)
      assert {:error, :invalid_otp} = Auth.verify_phone_otp(phone, code)
    end
  end
```

- [ ] **Step 6: Run verify tests to verify they fail**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix test test/moth/auth/auth_test.exs --only describe:"verify_phone_otp/2"`

Expected: failures — `verify_phone_otp/2` not defined.

- [ ] **Step 7: Implement verify_phone_otp/2**

Add to `lib/moth/auth/auth.ex`, after `request_phone_otp/1`:

```elixir
  def verify_phone_otp(phone, code) do
    with {:ok, normalized} <- Phone.normalize(phone) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.transaction(fn ->
        # Lock the most recent active OTP row
        otp_record =
          Repo.one(
            from(o in PhoneOtpCode,
              where: o.phone == ^normalized and o.expires_at > ^now and is_nil(o.used_at),
              order_by: [desc: o.inserted_at],
              limit: 1,
              lock: "FOR UPDATE"
            )
          )

        case otp_record do
          nil ->
            Repo.rollback({:error, :invalid_otp})

          %{attempt_count: attempts} when attempts >= 3 ->
            Repo.rollback({:error, :too_many_attempts})

          record ->
            hashed_input = :crypto.hash(:sha256, code)

            if hashed_input == record.hashed_code do
              # Mark as used
              record
              |> Ecto.Changeset.change(used_at: now)
              |> Repo.update!()

              # Find or create user
              {user, needs_name} = find_or_create_phone_user(normalized)
              {token, _} = generate_api_token(user)
              %{user: user, token: token, needs_name: needs_name}
            else
              # Increment attempt count
              new_count = record.attempt_count + 1

              record
              |> Ecto.Changeset.change(attempt_count: new_count)
              |> Repo.update!()

              Repo.rollback({:error, :invalid_otp, 3 - new_count})
            end
        end
      end)
      |> case do
        {:ok, result} -> {:ok, result}
        {:error, {:error, :invalid_otp}} -> {:error, :invalid_otp}
        {:error, {:error, :invalid_otp, remaining}} -> {:error, :invalid_otp, remaining}
        {:error, {:error, :too_many_attempts}} -> {:error, :too_many_attempts}
      end
    end
  end

  defp find_or_create_phone_user(phone) do
    case Repo.get_by(User, phone: phone) do
      %User{} = user ->
        # Existing user — needs_name is false (they already have an account)
        {user, false}

      nil ->
        {:ok, user} =
          %User{}
          |> User.phone_registration_changeset(%{phone: phone, name: phone})
          |> Repo.insert()

        {user, true}
    end
  end
```

- [ ] **Step 8: Run verify tests to verify they pass**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix test test/moth/auth/auth_test.exs --only describe:"verify_phone_otp/2"`

Expected: all pass.

- [ ] **Step 9: Run full auth test suite**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix test test/moth/auth/auth_test.exs`

Expected: all tests pass (old + new).

- [ ] **Step 10: Commit**

```bash
git add lib/moth/auth/auth.ex test/moth/auth/auth_test.exs
git commit -m "feat: add request_phone_otp and verify_phone_otp to Auth context"
```

---

### Task 7: Auth Controller — OTP Endpoints

**Files:**
- Modify: `lib/moth_web/controllers/api/auth_controller.ex`
- Modify: `lib/moth_web/router.ex`
- Modify: `test/moth_web/controllers/api/auth_controller_test.exs`

- [ ] **Step 1: Add routes**

In `lib/moth_web/router.ex`, inside the first `scope "/api", MothWeb.API` block (unauthenticated, around line 34), add after the existing auth routes:

```elixir
    post "/auth/otp/request", AuthController, :request_otp
    post "/auth/otp/verify", AuthController, :verify_otp
```

- [ ] **Step 2: Write failing controller tests**

Add these imports at the top of `test/moth_web/controllers/api/auth_controller_test.exs` (inside the module, after the existing `import`):

```elixir
  import Ecto.Query
```

Then append these test blocks inside the module:

```elixir
  describe "POST /api/auth/otp/request" do
    test "returns ok for valid phone", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/otp/request", %{phone: "9876543210"})
      assert %{"status" => "ok"} = json_response(conn, 200)
    end

    test "returns 422 for invalid phone", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/otp/request", %{phone: "123"})
      assert %{"error" => %{"code" => "invalid_phone"}} = json_response(conn, 422)
    end

    test "returns 429 when rate limited", %{conn: conn} do
      phone = "+919876543210"
      post(conn, ~p"/api/auth/otp/request", %{phone: phone})
      post(conn, ~p"/api/auth/otp/request", %{phone: phone})
      post(conn, ~p"/api/auth/otp/request", %{phone: phone})

      conn = post(conn, ~p"/api/auth/otp/request", %{phone: phone})
      assert %{"error" => %{"code" => "rate_limited"}} = json_response(conn, 429)
    end
  end

  describe "POST /api/auth/otp/verify" do
    test "correct code for new user returns token and needs_name: true", %{conn: conn} do
      phone = "+919876543210"
      post(conn, ~p"/api/auth/otp/request", %{phone: phone})
      assert_received {:otp_sent, ^phone, code}

      conn = post(conn, ~p"/api/auth/otp/verify", %{phone: phone, code: code})
      resp = json_response(conn, 200)
      assert resp["token"]
      assert resp["needs_name"] == true
      assert resp["user"]["phone"] == phone
    end

    test "correct code for existing user returns needs_name: false", %{conn: conn} do
      user = phone_user_fixture(%{phone: "+919876543210"})

      post(conn, ~p"/api/auth/otp/request", %{phone: user.phone})
      assert_received {:otp_sent, _, code}

      conn = post(conn, ~p"/api/auth/otp/verify", %{phone: user.phone, code: code})
      resp = json_response(conn, 200)
      assert resp["needs_name"] == false
      assert resp["user"]["id"] == user.id
    end

    test "wrong code returns 401 with attempts_remaining", %{conn: conn} do
      phone = "+919876543210"
      post(conn, ~p"/api/auth/otp/request", %{phone: phone})
      assert_received {:otp_sent, ^phone, _code}

      conn = post(conn, ~p"/api/auth/otp/verify", %{phone: phone, code: "000000"})
      resp = json_response(conn, 401)
      assert resp["error"]["code"] == "invalid_otp"
      assert resp["error"]["attempts_remaining"] == 2
    end

    test "exhausted attempts returns 429", %{conn: conn} do
      phone = "+919876543210"
      post(conn, ~p"/api/auth/otp/request", %{phone: phone})
      assert_received {:otp_sent, ^phone, _code}

      post(conn, ~p"/api/auth/otp/verify", %{phone: phone, code: "000000"})
      post(conn, ~p"/api/auth/otp/verify", %{phone: phone, code: "000000"})
      post(conn, ~p"/api/auth/otp/verify", %{phone: phone, code: "000000"})

      conn = post(conn, ~p"/api/auth/otp/verify", %{phone: phone, code: "000000"})
      assert %{"error" => %{"code" => "too_many_attempts"}} = json_response(conn, 429)
    end

    test "expired OTP returns 401", %{conn: conn} do
      phone = "+919876543210"
      post(conn, ~p"/api/auth/otp/request", %{phone: phone})
      assert_received {:otp_sent, ^phone, code}

      # Expire the OTP
      Moth.Repo.update_all(
        from(o in Moth.Auth.PhoneOtpCode, where: o.phone == ^phone),
        set: [expires_at: DateTime.add(DateTime.utc_now(), -1)]
      )

      conn = post(conn, ~p"/api/auth/otp/verify", %{phone: phone, code: code})
      assert %{"error" => %{"code" => "invalid_otp"}} = json_response(conn, 401)
    end

    test "token from OTP verify works for authenticated endpoints", %{conn: conn} do
      phone = "+919876543210"
      post(conn, ~p"/api/auth/otp/request", %{phone: phone})
      assert_received {:otp_sent, ^phone, code}

      conn = post(conn, ~p"/api/auth/otp/verify", %{phone: phone, code: code})
      %{"token" => token} = json_response(conn, 200)

      # Use the token to access an authenticated endpoint
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/user/me")

      assert %{"user" => %{"phone" => ^phone}} = json_response(conn, 200)
    end
  end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix test test/moth_web/controllers/api/auth_controller_test.exs`

Expected: failures — `request_otp` and `verify_otp` actions not defined.

- [ ] **Step 4: Implement controller actions**

Add to `lib/moth_web/controllers/api/auth_controller.ex`, before the `if Application.compile_env` block:

```elixir
  def request_otp(conn, %{"phone" => phone}) do
    case Auth.request_phone_otp(phone) do
      :ok ->
        json(conn, %{status: "ok"})

      {:error, :invalid_phone} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: "invalid_phone", message: "Please enter a valid Indian mobile number"}})

      {:error, :rate_limited} ->
        conn
        |> put_status(429)
        |> json(%{error: %{code: "rate_limited", message: "Too many OTP requests. Please wait a few minutes."}})

      {:error, :sms_delivery_failed} ->
        conn
        |> put_status(503)
        |> json(%{error: %{code: "sms_delivery_failed", message: "Could not send SMS. Please try again."}})
    end
  end

  def verify_otp(conn, %{"phone" => phone, "code" => code}) do
    case Auth.verify_phone_otp(phone, code) do
      {:ok, %{user: user, token: token, needs_name: needs_name}} ->
        json(conn, %{token: token, user: user, needs_name: needs_name})

      {:error, :invalid_phone} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: "invalid_phone", message: "Please enter a valid Indian mobile number"}})

      {:error, :invalid_otp} ->
        conn
        |> put_status(401)
        |> json(%{error: %{code: "invalid_otp", message: "Invalid or expired code"}})

      {:error, :invalid_otp, attempts_remaining} ->
        conn
        |> put_status(401)
        |> json(%{error: %{code: "invalid_otp", message: "Wrong code", attempts_remaining: attempts_remaining}})

      {:error, :too_many_attempts} ->
        conn
        |> put_status(429)
        |> json(%{error: %{code: "too_many_attempts", message: "Too many wrong attempts. Please request a new code."}})
    end
  end
```

- [ ] **Step 5: Run controller tests to verify they pass**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix test test/moth_web/controllers/api/auth_controller_test.exs`

Expected: all tests pass.

- [ ] **Step 6: Run full test suite**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix test`

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/moth_web/controllers/api/auth_controller.ex lib/moth_web/router.ex test/moth_web/controllers/api/auth_controller_test.exs
git commit -m "feat: add OTP request/verify API endpoints with integration tests"
```

---

### Task 8: Frontend — Types + API Client

**Files:**
- Modify: `assets/js/types/domain.ts`
- Modify: `assets/js/api/client.ts`

- [ ] **Step 1: Add phone to User type**

In `assets/js/types/domain.ts`, update the `User` interface:

```typescript
export interface User {
  id: string
  name: string
  email: string | null
  phone?: string | null
  avatar_url: string | null
}
```

- [ ] **Step 2: Add OTP methods to API client**

In `assets/js/api/client.ts`, add inside the `auth` object, after `devLogin`:

```typescript
    requestOtp: (phone: string) =>
      request<{ status: string }>('POST', '/auth/otp/request', { phone }),
    verifyOtp: (phone: string, code: string) =>
      request<{ token: string; user: User; needs_name: boolean }>('POST', '/auth/otp/verify', { phone, code }),
```

- [ ] **Step 3: Verify TypeScript compiles**

Run: `cd /Users/kiran/hashd/dev/alobmat/assets && npx tsc --noEmit`

Expected: no type errors.

- [ ] **Step 4: Commit**

```bash
git add assets/js/types/domain.ts assets/js/api/client.ts
git commit -m "feat: add phone to User type and OTP methods to API client"
```

---

### Task 9: Frontend — Auth.vue Phone OTP Flow

**Files:**
- Modify: `assets/js/pages/Auth.vue`

- [ ] **Step 1: Rewrite Auth.vue with phone OTP tab**

Replace the contents of `assets/js/pages/Auth.vue` with:

```vue
<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { api } from '@/api/client'
import InputField from '@/components/ui/InputField.vue'
import Button from '@/components/ui/Button.vue'
import SegmentedControl from '@/components/ui/SegmentedControl.vue'

const router = useRouter()
const route = useRoute()
const auth = useAuthStore()

const tab = ref<string>('phone')
const tabOptions = [
  { value: 'phone', label: 'Phone' },
  { value: 'email', label: 'Email' },
]

// Email state
const email = ref('')
const emailSent = ref(false)
const emailLoading = ref(false)
const emailError = ref('')

// Phone state
type PhoneStep = 'phone' | 'otp' | 'name'
const phoneStep = ref<PhoneStep>('phone')
const phone = ref('')
const otpCode = ref('')
const displayName = ref('')
const phoneLoading = ref(false)
const phoneError = ref('')
const resendCooldown = ref(0)
let resendTimer: ReturnType<typeof setInterval> | null = null

// Handle OAuth callback: /#/auth/callback?token=<t>
onMounted(async () => {
  const token = (route.query.token as string) ?? ''
  if (token) {
    window.history.replaceState({}, '', window.location.pathname)
    try {
      auth.token = token
      localStorage.setItem('auth_token', token)
      const { user: u } = await api.user.me()
      auth.login(u, token)
      router.replace((route.query.redirect as string) ?? '/')
    } catch {
      emailError.value = 'Token invalid. Please try again.'
    }
  }
})

// Email magic link
async function requestLink() {
  emailLoading.value = true
  emailError.value = ''
  try {
    await api.auth.requestMagicLink(email.value)
    emailSent.value = true
  } catch (e: any) {
    emailError.value = e.message
  } finally {
    emailLoading.value = false
  }
}

// Phone OTP
async function requestOtp() {
  phoneLoading.value = true
  phoneError.value = ''
  try {
    await api.auth.requestOtp(phone.value)
    phoneStep.value = 'otp'
    startResendCooldown()
  } catch (e: any) {
    const code = e.body?.error?.code
    if (code === 'invalid_phone') {
      phoneError.value = 'Please enter a valid Indian mobile number.'
    } else if (code === 'rate_limited') {
      phoneError.value = 'Too many attempts. Please wait a few minutes.'
    } else if (code === 'sms_delivery_failed') {
      phoneError.value = 'Could not send SMS. Please try again.'
    } else {
      phoneError.value = e.message
    }
  } finally {
    phoneLoading.value = false
  }
}

async function verifyOtp() {
  phoneLoading.value = true
  phoneError.value = ''
  try {
    const { token, user, needs_name } = await api.auth.verifyOtp(phone.value, otpCode.value)
    if (needs_name) {
      auth.token = token
      localStorage.setItem('auth_token', token)
      auth.login(user, token)
      phoneStep.value = 'name'
    } else {
      auth.login(user, token)
      router.replace((route.query.redirect as string) ?? '/')
    }
  } catch (e: any) {
    const code = e.body?.error?.code
    const remaining = e.body?.error?.attempts_remaining
    if (code === 'too_many_attempts') {
      phoneError.value = 'Too many wrong attempts. Please request a new code.'
    } else if (code === 'invalid_otp' && remaining !== undefined) {
      phoneError.value = `Wrong code. ${remaining} attempt${remaining === 1 ? '' : 's'} left.`
    } else {
      phoneError.value = 'Invalid or expired code.'
    }
  } finally {
    phoneLoading.value = false
  }
}

async function submitName() {
  phoneLoading.value = true
  phoneError.value = ''
  try {
    await auth.updateProfile({ name: displayName.value })
    router.replace((route.query.redirect as string) ?? '/')
  } catch (e: any) {
    phoneError.value = e.message
  } finally {
    phoneLoading.value = false
  }
}

function startResendCooldown() {
  resendCooldown.value = 30
  if (resendTimer) clearInterval(resendTimer)
  resendTimer = setInterval(() => {
    resendCooldown.value--
    if (resendCooldown.value <= 0 && resendTimer) {
      clearInterval(resendTimer)
      resendTimer = null
    }
  }, 1000)
}

async function resendOtp() {
  phoneError.value = ''
  try {
    await api.auth.requestOtp(phone.value)
    otpCode.value = ''
    startResendCooldown()
  } catch (e: any) {
    const code = e.body?.error?.code
    if (code === 'rate_limited') {
      phoneError.value = 'Too many attempts. Please wait a few minutes.'
    } else {
      phoneError.value = 'Could not resend. Please try again.'
    }
  }
}

function maskedPhone() {
  if (phone.value.length >= 10) {
    const digits = phone.value.replace(/\D/g, '').slice(-10)
    return `+91 ${digits.slice(0, 5)} ${digits.slice(5)}`
  }
  return phone.value
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center p-4">
    <div class="w-full max-w-sm">
      <h1 class="mb-8 text-center text-3xl font-bold">Moth</h1>

      <SegmentedControl v-model="tab" :options="tabOptions" class="mb-6" />

      <!-- Phone tab -->
      <template v-if="tab === 'phone'">
        <!-- Step 1: Phone entry -->
        <form v-if="phoneStep === 'phone'" @submit.prevent="requestOtp" class="flex flex-col gap-4">
          <InputField
            v-model="phone"
            label="Mobile number"
            type="tel"
            inputmode="numeric"
            placeholder="98765 43210"
            :error="phoneError"
          />
          <Button type="submit" :loading="phoneLoading">Send OTP</Button>
        </form>

        <!-- Step 2: OTP entry -->
        <form v-else-if="phoneStep === 'otp'" @submit.prevent="verifyOtp" class="flex flex-col gap-4">
          <p class="text-sm text-[--text-secondary]">Enter the 6-digit code sent to {{ maskedPhone() }}</p>
          <InputField
            v-model="otpCode"
            label="OTP Code"
            type="text"
            inputmode="numeric"
            maxlength="6"
            autocomplete="one-time-code"
            placeholder="123456"
            :error="phoneError"
          />
          <Button type="submit" :loading="phoneLoading">Verify</Button>
          <button
            type="button"
            :disabled="resendCooldown > 0"
            @click="resendOtp"
            class="text-center text-sm text-[--text-secondary] hover:text-[--text-primary] disabled:opacity-50"
          >
            {{ resendCooldown > 0 ? `Resend code in ${resendCooldown}s` : 'Resend code' }}
          </button>
        </form>

        <!-- Step 3: Name entry -->
        <form v-else-if="phoneStep === 'name'" @submit.prevent="submitName" class="flex flex-col gap-4">
          <p class="text-sm text-[--text-secondary]">What should we call you?</p>
          <InputField
            v-model="displayName"
            label="Display name"
            type="text"
            placeholder="Your name"
            :error="phoneError"
          />
          <Button type="submit" :loading="phoneLoading" :disabled="displayName.trim().length < 2">
            Start playing
          </Button>
        </form>
      </template>

      <!-- Email tab -->
      <template v-else>
        <div v-if="emailSent" class="text-center text-[--text-secondary]">
          Check your email for a sign-in link.
        </div>
        <form v-else @submit.prevent="requestLink" class="flex flex-col gap-4">
          <InputField v-model="email" label="Email" type="email" placeholder="you@example.com" :error="emailError" />
          <Button type="submit" :loading="emailLoading">Send magic link</Button>
          <a href="/auth/google" class="text-center text-sm text-[--text-secondary] hover:text-[--text-primary]">Continue with Google</a>
        </form>
      </template>
    </div>
  </div>
</template>
```

- [ ] **Step 2: Verify TypeScript compiles**

Run: `cd /Users/kiran/hashd/dev/alobmat/assets && npx tsc --noEmit`

Expected: no type errors.

- [ ] **Step 3: Verify the dev server starts**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix phx.server` (manual check — visit localhost:4000, see phone/email tabs on login page).

- [ ] **Step 4: Commit**

```bash
git add assets/js/pages/Auth.vue
git commit -m "feat: add phone OTP login flow to Auth page with 3-state UI"
```

---

### Task 10: Full Integration Smoke Test

- [ ] **Step 1: Run full backend test suite**

Run: `cd /Users/kiran/hashd/dev/alobmat && mix test`

Expected: all tests pass.

- [ ] **Step 2: Run frontend type check**

Run: `cd /Users/kiran/hashd/dev/alobmat/assets && npx tsc --noEmit`

Expected: no errors.

- [ ] **Step 3: Run frontend tests (if any exist)**

Run: `cd /Users/kiran/hashd/dev/alobmat/assets && npx vitest run`

Expected: passes (or no tests found yet).

- [ ] **Step 4: Final commit (if any uncommitted changes remain)**

```bash
git status
# If clean, nothing to do. Otherwise commit remaining changes.
```

---

## Summary of commits

1. `feat: add phone column to users and phone_otp_codes table`
2. `feat: add phone number normalization module with tests`
3. `feat: add PhoneOtpCode Ecto schema with tests`
4. `feat: make email optional on User, add phone field and phone_registration_changeset`
5. `feat: add SMSProvider behaviour with MSG91, Log, and Test adapters`
6. `feat: add request_phone_otp and verify_phone_otp to Auth context`
7. `feat: add OTP request/verify API endpoints with integration tests`
8. `feat: add phone to User type and OTP methods to API client`
9. `feat: add phone OTP login flow to Auth page with 3-state UI`
