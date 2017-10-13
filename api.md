### API

#### Without Authentication
- `GET /api/games`: Gets list of active games
- `GET /api/games/:id`: Gets detail of game with specified id
- `GET /logout`: Logs user out on the backend if logged in

#### Requires Authentication
- `GET /api/users`: Fetches user list from database
- `GET /api/auth/token`: Creates and fetches a token to be used for authorized socket connection
- `POST /api/games`: Creates a new game with **name, interval, moderators(o) and bulletin(o)**

### Channels
- `public:lobby`: Gets list of active games on the server. And further updates on game starts and ends as `start_game` and `end_game` type messages.
- `game:${id}`: Gets the state of the game on join. Further updates on game includes: *notification*, *pick*, *timer* and presence events.
