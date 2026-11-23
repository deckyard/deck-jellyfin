# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# jellyfin - library: what a user sees. Libraries, items with paging and
# search, latest additions, resume and next up, episodes, played and
# favourite marks, images and metadata refresh. Spliced into jellyfin.j via
# include.

/** The most items `allItems` reads: 20000, about 450 MB with each item's JSON. */
export def const MAX_ITEMS as int init 20000;

# the fields the list calls ask for besides the default ones, so `path` and
# `parentId` are filled
def const FIELDS as string init "fields=ParentId,Path";

# how many items one page of `allItems` asks for
def const PAGE as int init 200;

# the ticks of one second, Jellyfin's time unit
def const TICKS as int init 10000000;

# the image types an item can have
def const IMAGE_TYPES as list of string init [
    "Primary",
    "Art",
    "Backdrop",
    "Banner",
    "Logo",
    "Thumb",
    "Disc",
    "Box",
    "Screenshot",
    "Menu",
    "Chapter",
    "BoxRear",
    "Profile"
];

/**
 * One item: a movie, episode, series, season, album, song, folder, ... The
 * fields most programs need, and the whole JSON for the rest.
 *
 * @field id {string} the item's id
 * @field name {string} its name
 * @field type {string} its kind: `Movie`, `Series`, `Season`, `Episode`, `MusicAlbum`, `Audio`, `Folder`, `CollectionFolder`, ...
 * @field parentId {string} the folder, season or album it is in, `""` when none or not sent
 * @field seriesId {string} the series of an episode or season, `""` otherwise
 * @field seriesName {string} that series' name
 * @field season {int} an episode's season number, 0 when none
 * @field episode {int} an episode's number (a track's number on an album), 0 when none
 * @field year {int} the production year, 0 when unknown
 * @field runtimeSeconds {int} the length in seconds, 0 when unknown
 * @field path {string} the file or folder on the server, `""` when the server does not tell this user (every list call asks for it; a `fields=` of your own in `items` replaces that)
 * @field played {bool} the user has played it
 * @field favorite {bool} it is one of the user's favourites
 * @field positionSeconds {int} where the user stopped, for resume; 0 when not started
 * @field raw {json.Value} the item as the server sent it
 */
export def struct Item {
    id as string,
    name as string,
    type as string,
    parentId as string,
    seriesId as string,
    seriesName as string,
    season as int,
    episode as int,
    year as int,
    runtimeSeconds as int,
    path as string,
    played as bool,
    favorite as bool,
    positionSeconds as int,
    raw as json.Value
};

/**
 * One page of items.
 *
 * @field items {list of Item} the items on this page
 * @field total {int} how many items match in all
 * @field start {int} the index of the first item on this page
 */
export def struct Page {
    items as list of Item,
    total as int,
    start as int
};

/**
 * A library (a user view): Movies, Shows, Music, ...
 *
 * @field id {string} its id, the `parentId` of what is in it
 * @field name {string} its name
 * @field collectionType {string} `movies`, `tvshows`, `music`, `books`, `homevideos`, `boxsets`, `playlists`, ... or `""` for mixed
 */
export def struct Library {
    id as string,
    name as string,
    collectionType as string
};

/**
 * A string at a JSON pointer, `""` when absent or null.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {string} the string
 */
func textAt(v as json.Value, ptr as string) {
    def t as string init json.typeOf($v, $ptr);
    if ($t == "missing" or $t == "null") {
        return "";
    }
    if ($t != "string") {
        fail(shown($ptr) + " is a " + $t + ", not a string");
    }
    return json.asString($v, $ptr);
}

/**
 * An integer at a JSON pointer, 0 when absent or null.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {int} the number
 */
func intAt(v as json.Value, ptr as string) {
    def t as string init json.typeOf($v, $ptr);
    if ($t == "missing" or $t == "null") {
        return 0;
    }
    if ($t != "int") {
        fail(shown($ptr) + " is a " + $t + ", not an integer");
    }
    return json.asInt($v, $ptr);
}

/**
 * A boolean at a JSON pointer, false when absent or null.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {bool} the value
 */
func boolAt(v as json.Value, ptr as string) {
    def t as string init json.typeOf($v, $ptr);
    if ($t == "missing" or $t == "null") {
        return false;
    }
    if ($t != "bool") {
        fail(shown($ptr) + " is a " + $t + ", not a boolean");
    }
    return json.asBool($v, $ptr);
}

/**
 * An item from the server's JSON.
 *
 * @param v {json.Value} the item
 * @return {Item} the item
 */
