# @deckyard/jellyfin

[![test](https://github.com/deckyard/deck-jellyfin/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-jellyfin/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-jellyfin/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-jellyfin)](https://github.com/deckyard/deck-jellyfin/releases/latest)

A client for the REST API of [Jellyfin](https://jellyfin.org/), the
self-hosted media server, for [Jennifer](https://jennifer-lang.dev/)
programs: sign in with a password or an API key; browse, page and search
a user's libraries; latest additions, resume and next up; played and
favourite marks; posters and other images; and the administration side:
users, library scans, scheduled tasks and the sessions of clients playing
media. Every request has a deadline and a response cap, and plain http is
refused except to this machine unless allowed.

**[Documentation](https://deckyard.github.io/deck-jellyfin/)**

## Install

```sh
jvc add @deckyard/jellyfin
```

This vendors the deck to `vendor/<scope>/jellyfin/`. Without `jvc`, unpack the
`src/` subtree of a release archive (`<scope>-jellyfin-<version>.tar.gz`) there.

## Usage

```jennifer
use io;
use os;

import "@deckyard/jellyfin/" as jellyfin;

def c as jellyfin.Client init jellyfin.login(
    jellyfin.client("https://media.example.org"), "alice", os.getEnv("JELLYFIN_PASSWORD"));
for (def it in jellyfin.resume($c, 10)) {
    io.printf("%s at %d s\n", $it.name, $it.positionSeconds);
}
```

## Requirements

Jennifer 0.26.0 or newer and the default `jennifer` binary (the deck needs
`net`), and Jellyfin 10.9 or newer.

## Development

```sh
tools/check-all.sh                   # the full gate, as CI runs it
jennifer test src/jellyfin_test.j    # the tests, against a fake server
tools/check-docs.sh                  # docs against the code
tools/pack.sh dist                   # build the release archive
```

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.

`tools/check-headers.sh` checks every source file's SPDX header against
`deck.toml`.
