# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# jellyfin - core: the client and its settings, the MediaBrowser
# authorization header, signing in and out, the HTTP exchange with its
# deadline, errors, and `call`. Spliced into jellyfin.j via include.

/** How long one request may take, in milliseconds: 30 seconds. */
export def const DEFAULT_TIMEOUT_MS as int init 30000;

/** The largest response read, in bytes: 16 MiB. */
export def const DEFAULT_MAX_BYTES as int init 16777216;

/** The oldest Jellyfin major version `serverInfo` accepts. */
export def const MIN_MAJOR as int init 10;

# what an error message never shows: control characters and the bidi controls
# that reorder a terminal line
def const UNSHOWN as string init '[\x00-\x1f\x7f-\x9f\x{061c}\x{200b}-\x{200f}\x{2028}-\x{202e}\x{2060}-\x{2069}\x{feff}]';

# an item, user or session id: a GUID, plain or with dashes
def const GUID as string init '^([0-9A-Fa-f]{32}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})$';

# a query parameter name
def const PARAM as string init '^[A-Za-z][A-Za-z0-9]*$';

# what a client or device name may hold in the authorization header
def const LABEL as string init '^[A-Za-z0-9 ._()-]{1,64}$';

# a token or API key: letters, digits and characters URL decoding leaves alone
def const TOKEN_FORM as string init '^[A-Za-z0-9._~-]{8,512}$';

# the hosts plain http is allowed to without `withPlainHttp`
def const LOOPBACK as list of string init ["127.0.0.1", "localhost", "[::1]"];

/**
 * How to reach a Jellyfin server and who is asking. Build it with `client`,
 * sign in with `login` or `withToken`, change it with the `with*`
 * functions.
 *
 * @field baseUrl {string} the server's URL without a trailing slash, such as `https://media.example.org`
 * @field token {string} the access token or API key, `""` before signing in
 * @field userId {string} the user the per-user calls are for, `""` when not set
 * @field clientName {string} the client name the server shows, `Jennifer` by default
 * @field deviceName {string} the device name the server shows
 * @field deviceId {string} the device id; the server keeps one session per device
 * @field tls {http.TlsOptions} certificate checks for an `https` URL
 * @field allowPlainHttp {bool} whether plain `http` to another machine is allowed (the password and token then cross the network in clear)
 * @field timeoutMs {int} how long one request may take
 * @field maxBytes {int} the largest response read
 */
export def struct Client {
    baseUrl as string,
    token as string,
    userId as string,
    clientName as string,
    deviceName as string,
    deviceId as string,
    tls as http.TlsOptions,
    allowPlainHttp as bool,
    timeoutMs as int,
    maxBytes as int
};

/**
 * Throw a jellyfin error.
 *
 * @param message {string} what went wrong, without the `jellyfin: ` prefix
 * @throws {Error} kind "jellyfin", always
 */
func fail(message as string) {
    throw Error{kind: "jellyfin", message: "jellyfin: " + $message};
}

/**
 * A request the server refused: its status is not 2xx.
 *
 * @field kind {string} always "jellyfin.http"
 * @field message {string} `jellyfin: <request>: <why> (HTTP nnn)`
 * @field status {int} the HTTP status, such as 401 or 404
 * @field fields {map of string to string} the validation errors of an ASP.NET answer, field -> its first message; empty when it has none
 */
export def struct HttpError {
    kind as string,
    message as string,
    status as int,
    fields as map of string to string
};

/**
 * Throw the HttpError of a refused request.
 *
 * @param what {string} the request, for the message
 * @param why {string} the explanation
 * @param status {int} the HTTP status
 * @param fields {map of string to string} the validation errors
 * @throws {HttpError} kind "jellyfin.http", always
 */
func failHttp(what as string, why as string, status as int, fields as map of string to string) {
    throw HttpError{
        kind: "jellyfin.http",
        message: io.sprintf("jellyfin: %s: %s (HTTP %d)", $what, cleaned($why, 500), $status),
        status: $status,
        fields: $fields
    };
}

/**
 * Server-controlled text made safe for a message: control and bidi
 * characters as `?`, at most a number of characters.
 *
 * @param s {string} the text
 * @param most {int} the most characters kept
 * @return {string} the text
 */
func cleaned(s as string, most as int) {
    def text as string init $s;
    if (len($text) > $most) {
        $text = $text[..$most] + "...";
    }
    return regex.replace(UNSHOWN, $text, "?");
}

