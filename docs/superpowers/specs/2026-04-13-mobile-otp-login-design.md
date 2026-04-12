# Mobile OTP Login Design

**Date:** 2026-04-13  
**Status:** Approved  
**Feature branch:** `feature/mobile-otp-login`

## Context

Moth is a mobile-first Tambola game. Most players access it on their phones, where entering an email address is friction-heavy. This design adds SMS OTP as a first-class login and sign-up method so players can authenticate using only their mobile number.

## Goals

- Allow users to sign up and log in using just a phone number + 6-digit OTP
- Email remains supported (magic link, Google OAuth) but is now optional
- New users who sign up via phone are prompted for a display name after OTP verification
- Minimal changes to existing auth infrastructure

## Out of Scope

- Linking phone to an existing email account (no existing users, not needed now)
- WhatsApp OTP delivery
- iOS/Android SMS auto-fill (nice-to-have, not blocking)
- Non-Indian phone numbers (only +91 numbers supported for now)

**Known limitation:** If the same person signs up via phone OTP and later via email magic link, they will get two separate user accounts. Account linking/merging is deferred to a future iteration.

---

## Data Model

### `users` table changes

Add a `phone` column:

```sql
ALTER TABLE users ADD COLUMN phone varchar(20) UNIQUE;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
```

- E.164 format (`+919876543210`)
- Optional (nullable) — users can have phone only, email only, or both
- Unique index
- `email` column becomes nullable (remove `NOT NULL` constraint)

**Invariant (enforced in context, not DB):** every user must have at least one of `phone` or `email`.

#### `User` schema changes (`lib/moth/auth/user.ex`)

- Add `field :phone, :string` to schema
- Add `:phone` to `@derive {Jason.Encoder, only: [...]}` so it appears in API responses
- Replace the single `changeset/2` with two paths:
  - **`changeset/2`** (general update) — casts `[:email, :name, :avatar_url, :phone]`, validates that at least one of `email` or `phone` is present, validates email format if present, validates phone format if present
  - **`phone_registration_changeset/2`** — casts `[:phone, :name]`, requires `[:phone]`, validates phone is a 10-digit Indian mobile number (E.164 `+91` prefix + starts with 6/7/8/9). Used only when creating a new user from OTP verify.
- The existing magic link registration path continues to use `changeset/2` with email — no regression.

### New `phone_otp_codes` table

```sql
CREATE TABLE phone_otp_codes (
  id            bigserial PRIMARY KEY,
  phone         varchar(20)  NOT NULL,
  hashed_code   bytea        NOT NULL,
  expires_at    timestamptz  NOT NULL,
  used_at       timestamptz,
  attempt_count integer      NOT NULL DEFAULT 0,
  inserted_at   timestamptz  NOT NULL
);

CREATE INDEX ON phone_otp_codes (phone, expires_at);
```

- `hashed_code` — SHA-256 of the 6-digit numeric OTP (never stored in plaintext)
- `attempt_count` — incremented on each wrong guess; record is exhausted at 3
- `used_at` — set on successful verification OR when invalidated by a resend; `NULL` means active
- No `user_id` — this table is pre-authentication; user lookup happens at verify time

### Expired row cleanup

A periodic task (Oban job or simple `Process.send_after` loop in application supervisor) deletes `phone_otp_codes` rows where `expires_at < now - 1 hour`. Runs every 30 minutes. Not blocking for v1 — can ship without it and add later if table size becomes a concern.

---

## Phone Number Normalization

All phone inputs are normalized server-side before any DB operation:

1. Strip whitespace, dashes, parentheses
2. If bare 10-digit number starting with `6|7|8|9` → prepend `+91`
3. If starts with `91` (12 digits) → prepend `+`
4. Validate result matches `+91[6-9]\d{9}` (exactly 13 characters)
5. Reject with `422 invalid_phone` if validation fails

Non-Indian numbers are rejected. This logic lives in a pure function `Moth.Auth.Phone.normalize/1` for easy unit testing.

---

## Auth Flow

### Request OTP — `POST /api/auth/otp/request`

**Unauthenticated. Request body:** `{ "phone": "+919876543210" }`

