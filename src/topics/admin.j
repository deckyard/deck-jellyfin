# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# jellyfin - admin: the server, users, library scans, scheduled tasks and the
# sessions of clients playing media. Spliced into jellyfin.j via include.

# the playback commands a session takes
def const COMMANDS as list of string init [
    "Stop",
    "Pause",
    "Unpause",
    "PlayPause",
    "NextTrack",
    "PreviousTrack",
    "Rewind",
    "FastForward"
];

/**
 * The server, as anyone may see it before signing in.
 *
 * @field name {string} the server's name
 * @field version {string} its version, such as `10.11.2`
 * @field id {string} its id
 * @field productName {string} `Jellyfin Server`
 * @field operatingSystem {string} the host's operating system, `""` when not told
 * @field wizardCompleted {bool} the first-run wizard is done
 */
export def struct ServerInfo {
    name as string,
    version as string,
    id as string,
    productName as string,
    operatingSystem as string,
    wizardCompleted as bool
};

/**
 * A user account.
 *
 * @field id {string} the user's id
 * @field name {string} the user name
 * @field hasPassword {bool} the account has a password
 * @field isAdministrator {bool} the user may administer the server
 * @field isDisabled {bool} the account is disabled
 * @field lastLogin {string} when the user last signed in, ISO 8601, `""` when never
 */
export def struct User {
    id as string,
    name as string,
    hasPassword as bool,
    isAdministrator as bool,
    isDisabled as bool,
    lastLogin as string
};

/**
 * A scheduled task: library scan, metadata refresh, cleanup, ...
 *
 * @field id {string} the task's id
 * @field key {string} its stable key, such as `RefreshLibrary`; the name is translated, the key is not
 * @field name {string} its name, in the server's language
 * @field category {string} its category
 * @field state {string} `Idle`, `Running` or `Cancelling`
 * @field lastResult {string} how its last run ended: `Completed`, `Failed`, `Cancelled`, `Aborted`, or `""` when it never ran
 */
export def struct Task {
    id as string,
    key as string,
    name as string,
    category as string,
    state as string,
    lastResult as string
};

/**
 * A client connected to the server, and what it plays.
 *
 * @field id {string} the session's id
 * @field userName {string} who is signed in, `""` when nobody
 * @field client {string} the application
 * @field deviceName {string} the device
 * @field nowPlaying {list of Item} what it plays: one item, or nothing
 * @field paused {bool} playback is paused
 * @field positionSeconds {int} the playback position
 * @field remoteControl {bool} it takes commands (`playstate`, `sendMessage`)
 * @field lastActivity {string} when it was last active, ISO 8601
 */
export def struct Session {
    id as string,
    userName as string,
    client as string,
    deviceName as string,
    nowPlaying as list of Item,
    paused as bool,
    positionSeconds as int,
    remoteControl as bool,
    lastActivity as string
};

/**
 * The server's name and version; no sign-in needed.
 *
 * @param c {Client} the client
 * @return {ServerInfo} the server
 * @throws {Error} kind "jellyfin" when the server cannot be reached, is not Jellyfin, or is older than `MIN_MAJOR`
 * @example
 *   def s as jellyfin.ServerInfo init jellyfin.serverInfo($c);
 *   io.printf("%s %s\n", $s.name, $s.version);
 */
export func serverInfo(c as Client) {
    def v as json.Value init request($c, "GET", "/System/Info/Public", "", "serverInfo");
    def s as ServerInfo init ServerInfo{
        name: textAt($v, "/ServerName"),
        version: textAt($v, "/Version"),
        id: textAt($v, "/Id"),
        productName: textAt($v, "/ProductName"),
        operatingSystem: textAt($v, "/OperatingSystem"),
        wizardCompleted: boolAt($v, "/StartupWizardCompleted")
    };
    def m as regex.Match init regex.find('^([0-9]{1,6})\.', $s.version);
    if ($m.start < 0 or $s.id == "") {
        fail("serverInfo: " + shown($c.baseUrl) + " does not answer as a Jellyfin server");
    }
    if (convert.toInt($m.groups[0]) < MIN_MAJOR) {
        fail("serverInfo: Jellyfin " + $s.version + " is older than " + convert.toString(MIN_MAJOR));
    }
    return $s;
}

/**
 * A user from the server's JSON.
 *
 * @param v {json.Value} the user
 * @return {User} the user
 */
func userFrom(v as json.Value) {
    if (textAt($v, "/Id") == "") {
        fail("the server returned a user without an Id");
    }
    return User{
        id: textAt($v, "/Id"),
        name: textAt($v, "/Name"),
        hasPassword: boolAt($v, "/HasPassword"),
        isAdministrator: boolAt($v, "/Policy/IsAdministrator"),
        isDisabled: boolAt($v, "/Policy/IsDisabled"),
        lastLogin: textAt($v, "/LastLoginDate")
    };
}

/**
 * The signed-in user.
 *
 * @param c {Client} the client, signed in with `login` (an API key is no user)
 * @return {User} the user
 */
export func me(c as Client) {
    return userFrom(request($c, "GET", "/Users/Me", "", "me"));
}

/**
 * The user accounts the client may see: every one, for an administrator, an
 * API key, and on a default server any signed-in user.
 *
 * @param c {Client} the client
 * @return {list of User} the users
 */
export func users(c as Client) {
    def v as json.Value init request($c, "GET", "/Users", "", "users");
    if (json.typeOf($v) != "list") {
        fail("users: the server returned no list");
    }
    def out as list of User init [];
    for (def i in 0..json.length($v)) {
        $out[] = userFrom(json.get($v, "/" + convert.toString($i)));
    }
    return $out;
}

