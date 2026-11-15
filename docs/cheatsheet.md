<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# jellyfin cheatsheet

Every export of `@deckyard/jellyfin`. Guides are listed in
[the introduction](index.md).

```jennifer
import "@deckyard/jellyfin/" as jellyfin;
```

A request the server refused throws `HttpError` (kind `jellyfin.http`) with
the HTTP `status` and the validation errors as `fields` (field -> first
message); a response over its cap, a JSON answer past the decoder's caps and
`allItems` past its `most` are kind `"limit"`, a deadline kind `"timeout"`, a reply
cut short kind `"closed"`; a network failure is the
interpreter's `net.NetError` (kind `"net"`, with `reason`, `sent` and `replied`),
passed on unchanged; every other failure is
`Error{kind: "jellyfin"}` (a cancelled task stays kind `"cancelled"`, "task
cancelled"). A `c` argument
is a `Client`; a `query` is a `list of string` of `name=value` parameters.
"Per-user" calls need a user: `login`, or `withUser` with an API key.

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `VERSION` | `"0.1.0"` | this deck's version, sent in the authorization header |
| `DEFAULT_TIMEOUT_MS` | `30000` | how long one request may take |
| `DEFAULT_MAX_BYTES` | `16777216` | the largest response read |
| `MIN_MAJOR` | `10` | the oldest Jellyfin major version `serverInfo` accepts |
| `MAX_ITEMS` | `20000` | the most items `allItems` reads, about 450 MB with their JSON |

## The client

| Function | Returns | Does |
|---|---|---|
| `jellyfin.client(baseUrl)` | `Client` | a client, not signed in; plain http only to this machine |
| `jellyfin.login(c, username, password)` | `Client` | sign in; the client carries the token and the user |
| `jellyfin.logout(c)` | `Client` | sign out; a login's token stops working (an API key does not) |
| `jellyfin.withToken(c, token)` | `Client` | sign in with an access token or API key |
| `jellyfin.withUser(c, userId)` | `Client` | act for a user in the per-user calls |
| `jellyfin.withDevice(c, clientName, deviceName, deviceId)` | `Client` | the names and stable id the server shows |
| `jellyfin.withPlainHttp(c)` | `Client` | allow plain http to another machine |
| `jellyfin.withTls(c, tls)` | `Client` | certificate options (`caCert`, `skipVerify`) |
| `jellyfin.withTimeout(c, ms)` | `Client` | the deadline of one request, 1000 to 86400000 ms |
| `jellyfin.withMaxBytes(c, most)` | `Client` | the largest response, 65536 to 268435456 bytes |
| `jellyfin.call(c, method, path, query, body)` | `json.Value` | any other endpoint |

## The library

| Function | Returns | Does |
|---|---|---|
| `jellyfin.libraries(c)` | `list of Library` | per-user; the user's libraries |
| `jellyfin.items(c, query)` | `Page` | per-user; one page of items, filtered and sorted by the server |
| `jellyfin.allItems(c, query, most)` | `list of Item` | per-user; every matching item, page by page, at most `most` |
| `jellyfin.item(c, id)` | `Item` | per-user; one item |
| `jellyfin.search(c, term, limit)` | `list of Item` | per-user; items by name |
| `jellyfin.latest(c, parentId, limit)` | `list of Item` | per-user; the latest additions, of one library or all (`""`) |
| `jellyfin.resume(c, limit)` | `list of Item` | per-user; started and not finished |
| `jellyfin.nextUp(c, limit)` | `list of Item` | per-user; the next episode of each series in progress |
| `jellyfin.episodes(c, seriesId)` | `list of Item` | per-user; every episode of a series that has a file |
| `jellyfin.setPlayed(c, id, played)` | `null` | per-user; mark played or not |
| `jellyfin.setFavorite(c, id, favorite)` | `null` | per-user; add to or take out of the favourites |
| `jellyfin.image(c, id, type, maxWidth)` | `bytes` | an item's poster, backdrop, logo, ... |
| `jellyfin.refreshItem(c, id)` | `null` | administrator; rescan an item, filling in missing metadata and images |

## Administration

| Function | Returns | Does |
|---|---|---|
| `jellyfin.serverInfo(c)` | `ServerInfo` | the server's name and version; no sign-in needed |
| `jellyfin.me(c)` | `User` | the signed-in user |
| `jellyfin.users(c)` | `list of User` | the user accounts the client may see (every one, on a default server) |
| `jellyfin.refreshLibrary(c)` | `null` | administrator; scan every library |
| `jellyfin.tasks(c)` | `list of Task` | administrator; the scheduled tasks |
| `jellyfin.runTask(c, id)` | `null` | administrator; start a task now |
| `jellyfin.sessions(c)` | `list of Session` | the sessions the server knows, recently active included, and what they play |
| `jellyfin.sendMessage(c, sessionId, header, text, timeoutMs)` | `null` | show a message on a client |
| `jellyfin.playstate(c, sessionId, command)` | `null` | pause, resume, stop, skip a client's playback |

## Types

### `Client`

| Field | Meaning |
|---|---|
| `baseUrl as string` | the server's URL without a trailing slash |
| `token as string` | the access token or API key, `""` before signing in |
| `userId as string` | the user of the per-user calls, `""` when not set |
| `clientName as string` | the client name the server shows |
| `deviceName as string` | the device name the server shows |
| `deviceId as string` | the device id |
| `tls as http.TlsOptions` | certificate checks for https |
| `allowPlainHttp as bool` | plain http to another machine allowed |
| `timeoutMs as int` | the deadline of one request |
| `maxBytes as int` | the largest response |

### `HttpError`

| Field | Meaning |
|---|---|
| `kind as string` | always `"jellyfin.http"` |
| `message as string` | `jellyfin: <request>: <why> (HTTP nnn)` |
| `status as int` | the HTTP status, such as 401 or 404 |
| `fields as map of string to string` | the validation errors, field -> its first message; empty when none |

### `Item`

| Field | Meaning |
|---|---|
| `id as string` | the item's id |
| `name as string` | its name |
| `type as string` | `Movie`, `Series`, `Season`, `Episode`, `MusicAlbum`, `Audio`, `Folder`, ... |
| `parentId as string` | what it is in |
| `seriesId as string` | an episode's or season's series |
| `seriesName as string` | that series' name |
| `season as int` | an episode's season number, 0 if none |
| `episode as int` | an episode's (or track's) number, 0 if none |
| `year as int` | the production year, 0 if unknown |
| `runtimeSeconds as int` | the length, 0 if unknown |
| `path as string` | the file on the server, `""` when not told |
| `played as bool` | the user played it |
| `favorite as bool` | a favourite of the user |
| `positionSeconds as int` | where the user stopped |
| `raw as json.Value` | the item as the server sent it |