/**
 * Text quoted for an error message.
 *
 * @param s {string} the text
 * @return {string} the text in double quotes, cleaned and cut at 200 characters
 */
func shown(s as string) {
    return "\"" + cleaned($s, 200) + "\"";
}

/**
 * Refuse an int outside a range.
 *
 * @param value {int} the value
 * @param low {int} the smallest allowed
 * @param high {int} the largest allowed
 * @param what {string} what the value is
 */
func checkRange(value as int, low as int, high as int, what as string) {
    if ($value < $low or $value > $high) {
        fail(io.sprintf("%s must be %d to %d, got %d", $what, $low, $high, $value));
    }
}

/**
 * Refuse an id that is not a GUID.
 *
 * @param id {string} the id
 * @param what {string} what it is
 */
func checkId(id as string, what as string) {
    if (not regex.matches(GUID, $id)) {
        fail($what + " is a GUID (32 hex digits), got " + shown($id));
    }
}

/**
 * A client for a Jellyfin server, not signed in. Plain `http` is refused
 * except to this machine: add `withPlainHttp` for a server on the LAN. Each
 * client gets a random device id; give a stable one with `withDevice` so
 * the server does not collect a session per run.
 *
 * @param baseUrl {string} the server's URL, such as `https://media.example.org` or `http://localhost:8096`
 * @return {Client} the client
 * @throws {Error} kind "jellyfin" when the URL is not an absolute http(s) URL without query or fragment, or plain http to another machine
 * @example
 *   def c as jellyfin.Client init jellyfin.client("https://media.example.org");
 */
export func client(baseUrl as string) {
    def base as string init $baseUrl;
    while (strings.endsWith($base, "/")) {
        $base = $base[..len($base) - 1];
    }
    def c as Client init Client{
        baseUrl: $base,
        token: "",
        userId: "",
        clientName: "Jennifer",
        deviceName: "jennifer",
        deviceId: strings.replace(uuid.v4(), "-", ""),
        tls: http.TlsOptions{},
        allowPlainHttp: false,
        timeoutMs: DEFAULT_TIMEOUT_MS,
        maxBytes: DEFAULT_MAX_BYTES
    };
    checkUrl($c);
    return $c;
}

/**
 * Refuse a base URL that is not absolute http(s), has a query or fragment,
 * or is plain http to another machine without `allowPlainHttp`.
 *
 * @param c {Client} the client
 */
func checkUrl(c as Client) {
    def m as regex.Match init regex.find(
        '^(https?)://(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*)(:([0-9]{1,5}))?(/[A-Za-z0-9._~-]+)*/?$',
        $c.baseUrl);
    if ($m.start < 0 or regex.matches('/\.+(/|$)', $c.baseUrl) or
        ($m.groups[6] != "" and
        (convert.toInt($m.groups[6]) < 1 or convert.toInt($m.groups[6]) > 65535))) {
        fail("a base URL is http(s)://host[:port][/path], port 1 to 65535, the path plain segments, got " +
            shown($c.baseUrl));
    }
    if ($m.groups[0] == "http" and not $c.allowPlainHttp and
        not lists.contains(LOOPBACK, strings.lower($m.groups[1]))) {
        fail("plain http to " + shown($m.groups[1]) +
            " would send the password and token in clear: use https, or withPlainHttp");
    }
}

/**
 * The client allowed to use plain `http` to another machine, such as a
 * server on the LAN. The password and token cross the network in clear.
 *
 * @param c {Client} the client
 * @return {Client} the client
 */
export func withPlainHttp(c as Client) {
    $c.allowPlainHttp = true;
    return $c;
}

/**
 * The client signed in with an access token or an API key (Dashboard >
 * API Keys). An API key belongs to no user: add `withUser` for the
 * per-user calls.
 *
 * @param c {Client} the client
 * @param token {string} the token or key
 * @return {Client} the client
 * @example
 *   $c = jellyfin.withUser(jellyfin.withToken($c, $apiKey), $userId);
 */
export func withToken(c as Client, token as string) {
    if (not regex.matches(TOKEN_FORM, $token)) {
        fail("a token is 8 to 512 letters, digits and ._~-");
    }
    $c.token = $token;
    return $c;
}

/**
 * The client acting for a user in the per-user calls (libraries, items,
 * played and favourite marks, resume, next up).
 *
 * @param c {Client} the client
 * @param userId {string} the user's id
 * @return {Client} the client
 */