1. Normalize phone via `Phone.normalize/1`; return `422 invalid_phone` on failure
2. **Invalidate old OTPs:** `UPDATE phone_otp_codes SET used_at = now WHERE phone = ? AND used_at IS NULL AND expires_at > now`
3. Rate-limit: count OTP records for this phone inserted in the last 10 minutes (including just-invalidated ones). If >= 3, return `429 rate_limited`
4. Generate cryptographically random 6-digit numeric code (`:crypto.strong_rand_bytes` → `rem(integer, 900000) + 100000`)
5. Insert row into `phone_otp_codes` with `hashed_code = SHA-256(code)`, `expires_at = now + 10 minutes`
6. Deliver via `SMSProvider.deliver_otp(phone, code)` (see SMS Integration)
7. If SMS delivery fails (provider HTTP error/timeout), return `503 { "error": { "code": "sms_delivery_failed" } }`. The OTP row remains but will expire unused.
8. On success, return `{ "status": "ok" }` — same response regardless of whether the phone is associated with an existing user (prevents enumeration)

### Verify OTP — `POST /api/auth/otp/verify`

**Unauthenticated. Request body:** `{ "phone": "+919876543210", "code": "123456" }`

All steps 2–8 below run inside a single `Repo.transaction` with a row-level lock to prevent concurrent verify races.

1. Normalize phone via `Phone.normalize/1`; return `422 invalid_phone` on failure
2. Query with row lock: `SELECT … FROM phone_otp_codes WHERE phone = ? AND expires_at > now AND used_at IS NULL ORDER BY inserted_at DESC LIMIT 1 FOR UPDATE`
3. If no row found → `401 { "error": { "code": "invalid_otp" } }`
4. If `attempt_count >= 3` → `429 { "error": { "code": "too_many_attempts" } }` (checked before incrementing — 3 attempts max, period)
5. Compare `SHA-256(submitted_code)` against `hashed_code`
6. On mismatch → increment `attempt_count`, return `401 { "error": { "code": "invalid_otp", "attempts_remaining": 2 - attempt_count } }` (after increment: 1st fail → 2 remaining, 2nd → 1, 3rd → 0)
7. On match → set `used_at = now`, then:
   - Look up user by `phone`
   - **Existing user:** issue API token → `{ "token": "...", "user": {...}, "needs_name": false }`
   - **New user:** create user via `User.phone_registration_changeset` with `phone = phone`, `name = phone` (placeholder), issue API token → `{ "token": "...", "user": {...}, "needs_name": true }`

**Attempt logic clarified:** The check at step 4 (`>= 3`) happens *before* the hash comparison. A record starts with `attempt_count = 0`. After 3 wrong guesses, `attempt_count = 3`, and the next request is rejected before even comparing the code. This gives exactly 3 chances.

### Post-verify name collection (new users only)

When `needs_name: true`:
- Frontend shows a name-entry screen before redirecting to the app
- On submit, calls the **existing** `PATCH /api/user/me` endpoint with `{ "name": "Priya" }`
- This works because the general `User.changeset/2` now accepts phone-only users (no email required)
- No new backend endpoint needed

---

## SMS Integration

### Provider: MSG91

MSG91 is an India-focused SMS provider with TRAI DLT compliance (required for transactional SMS in India). OTPs are sent via their OTP API.

**HTTP call:**

```
POST https://api.msg91.com/api/v5/otp
Content-Type: application/json

{
  "authkey": "<MSG91_AUTH_KEY>",
  "template_id": "<DLT_TEMPLATE_ID>",
  "mobile": "919876543210",   // E.164 without leading '+'
  "otp": "123456"
}
```

**DLT template (to be registered with MSG91):**

> `Your Moth game sign-in OTP is {#var#}. Valid for 10 minutes. Do not share it with anyone.`

### SMS delivery architecture: behaviour + adapters

Define a behaviour `Moth.Auth.SMSProvider`:

```elixir
@callback deliver_otp(phone :: String.t(), code :: String.t()) :: :ok | {:error, term()}
```

Three implementations:
- **`Moth.Auth.SMSProvider.MSG91`** — production adapter, makes HTTP POST to MSG91 API
- **`Moth.Auth.SMSProvider.Log`** — dev adapter, logs OTP to console: `[dev] OTP for +919876543210: 482931`
- **`Moth.Auth.SMSProvider.Test`** — test adapter, sends `{:otp_sent, phone, code}` to the calling process (same pattern as Swoosh test adapter)

### Config

```elixir
# config/runtime.exs (production)
config :moth, :sms_provider, Moth.Auth.SMSProvider.MSG91
config :moth, :msg91,
  auth_key: System.get_env("MSG91_AUTH_KEY"),
  template_id: System.get_env("MSG91_TEMPLATE_ID")

# config/dev.exs
config :moth, :sms_provider, Moth.Auth.SMSProvider.Log

# config/test.exs
config :moth, :sms_provider, Moth.Auth.SMSProvider.Test
```

