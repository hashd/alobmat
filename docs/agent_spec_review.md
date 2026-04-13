# Adversarial Review: Mocha v2 Tambola Server Spec

While the document is exceptionally well-structured and the core architecture (context-separated monolith, GenServer-per-game, write-through vs. snapshot persistence) is idiomatically suited for Elixir/OTP, there are several critical flaws, race conditions, and DoS vectors that need to be addressed before this is production-ready.

---

### 🔴 CRITICAL ARCHITECTURE & STATE FLAWS

#### 1. The "Time Travel" State Inconsistency (Race Condition)
* **The Flaw:** Section 3 states that board state (picks) is snapshotted every 5 picks, while prize claims are "write-through" (persisted immediately). 
* **The Exploit/Impact:** If the game crashes at pick 14, it restarts from the snapshot at pick 10. The timer resumes picking numbers 11, 12, 13, and 14. However, if Player A legitimately claimed "Early Five" at pick 13, that claim is firmly in the database. When the game resumes from pick 10, the DB will show "Early Five" is already claimed, even though the currently visible board hasn't drawn those numbers yet. If Player B gets an "Early Five" at the replayed pick 12, they will be rejected for a prize that visually hasn't been claimed. 
* **The Fix:** At 10K games with 10s intervals, you are only averaging 1,000 picks per second system-wide. A single Postgres instance can easily handle 1,000 simple `UPDATE` queries per second. Change board state persistence to **write-through on every pick** to eliminate this temporal anomaly entirely.

#### 2. GenServer Mailbox Exhaustion (Chat DoS Vector)
* **The Flaw:** Section 10 states: "Rate limiting: 1 message per second per user, enforced inside the GameServer."
* **The Exploit/Impact:** If a malicious user connects to the Channel or LiveView and runs a script to send 10,000 chat messages per second, the edge process will forward all 10,000 messages directly into the `GameServer` GenServer mailbox. Even if the GameServer correctly drops 9,999 of them, processing that massive mailbox queue will consume all of the GenServer's CPU time, causing severe latency for legitimate actions (like prize claims) or crashing the GameServer via OOM.
* **The Fix:** Rate limits for high-frequency events MUST be enforced at the edge (inside the `LiveView` process and the `Channel` process) *before* forwarding the message to the shared `GameServer`.

#### 3. The "Thundering Herd" Database Nuke
* **The Flaw:** The `Mocha.Game.Supervisor` uses `rest_for_one` for `[Registry, DynSup, Monitor]`.
* **The Risk:** If the `Registry` crashes for any unforeseen reason, the supervisor will terminate the `DynamicSupervisor`, which will ruthlessly kill all 10,000 active `GameServer` processes simultaneously.
* **The Impact:** When the `DynamicSupervisor` restarts, it will boot up 10,000 GameServers at the exact same time. Every single one will execute `init/1` and immediately query Postgres to load their snapshot and `game_players` state. This will instantly exhaust your Ecto connection pool, spike Postgres CPU to 100%, and likely cause cascading timeouts that prevent the cluster from ever recovering.
* **The Fix:** Introduce random jitter (e.g., `Process.sleep(:rand.uniform(3000))`) inside the `GameServer.init/1` database recovery phase to stagger the load during massive supervisor restarts.

---

### 🟠 GAMEPLAY & PRODUCT EXPLOITS

#### 4. The "Late Joiner" Sniper Exploit
* **The Flaw:** Section 4 states: "Players who join after the game has started: ticket generated on join. They can claim prizes based on numbers already picked."
* **The Exploit:** A malicious user (or bot network) can wait until a game is deep into its progression (e.g., 70 numbers picked). They can then programmatically join the game with dozens of throwaway accounts, instantly generating dozens of fresh tickets against an already established board. Because 70 numbers are drawn, these fresh tickets have a massive statistical probability of instantly completing high-value unclaimed prizes (like Full House).
* **The Fix:** You must lock the game room. Disallow users from joining a game once its status transitions to `:running`. 

#### 5. The Immortal Game Loophole
* **The Flaw:** Section 6 states that if the host disconnects, the game auto-pauses after 60s. "If the host doesn't reconnect within the game's cooldown period [30 minutes]: game is finished and reaped."
* **The Exploit:** A malicious user can write a script to connect as a host, disconnect, wait 29 minutes, reconnect for 1 second, and disconnect again. This resets the cooldown timer, keeping the GameServer alive in memory indefinitely.
* **The Fix:** Enforce a hard "maximum lifetime" for any game (e.g., 4 hours from creation), regardless of host activity, at which point it is forcefully terminated, finalized, and archived.

---

### 🟡 API, CLIENT, & DATA MODEL RISKS