export func withUser(c as Client, userId as string) {
    checkId($userId, "a user id");
    $c.userId = $userId;
    return $c;
}

/**
 * The client with the names and id it shows to the server: the session
 * list, the devices page, and "sign out of all devices" go by them. Keep
 * the device id stable across runs.
 *
 * @param c {Client} the client
 * @param clientName {string} the application, such as `Media Sync`
 * @param deviceName {string} the machine, such as `backup-host`
 * @param deviceId {string} a stable id: letters, digits and `-`, 8 to 64
 * @return {Client} the client
 */
export func withDevice(
    c as Client,
    clientName as string,
    deviceName as string,
    deviceId as string) {
    if (not regex.matches(LABEL, $clientName) or not regex.matches(LABEL, $deviceName)) {
        fail("client and device names are 1 to 64 letters, digits, spaces and ._()+-");
    }
    if (not regex.matches('^[A-Za-z0-9-]{8,64}$', $deviceId)) {
        fail("a device id is 8 to 64 letters, digits and -, got " + shown($deviceId));
    }
    $c.clientName = $clientName;
    $c.deviceName = $deviceName;
    $c.deviceId = $deviceId;
    return $c;
}

/**
 * The client with certificate options for `https`.
 *
 * @param c {Client} the client
 * @param tls {http.TlsOptions} the options (`caCert`, `skipVerify`)
 * @return {Client} the client
 */
export func withTls(c as Client, tls as http.TlsOptions) {
    $c.tls = $tls;
    return $c;
}

/**
 * The client with another deadline for each request.
 *
 * @param c {Client} the client
 * @param ms {int} 1000 to 86400000 milliseconds
 * @return {Client} the client
 */
export func withTimeout(c as Client, ms as int) {
    checkRange($ms, 1000, 86400000, "the timeout");
    $c.timeoutMs = $ms;
    return $c;
}

/**
 * The client with another response cap.
 *
 * @param c {Client} the client
 * @param most {int} 65536 to 268435456 bytes
 * @return {Client} the client
 */
export func withMaxBytes(c as Client, most as int) {
    checkRange($most, 65536, 268435456, "the largest response");
    $c.maxBytes = $most;
    return $c;
}

/**
 * The `Authorization` header Jellyfin reads: client, device, version and,
 * once signed in, the token.
 *
 * @param c {Client} the client
 * @return {string} `MediaBrowser Client="...", Device="...", DeviceId="...", Version="...", Token="..."`
 */
func authorization(c as Client) {
    if (not regex.matches(LABEL, $c.clientName) or not regex.matches(LABEL, $c.deviceName) or
        not regex.matches('^[A-Za-z0-9-]{8,64}$', $c.deviceId) or
        ($c.token != "" and not regex.matches(TOKEN_FORM, $c.token))) {
        fail("the client's names, device id or token were changed to something the header cannot carry");
    }
    def h as string init "MediaBrowser Client=\"" + $c.clientName + "\", Device=\"" +
        $c.deviceName +
        "\", DeviceId=\"" + $c.deviceId + "\", Version=\"" + VERSION + "\"";
    if ($c.token != "") {
        $h = $h + ", Token=\"" + $c.token + "\"";
    }
    return $h;
}

/**
 * A query string from `name=value` parameters, each value percent-encoded.
 *
 * @param query {list of string} the parameters, such as `includeItemTypes=Movie`
 * @return {string} `?a=b&c=d`, or `""` without parameters
 */
func queryOf(query as list of string) {
    if (len($query) == 0) {
        return "";
    }
    def parts as list of string init [];
    for (def q in $query) {
        def at as int init strings.indexOf($q, "=");
        if ($at < 1 or not regex.matches(PARAM, $q[..$at])) {
            fail("a query parameter is name=value with a name such as includeItemTypes, got " +
                shown($q));
        }
        $parts[] = $q[..$at] + "=" + uri.encode($q[$at + 1..]);
    }
    return "?" + strings.join($parts, "&");
}

/**
 * Send one request within the deadline.
 *
 * @param c {Client} the client
 * @param method {string} the HTTP method
 * @param path {string} the path and query below the base URL, starting with `/`
 * @param body {string} a JSON body, `""` for none
 * @param what {string} the request, for messages
 * @return {http.BytesResponse} the response, any status
 */
