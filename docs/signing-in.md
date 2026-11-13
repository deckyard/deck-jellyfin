<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Signing in

## With a password

```jennifer
def c as jellyfin.Client init jellyfin.client("https://media.example.org");
$c = jellyfin.login($c, "alice", os.getEnv("JELLYFIN_PASSWORD"));
io.printf("signed in as %s\n", jellyfin.me($c).name);
```

`login` returns the client with the access token and the user's id; every
per-user call then acts for that user. `logout` ends the session on the
server and its token stops working. An API key is no session: `logout`
leaves it working; revoke a key on the dashboard.

## With an API key

An administrator creates API keys under Dashboard > API Keys. A key
belongs to no user: it can administer the server, and with `withUser` it
acts for a user in the per-user calls:

```jennifer
def c as jellyfin.Client init jellyfin.withToken(jellyfin.client("https://media.example.org"), $apiKey);
for (def u in jellyfin.users($c)) {
    def asUser as jellyfin.Client init jellyfin.withUser($c, $u.id);
    io.printf("%s: %d to resume\n", $u.name, len(jellyfin.resume($asUser, 100)));
}
```

`me` needs a signed-in user; it fails for a bare API key.

## The device

Jellyfin keeps one session per device id and shows the client and device
names on its dashboard. `client` picks a random device id each time; a
program that signs in on every run should give a stable one, or the
server collects a session per run. Signing in again ends the earlier
session of the same user on the same device id, so two programs running at
once need different ids:

```jennifer
$c = jellyfin.withDevice($c, "Media Sync", "backup-host", "media-sync-backup-host");
```

## Plain http

A server on the LAN often runs without TLS. The deck refuses plain `http`
to anything but this machine unless told:

```jennifer
def c as jellyfin.Client init jellyfin.withPlainHttp(jellyfin.client("http://nas.local:8096"));
```

The password and token then cross the network in clear.
