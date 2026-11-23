# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# jellyfin - white-box tests for the library topic. Spliced into
# jellyfin_test.j via include.

# an episode as the server sends it
def const EPISODE as string init '{"Id":"0a1b2c3d4e5f60718293a4b5c6d7e8f9","Name":"Pilot","Type":"Episode","ParentId":"1111111111111111111111111111aaaa","SeriesId":"2222222222222222222222222222bbbb","SeriesName":"The Show","ParentIndexNumber":1,"IndexNumber":1,"ProductionYear":2024,"RunTimeTicks":26400000000,"Path":"/media/tv/s01e01.mkv","UserData":{"Played":false,"IsFavorite":true,"PlaybackPositionTicks":6000000000}}';

/**
 * A page of the fake's items.
 *
 * @param ids {list of string} the ids
 * @param total {int} the total
 * @param start {int} the start index
 * @return {string} the JSON page
 */
func pageJson(ids as list of string, total as int, start as int) {
    def parts as list of string init [];
    for (def id in $ids) {
        $parts[] = '{"Id":"' + $id + '","Name":"n' + $id[..4] + '","Type":"Movie"}';
    }
    return '{"Items":[' + strings.join($parts, ",") + '],"TotalRecordCount":' +
        convert.toString($total) +
        ',"StartIndex":' + convert.toString($start) + '}';
}

/**
 * A GUID made from a number.
 *
 * @param n {int} the number
 * @return {string} 32 hex digits
 */
func guid(n as int) {
    def s as string init convert.toString($n);
    return strings.replicate("0", 32 - len($s)) + $s;
}

func testItemsAreRead() {
    def it as Item init itemFrom(json.decode(EPISODE));
    testing.assertEqual($it.name, "Pilot");
    testing.assertEqual(
        $it.seriesName + " " + convert.toString($it.season) + "x" + convert.toString($it.episode),
        "The Show 1x1");
    testing.assertEqual($it.runtimeSeconds, 2640);
    testing.assertEqual($it.positionSeconds, 600);
    testing.assertTrue($it.favorite);
    testing.assertFalse($it.played);
    testing.assertEqual($it.path, "/media/tv/s01e01.mkv");
    testing.assertEqual(json.asInt($it.raw, "/ProductionYear"), 2024);
    def bare as Item init itemFrom(json.decode('{"Id":"' + guid(3) +
        '","Name":"Folder","ParentId":null}'));
    testing.assertEqual($bare.parentId + "|" + convert.toString($bare.year), "|0");
    for (def bad in ['{"Name":"no id"}', '{"Id":"x","Name":7}', '[]']) {
        try {
            itemFrom(json.decode($bad));
            missed($bad);
        } catch (e) {
            testing.assertEqual($e.kind, "jellyfin");
        }
    }
}

func testLibrariesItemsAndSearch() {
    def f as Fake init startFake({
        "GET /UserViews?userId=" + USER: "200\n\n" +
            '{"Items":[{"Id":"' + guid(1) +
            '","Name":"Movies","Type":"CollectionFolder","CollectionType":"movies"}],"TotalRecordCount":1}',
        "GET /Items?userId=" + USER +
            "&includeItemTypes=Movie&limit=2&fields=ParentId%2CPath": "200\n\n" +
            pageJson([guid(5), guid(6)], 9, 0),
        "GET /Items?userId=" + USER +
            "&searchTerm=Star%20Wars&recursive=true&limit=10&fields=ParentId%2CPath": "200\n\n" +
            pageJson([guid(7)], 1, 0),
        "GET /Items/" + ITEM + "?userId=" + USER: "200\n\n" + EPISODE
    });
    def c as Client init fakeClient($f);
    def libs as list of Library init libraries($c);
    testing.assertEqual($libs[0].name + "/" + $libs[0].collectionType, "Movies/movies");
    def p as Page init items($c, ["includeItemTypes=Movie", "limit=2"]);
    testing.assertEqual(len($p.items), 2);
    testing.assertEqual($p.total, 9);
    testing.assertEqual(search($c, "Star Wars", 10)[0].id, guid(7));
    testing.assertEqual(item($c, ITEM).name, "Pilot");
    try {
        item($c, "../System/Info");
        missed("a path as id");
    } catch (e) {
        testing.assertContains($e.message, "an item id is a GUID");
    }
    try {
        items(withToken(client($f.base), TOKEN), []);
        missed("no user");
    } catch (e) {
        testing.assertContains($e.message, "items: no user: sign in with login, or add withUser");
    }
    def seen as list of string init stopFake($f);
    testing.assertContains($seen[0], "Authorization=MediaBrowser Client=\"Jennifer\"");
}