### `Page`

| Field | Meaning |
|---|---|
| `items as list of Item` | the items on this page |
| `total as int` | how many match in all |
| `start as int` | the index of the first on this page |

### `Library`

| Field | Meaning |
|---|---|
| `id as string` | its id, the `parentId` of what is in it |
| `name as string` | its name |
| `collectionType as string` | `movies`, `tvshows`, `music`, ... or `""` |

### `ServerInfo`

| Field | Meaning |
|---|---|
| `name as string` | the server's name |
| `version as string` | its version |
| `id as string` | its id |
| `productName as string` | `Jellyfin Server` |
| `operatingSystem as string` | the host's OS, `""` when not told |
| `wizardCompleted as bool` | the first-run wizard is done |

### `User`

| Field | Meaning |
|---|---|
| `id as string` | the user's id |
| `name as string` | the user name |
| `hasPassword as bool` | the account has a password |
| `isAdministrator as bool` | the user administers the server |
| `isDisabled as bool` | the account is disabled |
| `lastLogin as string` | the last sign-in, ISO 8601, `""` if never |

### `Task`

| Field | Meaning |
|---|---|
| `id as string` | the task's id |
| `key as string` | its stable key, such as `RefreshLibrary` |
| `name as string` | its name, in the server's language |
| `category as string` | its category |
| `state as string` | `Idle`, `Running` or `Cancelling` |
| `lastResult as string` | `Completed`, `Failed`, `Cancelled`, `Aborted`, or `""` |

### `Session`

| Field | Meaning |
|---|---|
| `id as string` | the session's id |
| `userName as string` | who is signed in |
| `client as string` | the application |
| `deviceName as string` | the device |
| `nowPlaying as list of Item` | what it plays: one item, or nothing |
| `paused as bool` | playback is paused |
| `positionSeconds as int` | the playback position |
| `remoteControl as bool` | it takes commands |
| `lastActivity as string` | when it was last active |
