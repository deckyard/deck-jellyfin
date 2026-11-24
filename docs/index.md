<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/jellyfin

[Jellyfin™](https://jellyfin.org/) is a self-hosted media server for films,
shows, music and photos. This deck is a client for its REST API: sign in,
browse and search what a user sees, keep track of what was played, fetch
posters, and look after the server (users, library scans, scheduled tasks,
the clients playing right now).

- [Signing in](signing-in.md): passwords, API keys, users, devices.
- [The library](library.md): libraries, items, paging, search, resume,
  next up, played and favourite marks, images.
- [Administration](admin.md): the server, users, scans, tasks, sessions.
- [Cheatsheet](cheatsheet.md): every export.

## Conventions

Snippets assume this import:

```jennifer
import "@deckyard/jellyfin/" as jellyfin;
```

A request the server refused throws `jellyfin.HttpError`, kind
`jellyfin.http`, with the HTTP `status` and the validation errors as
`fields`; a response over its cap, a JSON answer past the decoder's caps and
`allItems` past its `most` are kind `"limit"`, a request with no answer by its
deadline kind `"timeout"`, a reply cut short kind `"closed"`; a network failure
(refused, reset, unreachable, DNS, TLS) is the interpreter's `net.NetError`,
kind `"net"`, passed on unchanged with its `reason`; any other failure is
`Error{kind: "jellyfin"}` (a cancelled task stays kind `"cancelled"`, "task
cancelled"):

```jennifer
try {
    def it as jellyfin.Item init jellyfin.item($c, $id);
} catch (e) {
    if ($e.kind == "jellyfin.http" and $e.status == 404) {
        io.printf("no such item\n");
    } else {
        throw $e;
    }
}
```

Every request has a deadline (30 s) and a response cap (16 MiB). Plain
`http` is refused except to this machine, because the password and token
would cross the network in clear; a server on the LAN without TLS needs
`withPlainHttp`. Ids, query parameter names and paths are checked before
they go into a URL.

The deck follows the Jellyfin 10.9-and-later API (user ids as query
parameters, `/UserViews`, `/UserItems/Resume`, `/UserPlayedItems`). It
needs the `net` capability and does not run on `jennifer-tiny`.

## Trademarks

Jellyfin™ and other product and company names may be trademarks of their
respective owners. They are used only to identify the products this deck
works with. This deck is an independent project, not affiliated with,
sponsored or endorsed by the Jellyfin project.