#### 6. Missing Critical Database Index
* **The Flaw:** The `game_players` table lists indexes: `unique on (game_id, user_id)`.
* **The Risk:** When a user opens their profile to view their past or active games, Ecto must execute `SELECT * FROM game_players WHERE user_id = X`. Without a standalone index on `user_id`, Postgres will perform a sequential table scan. At 100K players playing a few games a week, this table will reach millions of rows quickly, and this missing index will destroy database performance.
* **The Fix:** Add a standard index on `game_players(user_id)`.

#### 7. IP-Based Rate Limiting on Mobile Connections
* **The Flaw:** Section 8 applies rate limits for failed game joins to "10 req/min per IP".
* **The Risk:** Mobile users often sit behind Carrier-Grade NAT (CGNAT), meaning hundreds of legitimate mobile users share a single IP address. A single user spamming invalid join codes from their phone will lock out all other users on the same cellular network block.
* **The Fix:** Because joining a game requires the user to be authenticated, rate limit failed game joins by `user_id` instead of IP.

#### 8. Client-Side Timer Drift
* **The Flaw:** Section 7 states: "Clients compute their own countdown from `next_pick_at`... No timer broadcast."
* **The Risk:** Mobile device clocks are notoriously inaccurate. If a user's phone clock is 5 seconds behind the server, they will see the timer hit 0 a full 5 seconds *after* the number was actually drawn. If they are ahead, the timer will sit at 0 for 5 seconds waiting for the network event.
* **The Fix:** The server must provide `server_current_time` in the initial game state payload. The client must calculate the offset (`server_time - local_time`) and apply this delta to all `next_pick_at` calculations.

#### 9. API Token Refresh Deadlock
* **The Flaw:** Section 5/8 states tokens expire in 30 days and clients must POST `/api/auth/refresh` before expiry.
* **The Risk:** If the client goes offline or the user doesn't open the app for 31 days, the token expires. When they finally open the app, how do they refresh? The `/api/auth/refresh` endpoint presumably requires authentication. If their token is expired, they receive a `401 Unauthorized` and are forced to log in from scratch.
* **The Fix:** Implement standard OAuth-style long-lived `refresh_tokens`, or rely on device-level secure enclaves and treat the API token as non-expiring until explicitly revoked by the server.

---

### 🌪️ RADICAL TECHNOLOGY SHIFTS

#### 1. Cloudflare Durable Objects (The Perfect Match)
The architectural pattern of "one isolated process per game room" maps 1-to-1 with **Cloudflare Durable Objects**. 
* **How it works:** You write the backend in TypeScript/JavaScript for Cloudflare Workers. Every Tambola game room becomes a single Durable Object.
* **Why it's better:** WebSockets terminate directly at the CDN edge (insanely low latency for players). The Durable Object holds the game state in memory and provides built-in transactional storage. You completely eliminate the need to manage a 64GB monolithic server, configure clusters, or worry about Postgres connection pooling. It scales infinitely from 10 games to 1,000,000 games automatically.
* **Trade-off:** You leave the Elixir/Phoenix ecosystem and have to deal with the quirks of edge-compute environments (no standard relational DB out of the box, though D1 exists).

#### 2. Go + Redis (The Brutal Efficiency Route)
If you want to stay on a single massive node but maximize throughput and minimize memory overhead:
* **How it works:** A Go backend utilizing lightweight Goroutines for WebSocket connections, paired with Redis for game state.
* **Why it's better:** Go's memory footprint per connection can be tuned to be even smaller than Elixir's. You replace the complexity of GenServers and Supervisors with standard Go channels and Redis atomic operations (like Lua scripts for claims to prevent race conditions).
* **Trade-off:** You lose OTP's built-in fault tolerance. If a Go panic takes down the process, the whole node goes down (though it boots back up in milliseconds).

---

### 🏛️ ARCHITECTURAL / PARADIGM SHIFTS (LANGUAGE AGNOSTIC)

#### 3. Event Sourcing (CQRS) for the Game Engine
Instead of the complex dance between "write-through" and "snapshots" (which caused the Time Travel bug), change the game engine to be purely **Event Sourced**.
* **How it works:** The database only has one table for active games: `game_events` (Columns: `game_id`, `sequence`, `event_type`, `payload`). Events are things like `GameStarted`, `NumberPicked(42)`, `PrizeClaimed(EarlyFive, UserX)`.
* **Why it's better:** To mutate state, you just append an event. If the GenServer crashes, its `init/1` simply queries `SELECT payload FROM game_events WHERE game_id = X ORDER BY sequence` and reduces them into the current state. 
* **Result:** **Zero race conditions.** Complete audit trail. No weird snapshots. If a user disputes a prize, you can mathematically replay the entire game exactly as it happened.