---

## New Backend Routes

```elixir
# in the unauthenticated /api scope:
post "/auth/otp/request", AuthController, :request_otp
post "/auth/otp/verify",  AuthController, :verify_otp
```

---

## Frontend Changes

### Type changes (`assets/js/types/domain.ts`)

Add `phone?: string` to the `User` type so the frontend can display it.

### `Auth.vue` — tab switcher

Add a `SegmentedControl` (already exists in `components/ui/`) at the top of the form with two tabs: **Phone** (default) and **Email**.

Email tab: existing magic link form, unchanged.

Phone tab — three sequential states:

**State 1 — Phone entry:**
- Input: phone number (type=tel, inputmode=numeric, placeholder=`98765 43210`)
- Button: "Send OTP"
- On submit → `api.auth.requestOtp(phone)`
- On `422` → show "Please enter a valid Indian mobile number"
- On `429` → show "Too many attempts. Please wait a few minutes."
- On `503` → show "Could not send SMS. Please try again."
- On success → advance to State 2

**State 2 — OTP entry:**
- Label: "Enter the 6-digit code sent to +91 XXXXX XXXXX"
- Input: 6-digit numeric OTP (inputmode=numeric, maxlength=6, autocomplete=one-time-code)
- Button: "Verify"
- Resend link (disabled for 30s cooldown, then "Resend code"). Resend calls `requestOtp` again (which invalidates old OTP and sends new one).
- On `401 invalid_otp` → show "Wrong code. {attempts_remaining} attempts left." (or "Wrong code." if no attempts_remaining in response)
- On `429 too_many_attempts` → show "Too many wrong attempts. Please request a new code."
- On success → if `needs_name`, advance to State 3; else store token, redirect to app

**State 3 — Name entry (new users only):**
- Label: "What should we call you?"
- Input: display name (text, required, min 2 chars)
- Button: "Start playing"
- On submit → `api.user.update({ name })` (existing endpoint)
- On success → redirect to app

### New API client methods (`api/client.ts`)

```typescript
api.auth.requestOtp(phone: string): Promise<void>
api.auth.verifyOtp(phone: string, code: string): Promise<{ token: string; user: User; needs_name: boolean }>
```

---

## Error Handling

| Scenario | HTTP status | Error code |
|---|---|---|
| Invalid/missing phone format | 422 | `invalid_phone` |
| Too many OTP requests (rate limit) | 429 | `rate_limited` |
| SMS delivery failure (MSG91 error) | 503 | `sms_delivery_failed` |
| OTP not found or expired | 401 | `invalid_otp` |
| Wrong code (with attempts remaining) | 401 | `invalid_otp` + `attempts_remaining` |
| Too many wrong attempts (3 exhausted) | 429 | `too_many_attempts` |

---

## Security Notes

- OTP codes are never stored in plaintext — only SHA-256 hashes
- Response to `request_otp` is always `{ status: "ok" }` regardless of whether the phone exists (prevents user enumeration). Exception: 503 on SMS failure, which does not reveal user existence.
- `attempt_count` cap (3) prevents brute-force of 6-digit codes
- Rate limit on requests (3 per 10 min per phone) prevents SMS spam/cost abuse
- `used_at` ensures single-use; old OTPs are invalidated on resend
- Phone numbers are normalized and validated server-side; client-supplied format is not trusted
- Only Indian mobile numbers (+91, starting with 6/7/8/9) are accepted
- Verify flow uses `SELECT ... FOR UPDATE` inside a transaction to prevent TOCTOU races on concurrent verify requests

---

## Files to Create / Modify

**Backend — new files:**
- `priv/repo/migrations/<ts>_add_phone_otp.exs` — add `phone` to users (nullable), drop `NOT NULL` on email, create `phone_otp_codes`
- `lib/moth/auth/phone_otp_code.ex` — Ecto schema for `phone_otp_codes`
- `lib/moth/auth/phone.ex` — `normalize/1` pure function for phone validation + E.164 normalization
- `lib/moth/auth/sms_provider.ex` — behaviour definition
- `lib/moth/auth/sms_provider/msg91.ex` — production MSG91 adapter
- `lib/moth/auth/sms_provider/log.ex` — dev adapter (console log)
- `lib/moth/auth/sms_provider/test.ex` — test adapter (process message)