func itemFrom(v as json.Value) {
    if (json.typeOf($v) != "map" or not regex.matches(GUID, textAt($v, "/Id"))) {
        fail("the server returned an item without a GUID Id");
    }
    return Item{
        id: textAt($v, "/Id"),
        name: textAt($v, "/Name"),
        type: textAt($v, "/Type"),
        parentId: textAt($v, "/ParentId"),
        seriesId: textAt($v, "/SeriesId"),
        seriesName: textAt($v, "/SeriesName"),
        season: intAt($v, "/ParentIndexNumber"),
        episode: intAt($v, "/IndexNumber"),
        year: intAt($v, "/ProductionYear"),
        runtimeSeconds: intAt($v, "/RunTimeTicks") // TICKS,
        path: textAt($v, "/Path"),
        played: boolAt($v, "/UserData/Played"),
        favorite: boolAt($v, "/UserData/IsFavorite"),
        positionSeconds: intAt($v, "/UserData/PlaybackPositionTicks") // TICKS,
        raw: $v
    };
}

/**
 * The items of a JSON list.
 *
 * @param v {json.Value} the document
 * @param ptr {string} where the list is, `""` for the document itself
 * @param what {string} the request, for messages
 * @return {list of Item} the items
 */
func itemsAt(v as json.Value, ptr as string, what as string) {
    if (json.typeOf($v, $ptr) != "list") {
        fail($what + ": the server returned no list of items");
    }
    def out as list of Item init [];
    for (def i in 0..json.length($v, $ptr)) {
        $out[] = itemFrom(json.get($v, $ptr + "/" + convert.toString($i)));
    }
    return $out;
}

/**
 * A page from a `{Items, TotalRecordCount, StartIndex}` result.
 *
 * @param v {json.Value} the result
 * @param what {string} the request, for messages
 * @return {Page} the page
 */
func pageFrom(v as json.Value, what as string) {
    return Page{
        items: itemsAt($v, "/Items", $what),
        total: intAt($v, "/TotalRecordCount"),
        start: intAt($v, "/StartIndex")
    };
}

/**
 * The user the per-user calls are for, as a query parameter.
 *
 * @param c {Client} the client
 * @param what {string} the request, for messages
 * @return {string} `userId=...`
 */
func userParam(c as Client, what as string) {
    if ($c.userId == "") {
        fail($what + ": no user: sign in with login, or add withUser to an API key");
    }
    return "userId=" + $c.userId;
}

/**
 * The libraries the user sees.
 *
 * @param c {Client} the client, signed in or with `withUser`
 * @return {list of Library} the libraries
 * @throws {Error} kind "jellyfin" when no user is set or the request fails
 * @example
 *   for (def l in jellyfin.libraries($c)) {
 *       io.printf("%s (%s)\n", $l.name, $l.collectionType);
 *   }
 */
export func libraries(c as Client) {
    def v as json.Value init request(
        $c,
        "GET",
        "/UserViews" + queryOf([userParam($c, "libraries")]),
        "",
        "libraries");
    def out as list of Library init [];
    for (def it in itemsAt($v, "/Items", "libraries")) {
        $out[] = Library{
            id: $it.id,
            name: $it.name,
            collectionType: textAt($it.raw, "/CollectionType")
        };
    }
    return $out;
}

/**
 * One page of the user's items, filtered and sorted by the server.
 *
 * @param c {Client} the client, signed in or with `withUser`
 * @param query {list of string} parameters as `name=value`: `parentId=<library>`, `recursive=true`, `includeItemTypes=Movie,Series`, `searchTerm=...`, `isPlayed=false`, `sortBy=SortName`, `sortOrder=Descending`, `fields=Path,Overview`, `startIndex=0`, `limit=50`, ...
 * @return {Page} the page
 * @throws {Error} kind "jellyfin" when no user is set, a parameter is malformed, or the request fails
 * @example
 *   def p as jellyfin.Page init jellyfin.items($c, ["includeItemTypes=Movie", "recursive=true", "limit=20"]);
 *   io.printf("%d movies\n", $p.total);
 */
export func items(c as Client, query as list of string) {
    def q as list of string init [userParam($c, "items")];
    def hasFields as bool init false;
    for (def x in $query) {
        $q[] = $x;
        if (strings.startsWith(strings.lower($x), "fields=")) {
            $hasFields = true;
        }
    }
    if (not $hasFields) {
        $q[] = FIELDS;
    }
    return pageFrom(request($c, "GET", "/Items" + queryOf($q), "", "items"), "items");
}

