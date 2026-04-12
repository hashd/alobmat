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

---

## Data Model

### `users` table changes

Add a `phone` column:

```sql
ALTER TABLE users ADD COLUMN phone varchar(20) UNIQUE;
```

- E.164 format (`+919876543210`)
- Optional (nullable) — users can have phone only, email only, or both
- Unique index
- `email` column becomes nullable (remove `NOT NULL` constraint)

**Invariant (enforced in context, not DB):** every user must have at least one of `phone` or `email`.

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
- `used_at` — set on first successful verification; `NULL` means unused
- No `user_id` — this table is pre-authentication; user lookup happens at verify time

---

## Auth Flow

### Request OTP — `POST /api/auth/otp/request`

**Unauthenticated. Request body:** `{ "phone": "+919876543210" }`

1. Normalize input to E.164 (strip spaces, dashes; prepend +91 if bare 10-digit Indian number)
2. Rate-limit: if ≥ 3 unexpired OTP records exist for this phone in the last 10 minutes, return `429 rate_limited`
3. Generate cryptographically random 6-digit numeric code (`100000..999999`)
4. Insert row into `phone_otp_codes` with `hashed_code = SHA-256(code)`, `expires_at = now + 10 minutes`
5. Deliver via MSG91 (see SMS Integration section)
6. Return `{ "status": "ok" }` — always, even for unknown phones (prevents enumeration)

### Verify OTP — `POST /api/auth/otp/verify`

**Unauthenticated. Request body:** `{ "phone": "+919876543210", "code": "123456" }`

1. Normalize phone to E.164
2. Query: `SELECT … FROM phone_otp_codes WHERE phone = ? AND expires_at > now AND used_at IS NULL ORDER BY inserted_at DESC LIMIT 1`
3. If no row found → `401 { "error": { "code": "invalid_otp" } }`
4. Increment `attempt_count`
5. If `attempt_count > 3` → `429 { "error": { "code": "too_many_attempts" } }`
6. Compare `SHA-256(submitted_code)` against `hashed_code`
7. On mismatch → `401 { "error": { "code": "invalid_otp", "attempts_remaining": 3 - attempt_count } }`
8. On match → set `used_at = now`, then:
   - Look up user by `phone`
   - **Existing user:** issue API token → `{ "token": "...", "user": {...}, "needs_name": false }`
   - **New user:** create user with `phone = phone`, `name = phone` (placeholder), issue API token → `{ "token": "...", "user": {...}, "needs_name": true }`

### Post-verify name collection (new users only)

When `needs_name: true`:
- Frontend shows a name-entry screen before redirecting to the app
- On submit, calls the **existing** `PATCH /api/user/me` endpoint with `{ "name": "Priya" }`
- No new backend endpoint needed

---

## SMS Integration

### Provider: MSG91

MSG91 is an India-focused SMS provider with TRAI DLT compliance (required for transactional SMS in India). OTPs are sent via their OTP API.

**HTTP call (from `Moth.Auth.SMSNotifier`):**

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

### New Elixir module: `Moth.Auth.SMSNotifier`

Parallel to `Moth.Auth.UserNotifier` (email). Single public function:

```elixir
SMSNotifier.deliver_otp(phone, otp_code)
```

### Config (`config/runtime.exs`)

```elixir
config :moth, :msg91,
  auth_key: System.get_env("MSG91_AUTH_KEY"),
  template_id: System.get_env("MSG91_TEMPLATE_ID")
```

### Dev/test behavior

In dev and test environments, SMS is not sent. The OTP code is logged to the console:

```
[dev] OTP for +919876543210: 482931
```

Same pattern as Swoosh's local mailbox for email in dev.

---

## New Backend Routes

```elixir
# in the unauthenticated /api scope:
post "/auth/otp/request", AuthController, :request_otp
post "/auth/otp/verify",  AuthController, :verify_otp
```

---

## Frontend Changes

### `Auth.vue` — tab switcher

Add a `SegmentedControl` (already exists in `components/ui/`) at the top of the form with two tabs: **Phone** and **Email**.

Email tab: existing magic link form, unchanged.

Phone tab — three sequential states:

**State 1 — Phone entry:**
- Input: phone number (type=tel, placeholder=`+91 98765 43210`)
- Button: "Send OTP"
- On submit → `api.auth.requestOtp(phone)`
- On success → advance to State 2

**State 2 — OTP entry:**
- Label: "Enter the 6-digit code sent to {phone}"
- Input: 6-digit numeric OTP (inputmode=numeric, maxlength=6, autocomplete=one-time-code)
- Button: "Verify"
- Resend link (disabled for 30s cooldown, then "Resend code")
- On submit → `api.auth.verifyOtp(phone, code)`
- On success → if `needs_name`, advance to State 3; else redirect to app

**State 3 — Name entry (new users only):**
- Label: "What should we call you?"
- Input: display name (text)
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
| OTP not found or expired | 401 | `invalid_otp` |
| Wrong code (with attempts remaining) | 401 | `invalid_otp` + `attempts_remaining` |
| Too many wrong attempts | 429 | `too_many_attempts` |

---

## Security Notes

- OTP codes are never stored in plaintext — only SHA-256 hashes
- Response to `request_otp` is always `{ status: "ok" }` regardless of whether the phone exists (prevents user enumeration)
- `attempt_count` cap (3) prevents brute-force of 6-digit codes
- Rate limit on requests (3 per 10 min per phone) prevents SMS spam/cost abuse
- `used_at` ensures single-use; expired records are inert
- Phone numbers are normalized server-side; client-supplied format is not trusted

---

## Files to Create / Modify

**Backend:**
- `priv/repo/migrations/<ts>_add_phone_otp.exs` — add `phone` to users, create `phone_otp_codes`
- `lib/moth/auth/phone_otp_code.ex` — Ecto schema for `phone_otp_codes`
- `lib/moth/auth/sms_notifier.ex` — MSG91 HTTP delivery
- `lib/moth/auth/auth.ex` — add `request_phone_otp/1`, `verify_phone_otp/2`
- `lib/moth/auth/user.ex` — make `email` optional, add `phone` field
- `lib/moth_web/controllers/api/auth_controller.ex` — add `request_otp/2`, `verify_otp/2`
- `lib/moth_web/router.ex` — add two new routes
- `config/runtime.exs` — MSG91 config keys

**Frontend:**
- `assets/js/pages/Auth.vue` — phone tab + 3-state OTP flow
- `assets/js/api/client.ts` — add `requestOtp`, `verifyOtp`

**Tests:**
- `test/moth/auth/auth_test.exs` — OTP request/verify/rate-limit/attempt-count logic
- `test/moth_web/controllers/api/auth_controller_test.exs` — HTTP endpoint tests