**Backend — modified files:**
- `lib/moth/auth/user.ex` — add `phone` field, add to `Jason.Encoder`, add `phone_registration_changeset/2`, relax `email` requirement in `changeset/2`
- `lib/moth/auth/auth.ex` — add `request_phone_otp/1`, `verify_phone_otp/2`
- `lib/moth_web/controllers/api/auth_controller.ex` — add `request_otp/2`, `verify_otp/2`
- `lib/moth_web/router.ex` — add two new routes
- `config/runtime.exs` — MSG91 config keys + SMS provider config
- `config/dev.exs` — SMS provider: Log
- `config/test.exs` — SMS provider: Test

**Frontend — modified files:**
- `assets/js/types/domain.ts` — add `phone?: string` to `User` type
- `assets/js/pages/Auth.vue` — phone tab + 3-state OTP flow with error handling
- `assets/js/api/client.ts` — add `requestOtp`, `verifyOtp`

---

## Test Plan

### Backend unit tests

**`test/moth/auth/phone_test.exs`** — phone normalization:
- Bare 10-digit number → E.164 (`9876543210` → `+919876543210`)
- Already E.164 → pass through
- With spaces/dashes → normalized
- `91` prefix without `+` → corrected
- Invalid: too short, too long, starts with 0-5, alphabetic → error
- Non-Indian country codes → rejected

**`test/moth/auth/phone_otp_code_test.exs`** — schema/changeset:
- Valid attrs produce valid changeset
- Missing phone → invalid
- Missing hashed_code → invalid

**`test/moth/auth/sms_notifier_test.exs`** — test adapter:
- `SMSProvider.Test.deliver_otp/2` sends message to calling process
- Can assert on `{:otp_sent, phone, code}` in tests

**`test/moth/auth/auth_test.exs`** — OTP context functions:
- `request_phone_otp/1`: creates OTP record, returns `:ok`
- `request_phone_otp/1`: invalidates previous unexpired OTPs for same phone
- `request_phone_otp/1`: rate-limits at 3 requests per 10 min
- `verify_phone_otp/2`: correct code → `{:ok, user, token}`
- `verify_phone_otp/2`: wrong code → `{:error, :invalid_otp, attempts_remaining}`
- `verify_phone_otp/2`: expired OTP → `{:error, :invalid_otp}`
- `verify_phone_otp/2`: already-used OTP → `{:error, :invalid_otp}`
- `verify_phone_otp/2`: 3 wrong attempts then correct → `{:error, :too_many_attempts}`
- `verify_phone_otp/2`: new phone creates user with `needs_name: true`
- `verify_phone_otp/2`: existing phone user returns `needs_name: false`
- Anti-enumeration: `request_phone_otp/1` returns `:ok` for unknown phones

**`test/moth/auth/user_test.exs`** — changeset changes:
- `phone_registration_changeset/2` accepts phone + name
- `phone_registration_changeset/2` rejects invalid Indian number
- `changeset/2` accepts email-only user (regression)
- `changeset/2` accepts phone-only user (new)
- `changeset/2` rejects user with neither phone nor email

### Backend integration tests

**`test/moth_web/controllers/api/auth_controller_test.exs`**:
- `POST /api/auth/otp/request` — happy path (200)
- `POST /api/auth/otp/request` — invalid phone (422)
- `POST /api/auth/otp/request` — rate limited (429)
- `POST /api/auth/otp/verify` — correct code, new user (200, `needs_name: true`)
- `POST /api/auth/otp/verify` — correct code, existing user (200, `needs_name: false`)
- `POST /api/auth/otp/verify` — wrong code (401, attempts_remaining)
- `POST /api/auth/otp/verify` — exhausted attempts (429)
- `POST /api/auth/otp/verify` — expired OTP (401)
- Token from OTP verify works for authenticated endpoints (`GET /api/user/me`)
- Token from OTP verify works for `UserSocket` channel auth (phone-only user can join game)

### Frontend tests

**`assets/js/pages/__tests__/Auth.spec.ts`**:
- Renders phone tab by default with SegmentedControl
- Switching to email tab shows magic link form
- Phone entry: submitting calls `api.auth.requestOtp` and advances to OTP state
- Phone entry: 422 shows "valid Indian mobile number" error
- Phone entry: 429 shows rate-limit message
- Phone entry: 503 shows SMS failure message
- OTP entry: correct code with `needs_name: false` → redirect
- OTP entry: correct code with `needs_name: true` → name entry state
- OTP entry: wrong code shows attempts remaining
- OTP entry: 429 shows "request a new code" message
- OTP entry: resend button disabled for 30s, then enabled
- Name entry: submitting calls `api.user.update` and redirects