/**
 * Every item that matches, reading page after page.
 *
 * @param c {Client} the client, signed in or with `withUser`
 * @param query {list of string} parameters as for `items`, without `startIndex` or `limit`
 * @param most {int} the most items to read, 1 to `MAX_ITEMS`; more is an error. Each item keeps its JSON: about 22 KB of memory for a typical item
 * @return {list of Item} the items
 * @throws {Error} kind "limit" when more than `most` items match; kind "jellyfin" when the query sets `startIndex`, `limit` or `enableTotalRecordCount`, the pages the server sends do not add up, a parameter is malformed, or a request fails
 * @example
 *   def all as list of jellyfin.Item init jellyfin.allItems($c, ["includeItemTypes=Episode", "recursive=true", "isPlayed=false"], 5000);
 */
export func allItems(c as Client, query as list of string, most as int) {
    checkRange($most, 1, MAX_ITEMS, "the most items");
    for (def x in $query) {
        def name as string init strings.lower($x);
        if (strings.startsWith($name, "startindex=") or strings.startsWith($name, "limit=") or
            strings.startsWith($name, "enabletotalrecordcount=")) {
            fail("allItems pages by itself: leave out " + shown($x));
        }
    }
    def out as list of Item init [];
    def start as int init 0;
    def total as int init 1;
    while ($start < $total) {
        def q as list of string init $query;
        $q[] = "startIndex=" + convert.toString($start);
        $q[] = "limit=" + convert.toString(PAGE);
        def p as Page init items($c, $q);
        $total = $p.total;
        if ($total > $most) {
            failLimit(io.sprintf(
                "allItems: %d items match, more than the %d asked for",
                $total,
                $most));
        }
        if ($p.start != $start or $total < $start + len($p.items) or len($out) +
            len($p.items) > $most) {
            fail(io.sprintf(
                "allItems: the server sent page %d with %d items of %d; the paging does not add up",
                $p.start,
                len($p.items),
                $total));
        }
        for (def it in $p.items) {
            $out[] = $it;
        }
        if (len($p.items) == 0) {
            $start = $total;
        } else {
            $start = $start + len($p.items);
        }
    }
    return $out;
}

/**
 * One item, as the user sees it.
 *
 * @param c {Client} the client, signed in or with `withUser`
 * @param id {string} the item's id
 * @return {Item} the item
 * @throws {HttpError} kind "jellyfin.http" when the item does not exist (status 404) or another status is not 2xx
 * @throws {Error} kind "jellyfin" when the id is malformed, or the request fails
 */
export func item(c as Client, id as string) {
    checkId($id, "an item id");
    return itemFrom(request(
        $c,
        "GET",
        "/Items/" + $id + queryOf([userParam($c, "item")]),
        "",
        "item " + $id));
}

/**
 * Items by name, in every library.
 *
 * @param c {Client} the client, signed in or with `withUser`
 * @param term {string} what to look for
 * @param limit {int} the most results, 1 to 1000
 * @return {list of Item} the matches
 */
export func search(c as Client, term as string, limit as int) {
    if (strings.trim($term) == "") {
        fail("search: the term is empty");
    }
    checkRange($limit, 1, 1000, "the limit");
    return items($c, ["searchTerm=" + $term, "recursive=true", "limit=" + convert.toString($limit)]).items;
}

/**
 * The latest additions, newest first; episodes of one series grouped.
 *
 * @param c {Client} the client, signed in or with `withUser`
 * @param parentId {string} a library's id, `""` for all
 * @param limit {int} the most items, 1 to 1000
 * @return {list of Item} the items
 */
export func latest(c as Client, parentId as string, limit as int) {
    checkRange($limit, 1, 1000, "the limit");
    def q as list of string init [
        userParam($c, "latest"),
        "limit=" + convert.toString($limit),
        FIELDS
    ];
    if ($parentId != "") {
        checkId($parentId, "a library id");
        $q[] = "parentId=" + $parentId;
    }
    return itemsAt(request($c, "GET", "/Items/Latest" + queryOf($q), "", "latest"), "", "latest");
}

/**
 * What the user started and did not finish, most recent first.
 *
 * @param c {Client} the client, signed in or with `withUser`
 * @param limit {int} the most items, 1 to 1000
 * @return {list of Item} the items, with `positionSeconds`
 */
export func resume(c as Client, limit as int) {
    checkRange($limit, 1, 1000, "the limit");
    def q as list of string init [
        userParam($c, "resume"),
        "limit=" + convert.toString($limit),
        FIELDS
    ];
    return pageFrom(request($c, "GET", "/UserItems/Resume" + queryOf($q), "", "resume"), "resume").items;
}

/**
 * The next episode to watch of each series the user is in.
 *
 * @param c {Client} the client, signed in or with `withUser`
 * @param limit {int} the most episodes, 1 to 1000
 * @return {list of Item} the episodes
 */