/**
 * Scan every library for new, changed and removed files; the server does
 * so in the background.
 *
 * @param c {Client} the client, as an administrator or with an API key
 */
export func refreshLibrary(c as Client) {
    request($c, "POST", "/Library/Refresh", "", "refreshLibrary");
}

/**
 * The scheduled tasks.
 *
 * @param c {Client} the client, as an administrator or with an API key
 * @return {list of Task} the tasks
 */
export func tasks(c as Client) {
    def v as json.Value init request($c, "GET", "/ScheduledTasks", "", "tasks");
    if (json.typeOf($v) != "list") {
        fail("tasks: the server returned no list");
    }
    def out as list of Task init [];
    for (def i in 0..json.length($v)) {
        def at as string init "/" + convert.toString($i);
        if (json.typeOf($v, $at) != "map" or not regex.matches(GUID, textAt($v, $at + "/Id"))) {
            fail("tasks: the server returned a task without a valid Id");
        }
        $out[] = Task{
            id: textAt($v, $at + "/Id"),
            key: textAt($v, $at + "/Key"),
            name: textAt($v, $at + "/Name"),
            category: textAt($v, $at + "/Category"),
            state: textAt($v, $at + "/State"),
            lastResult: textAt($v, $at + "/LastExecutionResult/Status")
        };
    }
    return $out;
}

/**
 * Start a scheduled task now.
 *
 * @param c {Client} the client, as an administrator or with an API key
 * @param id {string} the task's id, from `tasks`
 */
export func runTask(c as Client, id as string) {
    checkId($id, "a task id");
    request($c, "POST", "/ScheduledTasks/Running/" + $id, "", "runTask " + $id);
}

/**
 * The sessions the server knows, recently active ones included, and what
 * each plays.
 *
 * @param c {Client} the client; an administrator sees every session, a user their own
 * @return {list of Session} the sessions
 * @example
 *   for (def s in jellyfin.sessions($c)) {
 *       if (len($s.nowPlaying) > 0) {
 *           io.printf("%s watches %s\n", $s.userName, $s.nowPlaying[0].name);
 *       }
 *   }
 */
export func sessions(c as Client) {
    def v as json.Value init request($c, "GET", "/Sessions", "", "sessions");
    if (json.typeOf($v) != "list") {
        fail("sessions: the server returned no list");
    }
    def out as list of Session init [];
    for (def i in 0..json.length($v)) {
        def at as string init "/" + convert.toString($i);
        if (json.typeOf($v, $at) != "map" or
            not regex.matches('^[A-Za-z0-9-]{1,64}$', textAt($v, $at + "/Id"))) {
            fail("sessions: the server returned a session without a valid Id");
        }
        def playing as list of Item init [];
        if (json.typeOf($v, $at + "/NowPlayingItem") == "map") {
            $playing[] = itemFrom(json.get($v, $at + "/NowPlayingItem"));
        }
        $out[] = Session{
            id: textAt($v, $at + "/Id"),
            userName: textAt($v, $at + "/UserName"),
            client: textAt($v, $at + "/Client"),
            deviceName: textAt($v, $at + "/DeviceName"),
            nowPlaying: $playing,
            paused: boolAt($v, $at + "/PlayState/IsPaused"),
            positionSeconds: intAt($v, $at + "/PlayState/PositionTicks") // TICKS,
            remoteControl: boolAt($v, $at + "/SupportsRemoteControl"),
            lastActivity: textAt($v, $at + "/LastActivityDate")
        };
    }
    return $out;
}

/**
 * Refuse a session id that is not one.
 *
 * @param id {string} the id
 */
func checkSession(id as string) {
    if (not regex.matches('^[A-Za-z0-9-]{1,64}$', $id)) {
        fail("a session id is letters, digits and -, got " + shown($id));
    }
}

/**
 * Show a message on a client's screen.
 *
 * @param c {Client} the client
 * @param sessionId {string} the session, from `sessions`
 * @param header {string} the title
 * @param text {string} the message
 * @param timeoutMs {int} how long it shows, 0 until dismissed
 */
export func sendMessage(
    c as Client,
    sessionId as string,
    header as string,
    text as string,
    timeoutMs as int) {
    checkSession($sessionId);
    if ($text == "") {
        fail("sendMessage: the text is empty");
    }
    checkRange($timeoutMs, 0, 86400000, "the message time");
    def body as json.Value init json.map({"Header": $header, "Text": $text});
    if ($timeoutMs > 0) {
        $body = json.set($body, "/TimeoutMs", $timeoutMs);
    }
    request($c, "POST", "/Sessions/" + $sessionId + "/Message", json.encode($body), "sendMessage");
}

/**
 * Control a client's playback.
 *
 * @param c {Client} the client
 * @param sessionId {string} the session, from `sessions`
 * @param command {string} `Pause`, `Unpause`, `PlayPause`, `Stop`, `NextTrack`, `PreviousTrack`, `Rewind` or `FastForward`
 */
export func playstate(c as Client, sessionId as string, command as string) {
    checkSession($sessionId);
    if (not lists.contains(COMMANDS, $command)) {
        fail("a playback command is one of " + strings.join(COMMANDS, ", ") + ", got " +
            shown($command));
    }
    request(
        $c,
        "POST",
        "/Sessions/" + $sessionId + "/Playing/" + $command,
        "",
        "playstate " + $command);
}
