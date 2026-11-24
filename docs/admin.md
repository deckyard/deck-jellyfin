<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Administration

These calls need an administrator, or an API key, except `serverInfo`,
which anyone may make, `users`, which a default server answers for any
signed-in user, and `sessions`, where a user sees their own.

## The server

```jennifer
def s as jellyfin.ServerInfo init jellyfin.serverInfo($c);
io.printf("%s, Jellyfin %s\n", $s.name, $s.version);
```

`serverInfo` also checks that the URL answers as Jellyfin™, version
`MIN_MAJOR` or later.

## Users

```jennifer
for (def u in jellyfin.users($c)) {
    if ($u.isAdministrator) {
        io.printf("%s (administrator)\n", $u.name);
    }
}
```

## Library scans and tasks

`refreshLibrary` scans every library; `refreshItem` looks at one item
again, as the web interface's "Scan for new and updated files" does:
changed files are reread and missing metadata and images filled in,
metadata the item has is kept. Both start the work and return; the server
does it in the background. Tasks are found by their `key`, since their
names are translated:

```jennifer
for (def t in jellyfin.tasks($c)) {
    if ($t.key == "RefreshLibrary" and $t.state == "Idle") {
        jellyfin.runTask($c, $t.id);
    }
}
```

## Sessions

`sessions` lists the sessions the server knows, recently active ones
included, and what they play;
`sendMessage` shows a note on one and `playstate` controls its playback:

```jennifer
for (def s in jellyfin.sessions($c)) {
    if (len($s.nowPlaying) > 0 and $s.remoteControl) {
        jellyfin.sendMessage($c, $s.id, "Server", "Restarting in 5 minutes", 10000);
        jellyfin.playstate($c, $s.id, "Pause");
    }
}
```

## Anything else

`call` reaches any other endpoint of the
[API](https://api.jellyfin.org/), with the client's authorization, deadline
and cap:

```jennifer
def plugins as json.Value init jellyfin.call($c, "GET", "/Plugins", [], json.decode("null"));
```