func testAllItemsPages() {
    def answers as map of string to string init {};
    def base as string init "GET /Items?userId=" + USER + "&includeItemTypes=Episode";
    $answers[$base + "&startIndex=0&limit=200&fields=ParentId%2CPath"] = "200\n\n" +
        pageJson([guid(1), guid(2)], 5, 0);
    $answers[$base + "&startIndex=2&limit=200&fields=ParentId%2CPath"] = "200\n\n" +
        pageJson([guid(3), guid(4)], 5, 2);
    $answers[$base + "&startIndex=4&limit=200&fields=ParentId%2CPath"] = "200\n\n" +
        pageJson([guid(5)], 5, 4);
    def f as Fake init startFake($answers);
    def c as Client init fakeClient($f);
    def all as list of Item init allItems($c, ["includeItemTypes=Episode"], 100);
    testing.assertEqual(len($all), 5);
    testing.assertEqual($all[4].id, guid(5));
    try {
        allItems($c, ["includeItemTypes=Episode"], 3);
        missed("more than asked for");
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
        testing.assertEqual(
            $e.message,
            "jellyfin: allItems: 5 items match, more than the 3 asked for");
    }
    try {
        allItems($c, ["limit=5"], 10);
        missed("a limit");
    } catch (e) {
        testing.assertContains($e.message, "allItems pages by itself");
    }
    stopFake($f);
}

func testLatestResumeNextUpEpisodes() {
    def f as Fake init startFake({
        "GET /Items/Latest?userId=" + USER + "&limit=5&fields=ParentId%2CPath&parentId=" +
            guid(1): "200\n\n[" + EPISODE +
            "]",
        "GET /UserItems/Resume?userId=" + USER + "&limit=3&fields=ParentId%2CPath": "200\n\n" +
            pageJson([guid(8)], 1, 0),
        "GET /Shows/NextUp?userId=" + USER + "&limit=3&fields=ParentId%2CPath": "200\n\n" +
            pageJson([guid(9)], 1, 0),
        "GET /Shows/" + guid(2) + "/Episodes?userId=" + USER +
            "&isMissing=false&fields=ParentId%2CPath": "200\n\n" + '{"Items":[' + EPISODE +
            '],"TotalRecordCount":1}'
    });
    def c as Client init fakeClient($f);
    testing.assertEqual(latest($c, guid(1), 5)[0].name, "Pilot");
    testing.assertEqual(resume($c, 3)[0].id, guid(8));
    testing.assertEqual(nextUp($c, 3)[0].id, guid(9));
    testing.assertEqual(episodes($c, guid(2))[0].episode, 1);
    for (def n in [0, 1001]) {
        try {
            latest($c, "", $n);
            missed("limit");
        } catch (e) {
            testing.assertContains($e.message, "the limit must be 1 to 1000");
        }
    }
    stopFake($f);
}

func testMarksImagesAndRefresh() {
    def png as string init "PNGDATA";
    def f as Fake init startFake({
        "POST /UserPlayedItems/" + ITEM + "?userId=" + USER: "200\n\n" + '{"Played":true}',
        "DELETE /UserPlayedItems/" + ITEM + "?userId=" + USER: "200\n\n" + '{"Played":false}',
        "POST /UserFavoriteItems/" + ITEM + "?userId=" + USER: "200\n\n" + '{"IsFavorite":true}',
        "DELETE /UserFavoriteItems/" + ITEM + "?userId=" + USER: "200\n\n" + '{"IsFavorite":false}',
        "GET /Items/" + ITEM + "/Images/Primary?maxWidth=300": "200\nContent-Type: image/png\n\n" +
            $png,
        "POST /Items/" + ITEM +
            "/Refresh?metadataRefreshMode=Default&imageRefreshMode=Default": "204\n\n"
    });
    def c as Client init fakeClient($f);
    setPlayed($c, ITEM, true);
    setPlayed($c, ITEM, false);
    setFavorite($c, ITEM, true);
    setFavorite($c, ITEM, false);
    testing.assertEqual(encoding.decode("utf-8", image($c, ITEM, "Primary", 300)), $png);
    refreshItem($c, ITEM);
    try {
        image($c, ITEM, "Poster", 0);
        missed("an unknown image type");
    } catch (e) {
        testing.assertContains($e.message, "an image type is one of");
    }
    try {
        image($c, ITEM, "Backdrop", 0);
        missed("no backdrop");
    } catch (e) {
        testing.assertEqual($e.kind, "jellyfin.http");
        testing.assertEqual($e.status, 404);
    }
    def seen as list of string init stopFake($f);
    testing.assertEqual(len($seen), 7);
}

func testAllItemsRefusesWhatWouldMislead() {
    for (def bad in ["StartIndex=1", "LIMIT=5", "enableTotalRecordCount=false"]) {
        try {
            allItems(withUser(client("https://m.example.org"), USER), [$bad], 10);
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "allItems pages by itself");
        }
    }
    def f as Fake init startFake({
        "GET /Items": "200\n\n" + pageJson([guid(1), guid(2), guid(3)], 2, 0)
    });
    try {
        allItems(fakeClient($f), [], 10);
        missed("more items than the total");
    } catch (e) {
        testing.assertContains($e.message, "the paging does not add up");
    }
    stopFake($f);
    def g as Fake init startFake({"GET /Items": "200\n\n" + pageJson([guid(1)], 5, 3)});
    try {
        allItems(fakeClient($g), [], 10);
        missed("a page at another start");
    } catch (e) {
        testing.assertContains($e.message, "the paging does not add up");
    }
    stopFake($g);
    try {
        itemFrom(json.decode('{"Id":"../../x"}'));
        missed("a path as id");
    } catch (e) {
        testing.assertContains($e.message, "without a GUID Id");
    }
}
