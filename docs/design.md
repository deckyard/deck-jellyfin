<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

A client for the REST API of the Jellyfin media server: sign-in with a
password or an API key; libraries, items with paging, search, latest, resume,
next up, episodes, played and favourite marks, images; server information,
users, library and item refresh, scheduled tasks, sessions with messages and
playback commands. `call` reaches every other endpoint.

Not covered by typed functions: streaming and transcoding media, the
server's WebSocket notifications, the setup wizard and plugin management. A
player is a different kind of client, and the rest is one-time
administration; `call` reaches the REST side of them.

## Decisions

- **The 10.9-and-later routes.** The OpenAPI description is the source of
  truth, checked against version 12.4.0. The deck uses the newer routes
  (`userId` as a query parameter, `/UserViews`, `/UserItems/Resume`,
  `/UserPlayedItems/{id}`, `/UserFavoriteItems/{id}`); the older
  `/Users/{userId}/Items...` routes are gone from the description.
  `serverInfo` refuses a server older than `MIN_MAJOR` (10) or one that does
  not answer as Jellyfin.
- **One authorization header.** Every request carries
  `Authorization: MediaBrowser Client=..., Device=..., DeviceId=...,
  Version=1, Token=...`, the description's only security scheme. Jellyfin
  only shows the version, so it is a fixed `1`. Names, the device id and
  the token are checked so no quote or comma can break the header, and
  re-checked on every request, since `Client` fields are public.
- **Device identity.** `client` picks a random device id; `withDevice` sets
  a stable one. A login ends the earlier session of the same user and
  device id, so a long-running program should keep its own.
- **Two ways to sign in.** `login` with a user name and password stores the
  token and the user id it gets back, and validates both (the token's form
  is restricted so that URL decoding of header values cannot change it).
  `withToken` takes an API key; `withUser` then names the user for per-user
  calls, since an API key has no user (`me` answers 400 with one).
- **The deadline is the deck's.** Each request runs in a spawned task under
  `task.waitTimeout`, so a server that accepts and never answers cannot hold
  the caller past `withTimeout`. Redirects are not followed.
- **`refreshItem` asks for a real refresh** (`Default` metadata and image
  modes); the description's default, `None`, does nothing.
- **Bounded paging.** `allItems` pages 200 at a time, refuses more than its
  `most` matches (at most `MAX_ITEMS`, 20000; each item keeps its JSON,
  about 22 KB), refuses paging parameters in the caller's query, and fails
  when a page's start, size or the total do not add up.
- **Ask for what the description makes optional.** List calls request
  `ParentId` and `Path`, which the server returns only when asked;
  `episodes` leaves out missing episodes.
- **Strict entries.** Items, tasks and sessions without a valid id are
  refused rather than returned half-filled. `Task.key` is the stable name,
  since `Task.name` is translated.

## Errors

- A status that is not 2xx throws `HttpError{kind: "jellyfin.http",
  message, status, fields}`: `status` is the HTTP status and `fields` the
  ASP.NET validation errors of a 400 (field to its first message). The
  message carries ProblemDetails' `title` or `detail`, cleaned and capped. A
  refused login is a 401 with its own message.
- `allItems` past its `most` is kind `"limit"`.
- A cancelled task is rethrown as it is (kind `"cancelled"`).
- A network failure (refused, reset, unreachable, DNS, TLS) is the
  interpreter's `net.NetError` of kind `"net"`, passed on unchanged so its
  `reason`, `sent` and `replied` fields survive. Nothing is retried.
- A response over the byte cap and a JSON answer past the decoder's caps
  are kind `"limit"`, a request with no answer within the deadline kind
  `"timeout"`, and a reply cut short kind `"closed"`, each passed on as the
  generic kind every library shares.
- Everything else is `Error{kind: "jellyfin"}`: invalid input and an answer
  that is not what the description promises.

## Security and limits

- **Plain http only to loopback** (`127.0.0.1`, `localhost`, `[::1]`)
  unless `withPlainHttp`: LAN servers often have no TLS, but the token
  should not cross a network in clear by default.
- **Deadline and size.** `DEFAULT_TIMEOUT_MS` (30 s) per request and
  `DEFAULT_MAX_BYTES` (16 MiB) per response, changed with `withTimeout` and
  `withMaxBytes`.
- **Address checks** on every request: ports 1 to 65535, real host labels,
  plain path segments.
- **Server text is cleaned** before it reaches a message: control
  characters, bidirectional overrides and invisible separators become `?`.
- `withTls` takes a private CA (`caCert`), or turns verification off
  (`skipVerify`) for a self-signed server.

## Testing and validation

- 17 tests against a single-threaded loopback fake that answers scripted
  replies keyed by method and path (the fake comes from `@deckyard/fhir`).
- Checked live against Jellyfin 12.4.0 in a container, set up through the
  startup API with a generated film and two episodes: every export and both
  examples. Learned there: a refused login is 401; `/Users` answers any
  signed-in user on a default server; `me` with an API key is 400; `resume`
  stays empty for media shorter than the server's minimum resume length (5
  minutes by default); `/Items/Latest` groups episodes into their series.
- The review fixes of 2026-11-13 (token and id validation, address checks,
  paging consistency, entry validation) were tested against the fake only.
- Not confirmed live: that `logout` with an API key leaves the key working,
  and that a login ends the earlier session of the same user and device id
  (both from reading the server's source).

## Known limitations and open questions

- The cancel and cap checks also match the old messages, for interpreters
  older than the kinds; the fallbacks go at the next floor raise.

## Dependencies on the interpreter

- Floor `>=0.26.0`, the default binary and the `net` capability (not
  `jennifer-tiny`).
- `http.requestWithBytes` with a byte cap, `task.waitTimeout` and
  `task.cancel`.
- A reached cap and a cancelled task told by kind (`jennifer`'s M28.54,
  M28.55, M28.57), and network failures as `net.NetError` (M28.65).
