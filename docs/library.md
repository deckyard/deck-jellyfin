<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# The library

Everything here is what one user sees: their libraries, their played and
favourite marks, their place in a film.

## Libraries and items

```jennifer
for (def l in jellyfin.libraries($c)) {
    io.printf("%s (%s)\n", $l.name, $l.collectionType);
}
```

`items` asks the server for one page, with any of its filters as
`name=value` parameters; the `Page` says how many match in all:

```jennifer
def p as jellyfin.Page init jellyfin.items($c, [
    "parentId=" + $movies.id,
    "recursive=true",
    "includeItemTypes=Movie",
    "isPlayed=false",
    "sortBy=DateCreated",
    "sortOrder=Descending",
    "limit=20"
]);
io.printf("%d unwatched films, the newest %d:\n", $p.total, len($p.items));
```

`allItems` reads page after page, and refuses when more than `most` match
(an error of kind `"limit"`) rather than reading an unbounded result. It also refuses pages that do not
add up (a server that moved the window or sent more than the total), so
it never returns a short or doubled list. Each item keeps its JSON, about
22 KB of memory for a typical one, so `most` is capped at `MAX_ITEMS`
(20000):

```jennifer
def all as list of jellyfin.Item init jellyfin.allItems($c, ["includeItemTypes=Episode", "recursive=true"], 20000);
```

An `Item` has the fields most programs need (`name`, `type`, `year`,
`runtimeSeconds`, `season`, `episode`, `played`, `favorite`,
`positionSeconds`) and the whole JSON as `raw` for the rest
(`json.asString($it.raw, "/Overview")`). The list calls ask for `ParentId`
and `Path` (the server sends `Path` to administrators); ask for more with
`fields=Overview,Genres,ParentId,Path`, which replaces that request, so
name those two again.

## Shortcuts

| Call | Gives |
|---|---|
| `search(c, term, limit)` | items by name, in every library |
| `latest(c, parentId, limit)` | the newest additions (episodes grouped by series) |
| `resume(c, limit)` | what the user started and did not finish |
| `nextUp(c, limit)` | the next episode of each series in progress |
| `episodes(c, seriesId)` | a series in order |

## Played and favourites

```jennifer
jellyfin.setPlayed($c, $episode.id, true);
jellyfin.setFavorite($c, $film.id, true);
```

## Images

```jennifer
fs.writeBytes("poster.jpg", jellyfin.image($c, $film.id, "Primary", 600));
```

`Primary` is the poster; `Backdrop`, `Logo`, `Thumb`, `Banner` and `Art`
the others. An item without that image fails with HTTP 404. The width
scales it down on the server; 0 keeps the original.