func exchange(c as Client, method as string, path as string, body as string, what as string) {
    checkUrl($c);
    if ($c.userId != "") {
        checkId($c.userId, "the client's user id");
    }
    def headers as map of string to string init {
        "Authorization": authorization($c),
        "Accept": "application/json"
    };
    if ($body != "") {
        $headers["Content-Type"] = "application/json";
    }
    def url as string init $c.baseUrl + $path;
    def timeoutMs as int init $c.timeoutMs;
    def maxBytes as int init $c.maxBytes;
    def tls as http.TlsOptions init $c.tls;
    def t as task of http.BytesResponse init spawn {
        return http.requestWithBytes($method, $url, $headers, $body, $timeoutMs, $maxBytes, $tls);
    };
    try {
        return task.waitTimeout($t, $timeoutMs);
    } catch (e) {
        if ($e.message == "task cancelled") {
            task.cancel($t);
            task.discard($t);
            throw $e;
        }
        if ($e.kind == "timeout") {
            task.cancel($t);
            task.discard($t);
            fail(io.sprintf("%s: no answer within %d ms", $what, $timeoutMs));
        }
        if (strings.startsWith($e.message, "http: ") and strings.contains($e.message, " exceed")) {
            fail(io.sprintf("%s: the response is over %d bytes", $what, $maxBytes));
        }
        fail($what + ": cannot reach " + shown($c.baseUrl) + ": " + cleaned($e.message, 300));
    }
}

/**
 * Send a request and read the JSON response, failing on a status that is
 * not 2xx.
 *
 * @param c {Client} the client
 * @param method {string} the HTTP method
 * @param path {string} the path and query
 * @param body {string} a JSON body, `""` for none
 * @param what {string} the request, for messages
 * @return {json.Value} the response, JSON `null` when it has no body
 */
func request(c as Client, method as string, path as string, body as string, what as string) {
    def r as http.BytesResponse init exchange($c, $method, $path, $body, $what);
    checkStatus($r, $what);
    return jsonBody($r, $what);
}

/**
 * A response body as JSON.
 *
 * @param r {http.BytesResponse} the response
 * @param what {string} the request, for messages
 * @return {json.Value} the body, JSON `null` when empty
 */
func jsonBody(r as http.BytesResponse, what as string) {
    def text as string init "";
    try {
        $text = convert.stringFromBytes("utf-8", $r.body);
    } catch (e) {
        fail($what + ": the response is not UTF-8");
    }
    if (strings.trim($text) == "") {
        return json.decode("null");
    }
    try {
        return json.decode($text);
    } catch (e) {
        fail($what + ": the response is not JSON: " + shown($text));
    }
}

/**
 * Fail on a status that is not 2xx, with the server's explanation.
 *
 * @param r {http.BytesResponse} the response
 * @param what {string} the request, for messages
 */
func checkStatus(r as http.BytesResponse, what as string) {
    if ($r.status >= 200 and $r.status <= 299) {
        return null;
    }
    def why as string init $r.statusText;
    if ($r.status == 401) {
        $why = "not signed in, or the token is no longer valid";
    } elseif ($r.status == 403) {
        $why = "the user may not do this";
    }
    def detail as string init "";
    def fields as map of string to string init {};
    try {
        def text as string init strings.trim(convert.stringFromBytes("utf-8", $r.body));
        if ($text != "" and not strings.startsWith($text, "<")) {
            $detail = $text;
            def v as json.Value init json.decode($text);
            if (json.typeOf($v, "/title") == "string") {
                $detail = json.asString($v, "/title");
            }
            if (json.typeOf($v, "/detail") == "string") {
                $detail = json.asString($v, "/detail");
            }
            $fields = fieldErrors($v);
            $detail = $detail + fieldText($fields);
        }
    } catch (e) {
        $detail = $detail;
    }
    if ($detail != "" and $detail != $why) {
        $why = $why + ": " + $detail;
    }
    failHttp($what, $why, $r.status, $fields);
}

/**
 * The field errors of an ASP.NET validation answer (`errors`: field ->
 * messages), each field with its first message.
 *
 * @param v {json.Value} the answer
 * @return {map of string to string} field -> its first message (`""` when it has none); empty when the answer has no errors
 */
func fieldErrors(v as json.Value) {
    def fields as map of string to string init {};
    if (json.typeOf($v, "/errors") != "map") {
        return $fields;
    }
    for (def k in json.keys($v, "/errors")) {
        def ptr as string init "/errors/" +
            strings.replace(strings.replace($k, "~", "~0"), "/", "~1");
        $fields[$k] = "";
        if (json.typeOf($v, $ptr + "/0") == "string") {
            $fields[$k] = json.asString($v, $ptr + "/0");
        }
    }
    return $fields;
}