#### 4. Offload WebSockets to a Managed Gateway
* **How it works:** Use a service like **Centrifugo**, **Pusher**, or **AWS API Gateway WebSockets**. The Elixir app becomes a standard stateless HTTP API that just publishes events to the Gateway via Redis/HTTP.
* **Why it's better:** Maintaining 100,000 concurrent long-lived TCP connections requires specific OS tuning (file descriptors, TCP buffers, etc.). Offloading this to a managed layer means your Elixir server only handles actual game logic, drastically reducing its memory footprint and making clustering trivial (since the web nodes are stateless).

---

### 🛠️ ELIXIR/OTP SPECIFIC TWEAKS

#### 5. Use `:ets` or `Mnesia` for Ephemeral State instead of Postgres
* Postgres is not designed to be a fast-updating ephemeral state store for millions of in-flight game ticks. 
* Have the GenServer write its snapshot to an `:ets` table (or `:mnesia` if you plan to cluster) instead of Postgres. 
* If a single GameServer process crashes, it immediately reloads from `:ets` without ever touching the network or Postgres. Only write to Postgres when the game is `finished`.

#### 6. Push Ticket Generation to the Client
* **The current spec:** Server generates tickets, stores them in DB, and validates them. 
* **The suggestion:** Use a seeded deterministic PRNG (Pseudo-Random Number Generator). The server just assigns a `seed` integer to a user when they join. The client uses that seed to visually render the ticket. When the user claims a prize, the server quickly re-generates the ticket in-memory using the seed and validates the claim. 
* **Why it's better:** You completely remove the `ticket` JSONB column from the database, saving massive amounts of storage and memory bandwidth.

---

### 🚀 TRULY OUT-OF-THE-BOX ARCHITECTURES

#### 7. WebRTC P2P Mesh (The "Zero Server" Approach)
* **How it works:** Instead of a central server hosting the game, the server only acts as a signaling server (STUN/TURN) and identity provider. The "Host" of the game room acts as the authoritative node for that specific game. Players connect directly to the Host via WebRTC data channels.
* **Why it's better:** Server costs approach zero. Infinite scalability since players bring their own compute and bandwidth.
* **Trade-off:** Host disconnection kills the game immediately. Cheating is easier if the host is malicious (requires complex cryptographic verification to prevent the host from rigging picks).

#### 8. NATS JetStream as the Core Engine (The Pure Pub/Sub Route)
* **How it works:** Instead of building a custom GenServer engine, use a powerful message broker like NATS JetStream. Clients connect directly to the broker via WebSockets. The "server" is just a set of stateless microservices listening to streams. The game state is derived entirely from the stream of events in NATS.
* **Why it's better:** Incredibly robust messaging. Offloads all connection management to highly optimized C/Go brokers. NATS handles all the routing, presence, and fan-out to 100k users trivially.
* **Trade-off:** Moves complexity from application code to infrastructure configuration.

#### 9. Serverless + DynamoDB + API Gateway (The "Pay Per Tick" Model)
* **How it works:** Using AWS API Gateway WebSockets + Lambda + DynamoDB. Every action (join, claim, tick) triggers a Lambda. State is managed via DynamoDB atomic increments and conditional writes.
* **Why it's better:** Truly pay-per-execution. Zero idle costs. No server management or capacity planning required.
* **Trade-off:** Cold starts can introduce latency. High frequency ticks (every 10s across 10K games) might incur higher costs than a dedicated server at maximum scale.

#### 10. Cryptographically Verifiable Offline-First (CRDTs + Signed Claims)
* **How it works:** Use a CRDT (Conflict-free Replicated Data Type) library like Yjs or Automerge. This allows players to play in spotty network conditions (trains, rural areas). Their local state syncs with the server when they regain connection.
* **Why it's better:** Incredible user experience on mobile connections. Users never see "Reconnecting..." spinners.
* **Trade-off:** For Tambola, this is tricky due to the competitive nature of claims. It requires claims to be timestamp-ordered and cryptographically signed on the client so the server can retroactively verify who actually claimed a prize first.

#### 11. The Rustler Hybrid (Elixir Orchestration + Rust Engine)
* **How it works:** Keep the Elixir/Phoenix orchestration for WebSockets, Supervisors, and PubSub, but move the actual game tick, ticket validation, and claim logic into Rust via Rustler NIFs (Native Implemented Functions).
* **Why it's better:** Maximum CPU efficiency for validation logic while retaining OTP's battle-tested supervision tree and Phoenix's WebSockets.
* **Trade-off:** Increased build complexity. Probably a premature optimization since Elixir is fast enough for basic Tambola logic, but a solid pathway if CPU bounds are hit at extreme scales.