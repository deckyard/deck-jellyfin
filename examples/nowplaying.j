#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

/**
 * nowplaying example: with an API key, list who is playing what on a
 * Jellyfin server right now.
 *
 *   JELLYFIN_API_KEY=... jennifer run examples/nowplaying.j https://media.example.org
 *
 * Without arguments it prints this usage, so CI runs it without a server.
 */

use io;
use os;

import "../src/jellyfin.j" as jellyfin;

def args as list of string init os.ARGS;
if (len($args) != 2) {
    io.printf("usage: JELLYFIN_API_KEY=... jennifer run examples/nowplaying.j <url>\n");
    exit 0;
}

try {
    def c as jellyfin.Client init jellyfin.withToken(
        jellyfin.client($args[1]),
        os.getEnv("JELLYFIN_API_KEY"));
    def playing as int init 0;
    for (def s in jellyfin.sessions($c)) {
        if (len($s.nowPlaying) > 0) {
            $playing = $playing + 1;
            def state as string init "playing";
            if ($s.paused) {
                $state = "paused";
            }
            io.printf(
                "%s on %s (%s): %s, %s at %d s\n",
                $s.userName,
                $s.deviceName,
                $s.client,
                $s.nowPlaying[0].name,
                $state,
                $s.positionSeconds);
        }
    }
    io.printf("%d playing\n", $playing);
} catch (e) {
    io.eprintf("%s\n", $e.message);
    exit 1;
}
