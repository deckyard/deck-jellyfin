# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# jellyfin - white-box tests for the admin topic. Spliced into
# jellyfin_test.j via include.

func testServerInfo() {
    def f as Fake init startFake({
        "GET /System/Info/Public": "200\n\n" +
            '{"ServerName":"den","Version":"10.11.2","Id":"abc","ProductName":"Jellyfin Server","StartupWizardCompleted":true}'
    });
    def s as ServerInfo init serverInfo(client($f.base));
    testing.assertEqual($s.name + " " + $s.version, "den 10.11.2");
    testing.assertTrue($s.wizardCompleted);
    stopFake($f);
    for (def body in ['{"ServerName":"x","Version":"9.2.0","Id":"a"}', '{"hello":"world"}']) {
        def g as Fake init startFake({"GET /System/Info/Public": "200\n\n" + $body});
        try {
            serverInfo(client($g.base));
            missed($body);
        } catch (e) {
            testing.assertEqual($e.kind, "jellyfin");
        }
        stopFake($g);
    }
}

func testUsersTasksAndSessions() {
    def f as Fake init startFake({
        "GET /Users/Me": "200\n\n" + '{"Id":"' + USER +
            '","Name":"alice","HasPassword":true,"Policy":{"IsAdministrator":true,"IsDisabled":false}}',
        "GET /Users": "200\n\n" + '[{"Id":"' + USER + '","Name":"alice"},{"Id":"' + ITEM +
            '","Name":"bob","Policy":{"IsDisabled":true}}]',
        "POST /Library/Refresh": "204\n\n",
        "GET /ScheduledTasks": "200\n\n" + '[{"Id":"' + ITEM +
            '","Name":"Scan Media Library","Category":"Library","State":"Idle","LastExecutionResult":{"Status":"Completed"}}]',
        "POST /ScheduledTasks/Running/" + ITEM: "204\n\n",
        "GET /Sessions": "200\n\n" +
            '[{"Id":"s1","UserName":"alice","Client":"Jellyfin Web","DeviceName":"Firefox","SupportsRemoteControl":true,"NowPlayingItem":' +
            EPISODE +
            ',"PlayState":{"IsPaused":true,"PositionTicks":1200000000}},{"Id":"s2","Client":"Jennifer"}]',
        "POST /Sessions/s1/Message": "204\n\n",
        "POST /Sessions/s1/Playing/Unpause": "204\n\n"
    });
    def c as Client init fakeClient($f);
    def u as User init me($c);
    testing.assertTrue($u.isAdministrator);
    testing.assertEqual(len(users($c)), 2);
    testing.assertTrue(users($c)[1].isDisabled);
    refreshLibrary($c);
    def t as list of Task init tasks($c);
    testing.assertEqual($t[0].name + " " + $t[0].lastResult, "Scan Media Library Completed");
    runTask($c, $t[0].id);
    def s as list of Session init sessions($c);
    testing.assertEqual($s[0].nowPlaying[0].name, "Pilot");
    testing.assertTrue($s[0].paused);
    testing.assertEqual($s[0].positionSeconds, 120);
    testing.assertEqual(len($s[1].nowPlaying), 0);
    sendMessage($c, "s1", "Note", "Dinner is ready", 5000);
    playstate($c, "s1", "Unpause");
    for (def bad in ["Play", "pause"]) {
        try {
            playstate($c, "s1", $bad);
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "a playback command is one of");
        }
    }
    try {
        sendMessage($c, "../x", "h", "t", 0);
        missed("a bad session id");
    } catch (e) {
        testing.assertContains($e.message, "a session id is");
    }
    def seen as list of string init stopFake($f);
    def msg as string init "";
    for (def r in $seen) {
        if (strings.startsWith($r, "POST /Sessions/s1/Message")) {
            $msg = $r;
        }
    }
    testing.assertContains($msg, '{"Header":"Note","Text":"Dinner is ready","TimeoutMs":5000}');
}

func testMalformedServerAnswersAreRefused() {
    def f as Fake init startFake({
        "GET /System/Info/Public": "200\n\n" +
            '{"ServerName":"x","Version":"99999999999999999999.1","Id":"a"}',
        "GET /Sessions": "200\n\n" + '[{"Client":"no id"},5]',
        "GET /ScheduledTasks": "200\n\n" + '[7]'
    });
    def c as Client init fakeClient($f);
    try {
        serverInfo($c);
        missed("a huge version");
    } catch (e) {
        testing.assertEqual($e.kind, "jellyfin");
    }
    try {
        sessions($c);
        missed("a session without an id");
    } catch (e) {
        testing.assertContains($e.message, "without a valid Id");
    }
    try {
        tasks($c);
        missed("a task that is a number");
    } catch (e) {
        testing.assertContains($e.message, "without a valid Id");
    }
    stopFake($f);
}
