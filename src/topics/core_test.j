# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# jellyfin - white-box tests for the core topic, and the fake server the
# other overlays use. Spliced into jellyfin_test.j via include.

# a user, an item and a token for the fake
def const USER as string init "4bd7c0a1e2f34c5d8e9f0a1b2c3d4e5f";
def const ITEM as string init "0a1b2c3d4e5f60718293a4b5c6d7e8f9";
def const TOKEN as string init "0123456789abcdef0123456789abcdef";

/**
 * A running fake Jellyfin server.
 *
 * @field srv {httpd.Server} the server
 * @field base {string} its base URL
 * @field t {task of list of string} the task serving it; its result is every request seen
 */
def struct Fake {
    srv as httpd.Server,
    base as string,
    t as task of list of string
};

/**
 * Mark a call that should have thrown.
 *
 * @param what {string} what got through
 * @throws {Error} always, kind "missed"
 */
func missed(what as string) {
    throw Error{kind: "missed", message: $what};
}

/**
 * Start a fake Jellyfin server. An answer is looked up by `METHOD path?query`,
 * then `METHOD path`; it is the status, a newline, header lines `Name: value`,
 * an empty line and the body; `BASE` in it becomes the server's base URL. A
 * request with no answer gets 404 and an OperationOutcome.
 *
 * @param answers {map of string to string} the answers
 * @return {Fake} the server
 */
func startFake(answers as map of string to string) {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    def base as string init "http://" + httpd.address($srv);
    def t as task of list of string init spawn {
        return serveFake($srv, $answers, $base);
    };
    return Fake{srv: $srv, base: $base, t: $t};
}

/**
 * Serve requests until the server shuts down.
 *
 * @param srv {httpd.Server} the server
 * @param answers {map of string to string} the answers
 * @param base {string} the base URL
 * @return {list of string} each request as `METHOD path?query|header=value|...|body`
 */
func serveFake(srv as httpd.Server, answers as map of string to string, base as string) {
    def seen as list of string init [];
    while (true) {
        def req as httpd.Request;
        try {
            $req = httpd.accept($srv);
        } catch (e) {
            return $seen;
        }
        def target as string init httpd.path($req);
        if (httpd.rawQuery($req) != "") {
            $target = $target + "?" + httpd.rawQuery($req);
        }
        def key as string init httpd.method($req) + " " + $target;
        def line as list of string init [$key];
        for (def h in ["Content-Type", "Authorization"]) {
            if (httpd.header($req, $h) != "") {
                $line[] = $h + "=" + httpd.header($req, $h);
            }
        }
        $line[] = convert.stringFromBytes("utf-8", httpd.body($req));
        $seen[] = strings.join($line, "|");
        def spec as string init "404\n\n" +
            '{"title":"Not Found","detail":"no answer for ' + $key + '"}';
        if (maps.has($answers, $key)) {
            $spec = $answers[$key];
        } elseif (maps.has($answers, httpd.method($req) + " " + httpd.path($req))) {
            $spec = $answers[httpd.method($req) + " " + httpd.path($req)];
        }
        $spec = strings.replace($spec, "BASE", $base);
        def split as int init strings.indexOf($spec, "\n\n");
        def head as list of string init strings.split($spec[..$split], "\n");
        for (def h in $head[1..]) {
            def at as int init strings.indexOf($h, ": ");
            httpd.setHeader($req, $h[..$at], $h[$at + 2..]);
        }
        if ($head[0] == "SLEEP") {
            time.sleep(time.fromMilliseconds(3000));
            httpd.respond($req, 200, '{}');
        } else {
            httpd.respond($req, convert.toInt($head[0]), $spec[$split + 2..]);
        }
    }
}

/**
 * Stop a fake and return what it saw.
 *
 * @param f {Fake} the fake
 * @return {list of string} the requests
 */
func stopFake(f as Fake) {
    httpd.shutdown($f.srv);
    return task.wait($f.t);
}

/**
 * A client of a fake.
 *
 * @param f {Fake} the fake
 * @return {Client} the client, signed in as USER with the token TOKEN
 */
func fakeClient(f as Fake) {
    return withUser(withToken(client($f.base), TOKEN), USER);
}

