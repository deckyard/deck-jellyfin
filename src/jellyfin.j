# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0
# pragma-jennifer-capability: net

/**
 * A client for the REST API of Jellyfin, the self-hosted media server:
 * sign in with a user name and password or an API key, read the user's
 * libraries and items with paging and search, latest additions, resume and
 * next up, episodes, mark items played or favourite, fetch posters and
 * other images, and administer the server: users, library scans, scheduled
 * tasks, and the sessions of clients playing media. `call` reaches any
 * other endpoint.
 *
 * Every request has a deadline and a response cap; plain `http` is refused
 * except to this machine unless allowed. A request the server refused
 * throws `HttpError` (kind `jellyfin.http`) with its `status` and validation
 * `fields`. The situations every library shares have their generic kinds: a
 * response over the cap, a JSON answer past the decoder's caps and
 * `allItems` past its `most` are `"limit"`, a deadline `"timeout"`, a reply
 * cut short `"closed"`, a network failure (refused, reset, unreachable, DNS,
 * TLS) the interpreter's `net.NetError` (`"net"`), passed on unchanged; every
 * other failure is `Error{kind: "jellyfin"}`.
 *
 * | topic | covers |
 * | --- | --- |
 * | `core` | `Client`, settings, sign-in, the exchange, errors, `call` |
 * | `library` | libraries, items, search, resume, next up, marks, images |
 * | `admin` | the server, users, scans, tasks, sessions |
 *
 * @module jellyfin
 * @see https://api.jellyfin.org/
 * @example
 *   def c as jellyfin.Client init jellyfin.login(jellyfin.client("https://media.example.org"), "alice", $password);
 *   for (def m in jellyfin.latest($c, "", 10)) {
 *       io.printf("%s (%d)\n", $m.name, $m.year);
 *   }
 */
use convert;
use encoding;
use io;
use json;
use lists;
use math;
use net;
use regex;
use strings;
use task;
use uuid;

import "http.j" as http;
import "uri.j" as uri;

include "topics/core.j";
include "topics/library.j";
include "topics/admin.j";