/**
 * Field errors for a message.
 *
 * @param fields {map of string to string} field -> its first message
 * @return {string} ` (field: message; ...)`, or `""` when there are none
 */
func fieldText(fields as map of string to string) {
    if (len($fields) == 0) {
        return "";
    }
    def parts as list of string init [];
    for (def k in $fields) {
        if ($fields[$k] == "") {
            $parts[] = $k;
        } else {
            $parts[] = $k + ": " + $fields[$k];
        }
    }
    return " (" + strings.join($parts, "; ") + ")";
}

/**
 * Sign in with a user name and password. The client then carries the
 * access token and acts for that user.
 *
 * @param c {Client} the client
 * @param username {string} the user name
 * @param password {string} the password, `""` for a user without one
 * @return {Client} the signed-in client
 * @throws {HttpError} kind "jellyfin.http" when the server refuses the name or password (status 401) or another status is not 2xx
 * @throws {Error} kind "jellyfin" when the server cannot be reached or answers malformed
 * @example
 *   $c = jellyfin.login($c, "alice", os.getEnv("JELLYFIN_PASSWORD"));
 */
export func login(c as Client, username as string, password as string) {
    if ($username == "") {
        fail("login: the user name is empty");
    }
    $c.token = "";
    def body as json.Value init json.map({"Username": $username, "Pw": $password});
    def what as string init "login " + shown($username);
    def r as http.BytesResponse init exchange(
        $c,
        "POST",
        "/Users/AuthenticateByName",
        json.encode($body),
        $what);
    if ($r.status == 401) {
        failHttp($what, "the server refused the user name or password", 401, {});
    }
    checkStatus($r, $what);
    def v as json.Value init jsonBody($r, $what);
    if (json.typeOf($v, "/AccessToken") != "string" or json.typeOf($v, "/User/Id") != "string") {
        fail("login: the server returned no access token");
    }
    def token as string init json.asString($v, "/AccessToken");
    def user as string init json.asString($v, "/User/Id");
    if (not regex.matches(TOKEN_FORM, $token) or not regex.matches(GUID, $user)) {
        fail("login: the server returned a malformed token or user id");
    }
    $c.token = $token;
    $c.userId = $user;
    return $c;
}

/**
 * Sign out: the server ends this device's session and its access token stops
 * working. An API key is no session: the server answers, and the key keeps
 * working; revoke a key on the dashboard.
 *
 * @param c {Client} the signed-in client
 * @return {Client} the client without its token
 */
export func logout(c as Client) {
    if ($c.token == "") {
        fail("logout: not signed in");
    }
    request($c, "POST", "/Sessions/Logout", "", "logout");
    $c.token = "";
    return $c;
}

/**
 * Any other request to the server.
 *
 * @param c {Client} the client
 * @param method {string} `GET`, `POST`, `PUT`, `PATCH`, `DELETE` or `HEAD`
 * @param path {string} the path below the base URL, such as `/Persons` or `/Items/<id>/Similar`
 * @param query {list of string} parameters as `name=value`
 * @param body {json.Value} the body, JSON `null` for none
 * @return {json.Value} the response, JSON `null` when it has no body
 * @throws {HttpError} kind "jellyfin.http" when the status is not 2xx
 * @throws {Error} kind "jellyfin" when the method or path is malformed, or the request fails
 * @example
 *   def similar as json.Value init jellyfin.call($c, "GET", "/Items/" + $id + "/Similar", ["limit=5"], json.decode("null"));
 */
export func call(
    c as Client,
    method as string,
    path as string,
    query as list of string,
    body as json.Value) {
    if (not lists.contains(["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"], $method)) {
        fail("a method is GET, POST, PUT, PATCH, DELETE or HEAD, got " + shown($method));
    }
    if (not regex.matches('^(/[A-Za-z0-9_.-]+)+$', $path) or regex.matches('/\.+(/|$)', $path)) {
        fail("a path is /segments of letters, digits and _.-, got " + shown($path));
    }
    def payload as string init "";
    if (json.typeOf($body) != "null") {
        $payload = json.encode($body);
    }
    return request($c, $method, $path + queryOf($query), $payload, $method + " " + $path);
}