func testClientUrlsAndSettings() {
    def c as Client init client("https://media.example.org/");
    testing.assertEqual($c.baseUrl, "https://media.example.org");
    testing.assertTrue(regex.matches('^[0-9a-f]{32}$', $c.deviceId));
    testing.assertTrue(client("https://media.example.org").deviceId != $c.deviceId);
    for (def bad in ["ftp://x", "https://x/?a=1", "media.example.org", "https://x/#f"]) {
        try {
            client($bad);
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "a base URL is");
        }
    }
    try {
        client("http://nas.local:8096");
        missed("plain http to the LAN");
    } catch (e) {
        testing.assertContains($e.message, "in clear: use https, or withPlainHttp");
    }
    def lan as Client init client("https://nas.local:8096");
    $lan.baseUrl = "http://nas.local:8096";
    checkUrl(withPlainHttp($lan));
    testing.assertEqual(withTimeout($c, 5000).timeoutMs, 5000);
    testing.assertEqual(withMaxBytes($c, 65536).maxBytes, 65536);
    testing.assertTrue(withTls($c, http.TlsOptions{skipVerify: true}).tls.skipVerify);
    for (def bad in ["short", "has space here", "quote\"inside"]) {
        try {
            withToken($c, $bad);
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "a token is");
        }
    }
    try {
        withUser($c, "alice");
        missed("a name as user id");
    } catch (e) {
        testing.assertContains($e.message, "a user id is a GUID");
    }
}

func testTheAuthorizationHeader() {
    def c as Client init withDevice(
        client("https://m.example.org"),
        "Media Sync",
        "backup-host",
        "dev-0001");
    testing.assertEqual(
        authorization($c),
        "MediaBrowser Client=\"Media Sync\", Device=\"backup-host\", DeviceId=\"dev-0001\", Version=\"" +
            VERSION + "\"");
    testing.assertEqual(
        authorization(withToken($c, TOKEN)),
        "MediaBrowser Client=\"Media Sync\", Device=\"backup-host\", DeviceId=\"dev-0001\", Version=\"" +
            VERSION + "\", Token=\"" + TOKEN + "\"");
    for (def bad in [["a\"b", "d", "dev-0001"], ["a", "d,e", "dev-0001"], ["a", "d", "x"]]) {
        try {
            withDevice($c, $bad[0], $bad[1], $bad[2]);
            missed($bad[0] + $bad[1] + $bad[2]);
        } catch (e) {
            testing.assertEqual($e.kind, "jellyfin");
        }
    }
}

func testLoginLogoutAndErrors() {
    def f as Fake init startFake({
        "POST /Users/AuthenticateByName": "200\n\n" +
            '{"User":{"Id":"' + USER + '","Name":"alice"},"AccessToken":"' + TOKEN +
            '","ServerId":"s"}',
        "POST /Sessions/Logout": "204\n\n",
        "GET /Users/Me": "401\n\n",
        "GET /Items/" + ITEM: "403\n\n" +
            '{"title":"Forbidden","detail":"user may not see it (HTTP 200)"}'
    });
    def c as Client init login(client($f.base), "alice", "s3cret");
    testing.assertEqual($c.token, TOKEN);
    testing.assertEqual($c.userId, USER);
    try {
        me($c);
        missed("a 401");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "jellyfin: me: not signed in, or the token is no longer valid (HTTP 401)");
        testing.assertEqual($e.kind, "jellyfin.http");
        testing.assertEqual($e.status, 401);
    }
    try {
        item($c, ITEM);
        missed("a 403");
    } catch (e) {
        testing.assertEqual($e.kind, "jellyfin.http");
        testing.assertEqual($e.status, 403);
        testing.assertContains($e.message, "the user may not do this: user may not see it");
    }
    $c = logout($c);
    testing.assertEqual($c.token, "");
    try {
        logout($c);
        missed("logout twice");
    } catch (e) {
        testing.assertContains($e.message, "not signed in");
    }
    try {
        login($c, "", "x");
        missed("no user name");
    } catch (e) {
        testing.assertContains($e.message, "the user name is empty");
    }
    def seen as list of string init stopFake($f);
    testing.assertContains($seen[0], '{"Username":"alice","Pw":"s3cret"}');
    testing.assertFalse(strings.contains($seen[0], "Token="));
    testing.assertContains($seen[1], "Token=\"" + TOKEN + "\"");
}