export func nextUp(c as Client, limit as int) {
    checkRange($limit, 1, 1000, "the limit");
    def q as list of string init [
        userParam($c, "nextUp"),
        "limit=" + convert.toString($limit),
        FIELDS
    ];
    return pageFrom(request($c, "GET", "/Shows/NextUp" + queryOf($q), "", "next up"), "next up").items;
}

/**
 * Every episode of a series that has a file, in order (episodes the server
 * only knows of from metadata are left out).
 *
 * @param c {Client} the client, signed in or with `withUser`
 * @param seriesId {string} the series' id
 * @return {list of Item} the episodes, with `season` and `episode`
 */
export func episodes(c as Client, seriesId as string) {
    checkId($seriesId, "a series id");
    def path as string init "/Shows/" + $seriesId + "/Episodes" +
        queryOf([userParam($c, "episodes"), "isMissing=false", FIELDS]);
    return pageFrom(request($c, "GET", $path, "", "episodes"), "episodes").items;
}

/**
 * Mark an item played or not played for the user.
 *
 * @param c {Client} the client, signed in or with `withUser`
 * @param id {string} the item's id
 * @param played {bool} true for played, false for not played
 * @throws {Error} kind "jellyfin" when the id is malformed or the request fails
 */
export func setPlayed(c as Client, id as string, played as bool) {
    checkId($id, "an item id");
    def method as string init "DELETE";
    if ($played) {
        $method = "POST";
    }
    request(
        $c,
        $method,
        "/UserPlayedItems/" + $id + queryOf([userParam($c, "setPlayed")]),
        "",
        "setPlayed " + $id);
}

/**
 * Add an item to the user's favourites, or take it out.
 *
 * @param c {Client} the client, signed in or with `withUser`
 * @param id {string} the item's id
 * @param favorite {bool} true to add, false to take out
 * @throws {Error} kind "jellyfin" when the id is malformed or the request fails
 */
export func setFavorite(c as Client, id as string, favorite as bool) {
    checkId($id, "an item id");
    def method as string init "DELETE";
    if ($favorite) {
        $method = "POST";
    }
    request(
        $c,
        $method,
        "/UserFavoriteItems/" + $id + queryOf([userParam($c, "setFavorite")]),
        "",
        "setFavorite " + $id);
}

/**
 * An image of an item: its poster, backdrop, logo, ...
 *
 * @param c {Client} the client
 * @param id {string} the item's id
 * @param type {string} `Primary` (the poster), `Backdrop`, `Logo`, `Thumb`, `Banner`, `Art`, ...
 * @param maxWidth {int} scale it down to at most this width, 0 for the original size
 * @return {bytes} the image (JPEG, PNG or WebP, as stored)
 * @throws {HttpError} kind "jellyfin.http" when the item has no such image (status 404) or another status is not 2xx
 * @throws {Error} kind "jellyfin" when the type is unknown; kind "limit" when the image is larger than `maxBytes`
 * @example
 *   fs.writeBytes("poster.jpg", jellyfin.image($c, $movie.id, "Primary", 600));
 */
export func image(c as Client, id as string, type as string, maxWidth as int) {
    checkId($id, "an item id");
    if (not lists.contains(IMAGE_TYPES, $type)) {
        fail("an image type is one of " + strings.join(IMAGE_TYPES, ", ") + ", got " + shown($type));
    }
    checkRange($maxWidth, 0, 10000, "the width");
    def path as string init "/Items/" + $id + "/Images/" + $type;
    if ($maxWidth > 0) {
        $path = $path + "?maxWidth=" + convert.toString($maxWidth);
    }
    def r as http.BytesResponse init exchange($c, "GET", $path, "", "image " + $id);
    checkStatus($r, "image " + $id);
    return $r.body;
}

/**
 * Ask the server to look at an item again, as the web interface's "Scan for
 * new and updated files" does: it rereads changed files and fills in
 * missing metadata and images, in the background. It does not replace
 * metadata the item already has.
 *
 * @param c {Client} the client, as an administrator
 * @param id {string} the item's id
 * @throws {HttpError} kind "jellyfin.http" when the user is not an administrator (status 403) or another status is not 2xx
 * @throws {Error} kind "jellyfin" when the id is malformed, or the request fails
 */
export func refreshItem(c as Client, id as string) {
    checkId($id, "an item id");
    def q as string init queryOf(["metadataRefreshMode=Default", "imageRefreshMode=Default"]);
    request($c, "POST", "/Items/" + $id + "/Refresh" + $q, "", "refreshItem " + $id);
}
