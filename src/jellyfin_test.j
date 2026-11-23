# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

/**
 * White-box tests: jennifer test src/jellyfin_test.j
 *
 * No test needs a Jellyfin server. A fake on 127.0.0.1 (`startFake` in the
 * core overlay) answers each request from a script and records what it
 * got; the answers follow the shapes of Jellyfin's OpenAPI description. The
 * topic overlays are fragments spliced in here, not standalone suites.
 */
use httpd;
use maps;
use testing;
use time;

include "topics/core_test.j";
include "topics/library_test.j";
include "topics/admin_test.j";