func testCallAndDeadlines() {
    def f as Fake init startFake({
        "GET /Items/" + ITEM + "/Similar?limit=5": "200\n\n" + '{"Items":[],"TotalRecordCount":0}',
        "GET /Persons/slow": "SLEEP\n\n",
        "GET /Persons/big": "200\n\n" + '{"x":"' + strings.repeat("y", 70000) + '"}',
        "GET /Persons/html": "200\n\n<html>"
    });
    def c as Client init fakeClient($f);
    testing.assertEqual(
        json.asInt(
            call($c, "GET", "/Items/" + ITEM + "/Similar", ["limit=5"], json.decode("null")),
            "/TotalRecordCount"),
        0);
    try {
        call(withMaxBytes($c, 65536), "GET", "/Persons/big", [], json.decode("null"));
        missed("a big response");
    } catch (e) {
        testing.assertContains($e.message, "the response is over 65536 bytes");
    }
    try {
        call($c, "GET", "/Persons/html", [], json.decode("null"));
        missed("not JSON");
    } catch (e) {
        testing.assertContains($e.message, "the response is not JSON");
    }
    def started as time.Time init time.now();
    try {
        call(withTimeout($c, 1000), "GET", "/Persons/slow", [], json.decode("null"));
        missed("a slow server");
    } catch (e) {
        testing.assertEqual($e.message, "jellyfin: GET /Persons/slow: no answer within 1000 ms");
    }
    testing.assertTrue(time.milliseconds(time.sub(time.now(), $started)) < 2500);
    for (def bad in [
        ["GET", "Items"],
        ["GET", "/Items/../System"],
        ["TRACE", "/Items"],
        ["GET", "/a b"]
    ]) {
        try {
            call($c, $bad[0], $bad[1], [], json.decode("null"));
            missed($bad[1]);
        } catch (e) {
            testing.assertEqual($e.kind, "jellyfin");
        }
    }
    for (def bad in ["limit", "=5", "a b=1"]) {
        try {
            queryOf([$bad]);
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "a query parameter is name=value");
        }
    }
    testing.assertEqual(
        queryOf(["searchTerm=Star Wars & co"]),
        "?searchTerm=Star%20Wars%20%26%20co");
    stopFake($f);
    try {
        serverInfo(client("http://127.0.0.1:1"));
        missed("nobody listening");
    } catch (e) {
        testing.assertContains($e.message, "cannot reach");
    }
}

func testARefusedLoginSaysSo() {
    def f as Fake init startFake({
        "POST /Users/AuthenticateByName": "401\n\n" +
            '{"title":"Unauthorized","detail":"Error processing request."}'
    });
    try {
        login(client($f.base), "alice", "wrong");
        missed("a wrong password");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "jellyfin: login \"alice\": the server refused the user name or password (HTTP 401)");
        testing.assertEqual($e.kind, "jellyfin.http");
        testing.assertEqual($e.status, 401);
        testing.assertEqual(len($e.fields), 0);
    }
    testing.assertEqual(len(stopFake($f)), 1);
}

func testAReasonIsNotRepeated() {
    def r as http.BytesResponse init http.BytesResponse{
        status: 404,
        statusText: "Not Found",
        headers: {},
        body: convert.bytesFromString("utf-8", '{"title":"Not Found"}')
    };
    try {
        checkStatus($r, "item x");
        missed("a 404");
    } catch (e) {
        testing.assertEqual($e.message, "jellyfin: item x: Not Found (HTTP 404)");
    }
}

func testTamperedClientsAndMalformedLogins() {
    def f as Fake init startFake({
        "POST /Users/AuthenticateByName": "200\n\n" +
            '{"User":{"Id":"../x?y"},"AccessToken":"tok\", Client=\"evil"}',
        "GET /Items": "400\n\n" +
            '{"title":"One or more validation errors occurred.","errors":{"limit":["The value is not valid."]}}'
    });
    try {
        login(client($f.base), "alice", "x");
        missed("a malformed token");
    } catch (e) {
        testing.assertContains($e.message, "a malformed token or user id");
    }
    def c as Client init fakeClient($f);
    try {
        items($c, ["limit=x"]);
        missed("a 400");
    } catch (e) {
        testing.assertContains($e.message, "(limit: The value is not valid.)");
        testing.assertEqual($e.status, 400);
        testing.assertEqual($e.fields, {"limit": "The value is not valid."});
    }
    def far as Client init $c;
    $far.baseUrl = "http://198.51.100.7:8096";
    def forged as Client init $c;
    $forged.token = "abcdefgh\", Client=\"evil";
    def other as Client init $c;
    $other.userId = "../x";
    for (def bad in [$far, $forged, $other]) {
        try {
            call($bad, "GET", "/System/Info", [], json.decode("null"));
            missed("a tampered client");
        } catch (e) {
            testing.assertEqual($e.kind, "jellyfin");
        }
    }
    def seen as list of string init stopFake($f);
    testing.assertEqual(len($seen), 2);
    for (def bad in [
        "https://x:0",
        "https://x:99999",
        "https://-",
        "https://..",
        "https://x/%zz",
        "https://x/a/../b"
    ]) {
        try {
            client($bad);
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "a base URL is");
        }
    }
    def hidden as string init "a" + convert.fromCodepoint(8232) + "b" +
        convert.fromCodepoint(8203) + "c" + convert.fromCodepoint(65279);
    testing.assertEqual(cleaned($hidden, 100), "a?b?c?");
    try {
        withDevice(client("https://m.example.org"), "C++ Sync", "host", "dev-00001");
        missed("a + in a name");
    } catch (e) {
        testing.assertContains($e.message, "client and device names are");
    }
}
