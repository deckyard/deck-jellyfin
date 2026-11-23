#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

/**
 * library example: sign in to a Jellyfin server and show what a user has:
 * each library with its item count, the latest additions, and what is left
 * to resume.
 *
 *   JELLYFIN_PASSWORD=... jennifer run examples/library.j https://media.example.org alice
 *   JELLYFIN_PASSWORD=... jennifer run examples/library.j http://localhost:8096 alice
 *
 * Without arguments it prints this usage, so CI runs it without a server.
 */

use io;
use os;

import "../src/jellyfin.j" as jellyfin;

def args as list of string init os.ARGS;
if (len($args) != 3) {
    io.printf("usage: JELLYFIN_PASSWORD=... jennifer run examples/library.j <url> <user>\n");
    exit 0;
}

try {
    def c as jellyfin.Client init jellyfin.client($args[1]);
    def server as jellyfin.ServerInfo init jellyfin.serverInfo($c);
    io.printf("%s, Jellyfin %s\n", $server.name, $server.version);
    $c = jellyfin.withDevice($c, "Jennifer example", "example", "jennifer-library-example");
    $c = jellyfin.login($c, $args[2], os.getEnv("JELLYFIN_PASSWORD"));
    for (def l in jellyfin.libraries($c)) {
        def p as jellyfin.Page init jellyfin.items(
            $c,
            ["parentId=" + $l.id, "recursive=true", "limit=1"]);
        io.printf("%s (%s): %d items\n", $l.name, $l.collectionType, $p.total);
    }
    io.printf("latest:\n");
    for (def it in jellyfin.latest($c, "", 5)) {
        io.printf("  %s (%s)\n", $it.name, $it.type);
    }
    io.printf("to resume:\n");
    for (def it in jellyfin.resume($c, 5)) {
        io.printf("  %s at %d of %d s\n", $it.name, $it.positionSeconds, $it.runtimeSeconds);
    }
    jellyfin.logout($c);
} catch (e) {
    io.eprintf("%s\n", $e.message);
    exit 1;
}
