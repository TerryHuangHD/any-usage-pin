import 'dart:convert';
import 'dart:io';

import 'package:any_usage_pin/core.dart';
import 'package:flutter_test/flutter_test.dart';

final _observed = DateTime.utc(2026, 10, 3, 8);

Map<String, dynamic> _limit({
  String id = 'five-hour',
  String window = '5h',
  String unit = 'percent',
  double? used = 25,
  double? remaining = 75,
  double? maximum = 100,
  double? usedFraction,
  double? remainingFraction,
  bool shared = false,
  String? group,
  DateTime? resetsAt,
  int? durationMs = 18000000,
  Map<String, dynamic> scope = const {},
}) => {
  'id': id,
  'label': id,
  'scope': {
    'provider': 'anthropic',
    'windowId': window,
    'shared': shared,
    'sharedGroup': ?group,
    ...scope,
  },
  'window': {
    'id': window,
    'durationMs': ?durationMs,
    'resetsAt': ?resetsAt?.millisecondsSinceEpoch,
  },
  'amount': {
    'unit': unit,
    'used': ?used,
    'remaining': ?remaining,
    'limit': ?maximum,
    'usedFraction': ?usedFraction,
    'remainingFraction': ?remainingFraction,
  },
  'status': 'ok',
};

Map<String, dynamic> _report({
  String provider = 'anthropic',
  String? email = 'member@example.invalid',
  String? account = 'member',
  String? org = 'work',
  String? project,
  List<Map<String, dynamic>>? limits,
  DateTime? fetchedAt,
}) => {
  'provider': provider,
  'fetchedAt': (fetchedAt ?? _observed).millisecondsSinceEpoch,
  'limits': limits ?? [_limit()],
  'metadata': {
    'email': ?email,
    'accountId': ?account,
    'orgId': ?org,
    'projectId': ?project,
  },
};

UsageSnapshot _snapshot(
  List<Map<String, dynamic>> reports, {
  List<Map<String, dynamic>> missing = const [],
  List<Map<String, dynamic>> disabled = const [],
}) => UsageSnapshot.fromOmpJson({
  'generatedAt': _observed.millisecondsSinceEpoch,
  'reports': reports,
  'accountsWithoutUsage': missing,
  'disabledCredentials': disabled,
});

Future<void> _waitUntil(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 5)) {
      throw TestFailure(
        'Subprocess did not reach the expected lifecycle state.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<File> _fixtureExecutable(Directory directory, String body) async {
  final file = File('${directory.path}/fixture-omp');
  await file.writeAsString('#!/bin/sh\n$body\n');
  final permission = await Process.run('/bin/chmod', ['700', file.path]);
  if (permission.exitCode != 0) {
    throw TestFailure('Cannot prepare CLI regression fixture.');
  }
  return file;
}

void main() {
  group('OMP account identity and resource semantics', () {
    test(
      'two Claude members and the same member in two orgs remain independent',
      () {
        final snapshot = _snapshot([
          _report(email: 'one@example.invalid', account: 'one', org: 'org-a'),
          _report(email: 'two@example.invalid', account: 'two', org: 'org-a'),
          _report(email: 'one@example.invalid', account: 'one', org: 'org-b'),
          _report(
            email: 'one@example.invalid',
            account: 'one',
            org: 'org-a',
            project: 'project-a',
          ),
        ]);
        expect(snapshot.accounts, hasLength(4));
        expect(
          snapshot.accounts.map((account) => account.key).toSet(),
          hasLength(4),
        );
        expect(
          snapshot.accounts.every((account) => account.identityKnown),
          isTrue,
        );
        expect(
          snapshot.accounts.map((account) => account.fetchedAt),
          everyElement(_observed),
        );
        expect(snapshot.generatedAt, _observed);
        expect(
          snapshot.accounts.map((account) => account.limits.single.used),
          everyElement(25),
        );
      },
    );

    test('limit scopes split one report into independent projects', () {
      final snapshot = _snapshot([
        _report(
          project: null,
          limits: [
            _limit(id: 'project-one', scope: {'projectId': 'one'}),
            _limit(id: 'project-two', scope: {'projectId': 'two'}),
          ],
        ),
      ]);
      expect(snapshot.accounts, hasLength(2));
      expect(snapshot.accounts.map((account) => account.projectId).toSet(), {
        'one',
        'two',
      });
      expect(
        snapshot.accounts.every((account) => account.limits.length == 1),
        isTrue,
      );
    });

    test(
      'equivalent shared pools collapse, not independent windows or differing values',
      () {
        final snapshot = _snapshot([
          _report(
            limits: [
              _limit(id: 'model-a', shared: true, group: 'pool'),
              _limit(id: 'model-b', shared: true, group: 'pool'),
              _limit(id: 'weekly', window: '7d', shared: true, group: 'pool'),
              _limit(
                id: 'different-reading',
                used: 30,
                remaining: 70,
                shared: true,
                group: 'pool',
              ),
              _limit(id: 'private-meter', shared: false, group: 'pool'),
            ],
          ),
        ]);
        final limits = snapshot.accounts.single.limits;
        expect(limits, hasLength(4));
        expect(
          limits.map((limit) => limit.id),
          containsAll([
            'model-a',
            'weekly',
            'different-reading',
            'private-meter',
          ]),
        );
        expect(limits.first.fraction(LayerMode.used), 0.25);
        expect(limits.first.remaining, 75);
      },
    );

    test(
      'duplicate observations keep independent meters and newest repeated meter',
      () {
        final earlier = _observed.subtract(const Duration(minutes: 10));
        final snapshot = _snapshot([
          _report(
            fetchedAt: earlier,
            limits: [
              _limit(),
              _limit(id: 'weekly', window: '7d'),
            ],
          ),
          _report(limits: [_limit(used: 40, remaining: 60)]),
        ]);
        final account = snapshot.accounts.single;
        expect(account.fetchedAt, earlier);
        expect(account.limits, hasLength(2));
        expect(
          account.limits.firstWhere((limit) => limit.id == 'five-hour').used,
          40,
        );
        expect(
          account.limits
              .firstWhere((limit) => limit.id == 'five-hour')
              .fetchedAt,
          _observed,
        );
        expect(
          account.limits.firstWhere((limit) => limit.id == 'weekly').remaining,
          75,
        );
      },
    );

    test('out-of-order reports cannot replace a fresher retained meter', () {
      final earlier = _observed.subtract(const Duration(minutes: 10));
      final middle = _observed.subtract(const Duration(minutes: 5));
      final account = _snapshot([
        _report(
          fetchedAt: earlier,
          limits: [
            _limit(),
            _limit(id: 'weekly', window: '7d'),
          ],
        ),
        _report(limits: [_limit(used: 40, remaining: 60)]),
        _report(fetchedAt: middle, limits: [_limit(used: 30, remaining: 70)]),
      ]).accounts.single;
      expect(account.fetchedAt, earlier);
      final latest = account.limits.firstWhere(
        (limit) => limit.id == 'five-hour',
      );
      expect(latest.used, 40);
      expect(latest.fetchedAt, _observed);
      final restored = UsageAccount.fromJson(account.toJson());
      expect(restored.limits.first.fetchedAt, _observed);
    });

    test(
      'replacing all older meters advances the retained observation time',
      () {
        final earlier = _observed.subtract(const Duration(minutes: 10));
        final account = _snapshot([
          _report(fetchedAt: earlier),
          _report(limits: [_limit(used: 40, remaining: 60)]),
        ]).accounts.single;
        expect(account.fetchedAt, _observed);
        expect(account.limits.single.used, 40);
      },
    );

    test(
      'missing and disabled identities stay visible without exposing disable cause',
      () {
        const secret = 'SECRET_RAW_PROVIDER_ERROR';
        final disabledAt = _observed.subtract(const Duration(days: 2));
        final snapshot = _snapshot(
          [],
          missing: [
            {
              'provider': 'anthropic',
              'type': 'oauth',
              'email': 'missing@example.invalid',
              'orgId': 'missing-org',
            },
          ],
          disabled: [
            {
              'provider': 'anthropic',
              'type': 'oauth',
              'email': 'disabled@example.invalid',
              'accountId': 'disabled-member',
              'orgId': 'disabled-org',
              'id': 7,
              'cause': secret,
              'disabledAtMs': disabledAt.millisecondsSinceEpoch,
            },
          ],
        );
        expect(snapshot.accounts, hasLength(2));
        expect(snapshot.accounts.first.disabled, isFalse);
        expect(snapshot.accounts.first.issue, isNotNull);
        expect(snapshot.accounts.first.limits, isEmpty);
        expect(snapshot.accounts.last.disabled, isTrue);
        expect(snapshot.accounts.last.fetchedAt, disabledAt);
        expect(snapshot.accounts.last.identityKnown, isTrue);
        expect(jsonEncode(snapshot.toJson()), isNot(contains(secret)));
      },
    );

    test('a disabled tombstone cannot erase a currently working account', () {
      final snapshot = _snapshot(
        [_report()],
        disabled: [
          {
            'provider': 'anthropic',
            'email': 'member@example.invalid',
            'accountId': 'member',
            'orgId': 'work',
            'cause': 'expired',
          },
        ],
      );
      expect(snapshot.accounts, hasLength(2));
      expect(snapshot.accounts.first.disabled, isFalse);
      expect(snapshot.accounts.first.limits, isNotEmpty);
      expect(snapshot.accounts.last.disabled, isTrue);
      expect(snapshot.accounts.first.key, isNot(snapshot.accounts.last.key));
    });

    test(
      'unattributed reports are distinguishable but not durably pinnable',
      () {
        final snapshot = _snapshot([
          _report(email: null, account: null, org: null),
          _report(email: null, account: null, org: null),
        ]);
        expect(snapshot.accounts, hasLength(2));
        expect(
          snapshot.accounts.map((account) => account.key).toSet(),
          hasLength(2),
        );
        expect(
          snapshot.accounts.every((account) => !account.identityKnown),
          isTrue,
        );
        expect(
          snapshot.accounts.every((account) => account.issue != null),
          isTrue,
        );
      },
    );

    test(
      'workspace IDs alone cannot merge unidentified people or create durable pins',
      () {
        final snapshot = _snapshot([
          _report(
            email: null,
            account: null,
            org: 'shared-workspace',
            project: 'shared-project',
          ),
          _report(
            email: null,
            account: null,
            org: 'shared-workspace',
            project: 'shared-project',
          ),
        ]);
        expect(snapshot.accounts, hasLength(2));
        expect(snapshot.accounts.map((a) => a.key).toSet(), hasLength(2));
        expect(snapshot.accounts.every((a) => !a.identityKnown), isTrue);
      },
    );

    test('raw payload and arbitrary metadata never enter normalized cache', () {
      const secret = 'SECRET_TOKEN_SENTINEL';
      final report = _report();
      (report['metadata'] as Map<String, dynamic>)['accessToken'] = secret;
      report['raw'] = {'authorization': secret};
      report['notes'] = [secret];
      final serialized = jsonEncode(_snapshot([report]).toJson());
      expect(serialized, isNot(contains(secret)));
      expect(serialized, isNot(contains('accessToken')));
      expect(serialized, contains('member@example.invalid'));
    });
  });

  group('quota units and reset boundaries', () {
    test(
      'money retains its unit while fractions remain available for a quota bar',
      () {
        final limit = _snapshot([
          _report(
            limits: [
              _limit(unit: 'usd', used: 2.5, remaining: 7.5, maximum: 10),
            ],
          ),
        ]).accounts.single.limits.single;
        expect(limit.used, 2.5);
        expect(limit.unit, 'usd');
        expect(limit.fraction(LayerMode.used), 0.25);
        expect(limit.valueText(LayerMode.remaining, _observed), '7.5 USD');
        expect(
          limit.valueText(LayerMode.remaining, _observed, raw: true),
          '7.5 USD',
        );
        expect(
          limit.valueText(LayerMode.used, _observed, raw: true),
          '2.5 USD',
        );
      },
    );

    test('tiny real balances remain nonzero in raw-unit display', () {
      final limit = _snapshot([
        _report(
          limits: [
            _limit(unit: 'usd', used: 0.004, remaining: 9.996, maximum: 10),
          ],
        ),
      ]).accounts.single.limits.single;
      expect(
        limit.valueText(LayerMode.used, _observed, raw: true),
        '0.004 USD',
      );
      expect(limit.valueText(LayerMode.used, _observed), '0.004 USD');
      expect(limit.used, 0.004);
    });

    test('percent-unit absolute amounts do not get multiplied twice', () {
      final limit = _snapshot([
        _report(limits: [_limit(used: 25, remaining: null, maximum: null)]),
      ]).accounts.single.limits.single;
      expect(limit.fraction(LayerMode.used), 0.25);
      expect(limit.fraction(LayerMode.remaining), 0.75);
      expect(limit.valueText(LayerMode.used, _observed, raw: true), '25%');
      expect(limit.valueText(LayerMode.remaining, _observed), '75%');
    });

    test('a fraction alone cannot manufacture a raw token count', () {
      final limit = _snapshot([
        _report(
          limits: [
            _limit(
              unit: 'tokens',
              used: null,
              remaining: null,
              maximum: null,
              remainingFraction: 0.4,
            ),
          ],
        ),
      ]).accounts.single.limits.single;
      expect(limit.fraction(LayerMode.used), closeTo(0.6, 0.000001));
      final text = limit.valueText(LayerMode.remaining, _observed);
      expect(text, contains('40%'));
      expect(text, contains('tokens'));
      expect(
        RegExp(
          r'\d',
        ).hasMatch(limit.valueText(LayerMode.remaining, _observed, raw: true)),
        isFalse,
      );
      expect(limit.remaining, isNull);
    });

    test('missing amounts and a zero denominator do not become fake quota', () {
      final snapshot = _snapshot([
        _report(
          limits: [
            _limit(id: 'missing', used: null, remaining: null, maximum: null),
            _limit(
              id: 'zero',
              unit: 'requests',
              used: null,
              remaining: null,
              maximum: 0,
            ),
          ],
        ),
      ]);
      for (final limit in snapshot.accounts.single.limits) {
        expect(limit.fraction(LayerMode.remaining), isNull);
        expect(limit.barFraction(LayerMode.remaining, _observed), isNull);
        expect(
          RegExp(
            r'\d',
          ).hasMatch(limit.valueText(LayerMode.remaining, _observed)),
          isFalse,
        );
      }
    });

    test(
      'explicit overage is preserved and remaining capacity stops at zero',
      () {
        final limit = _snapshot([
          _report(
            limits: [
              _limit(
                unit: 'requests',
                used: 120,
                remaining: null,
                maximum: 100,
              ),
            ],
          ),
        ]).accounts.single.limits.single;
        expect(limit.fraction(LayerMode.used), 1.2);
        expect(limit.barFraction(LayerMode.used, _observed), 1.2);
        expect(limit.barFraction(LayerMode.remaining, _observed), 0);
        expect(limit.fraction(LayerMode.remaining), 0);
        expect(limit.valueText(LayerMode.used, _observed), '120 requests');
        expect(
          limit.valueText(LayerMode.remaining, _observed, raw: true),
          '0 requests',
        );
      },
    );

    test(
      'reset state crosses its deadline without minting a fresh allowance',
      () {
        final missing = _snapshot([_report()]).accounts.single.limits.single;
        final limit = _snapshot([
          _report(
            limits: [
              _limit(resetsAt: _observed.add(const Duration(seconds: 61))),
            ],
          ),
        ]).accounts.single.limits.single;
        expect(missing.resetState(_observed), ResetState.unknown);
        expect(limit.resetState(_observed), ResetState.upcoming);
        expect(
          limit.resetState(
            limit.resetsAt!.subtract(const Duration(milliseconds: 1)),
          ),
          ResetState.upcoming,
        );
        expect(limit.resetState(limit.resetsAt!), ResetState.due);
        expect(
          limit.resetState(limit.resetsAt!.add(const Duration(days: 1))),
          ResetState.due,
        );
        expect(
          limit.valueText(
            LayerMode.remaining,
            limit.resetsAt!.add(const Duration(days: 1)),
          ),
          limit.valueText(LayerMode.remaining, _observed),
        );
      },
    );

    test(
      'reset bars use the reported duration and clamp at both boundaries',
      () {
        final reset = _observed.add(const Duration(milliseconds: 400));
        final limit = _snapshot([
          _report(limits: [_limit(resetsAt: reset, durationMs: 1600)]),
        ]).accounts.single.limits.single;
        expect(limit.barFraction(LayerMode.reset, _observed), 0.25);
        expect(
          limit.barFraction(
            LayerMode.reset,
            reset.subtract(const Duration(milliseconds: 1)),
          ),
          1 / 1600,
        );
        expect(
          limit.barFraction(
            LayerMode.reset,
            reset.subtract(const Duration(seconds: 4)),
          ),
          1,
        );
        expect(limit.barFraction(LayerMode.reset, reset), 0);
        expect(
          limit.barFraction(
            LayerMode.reset,
            reset.add(const Duration(days: 1)),
          ),
          0,
        );
        expect(limit.valueText(LayerMode.reset, reset), '待更新');
        expect(limit.remaining, 75);
      },
    );

    test('reset bars never infer a missing or nonpositive source duration', () {
      final reset = _observed.add(const Duration(hours: 5));
      final limits = _snapshot([
        _report(
          limits: [
            _limit(id: 'missing', resetsAt: reset, durationMs: null),
            _limit(id: 'zero', resetsAt: reset, durationMs: 0),
            _limit(id: 'negative', resetsAt: reset, durationMs: -1),
            _limit(id: 'no-reset'),
          ],
        ),
      ]).accounts.single.limits;
      for (final limit in limits) {
        expect(limit.barFraction(LayerMode.reset, _observed), isNull);
        expect(
          limit.barFraction(
            LayerMode.reset,
            reset.add(const Duration(days: 1)),
          ),
          isNull,
        );
      }
      expect(limits.first.duration, isNull);
      expect(limits.last.duration, const Duration(hours: 5));
      final negativeDuration = UsageLimit(
        id: 'negative-duration',
        label: 'Negative duration',
        resetsAt: reset,
        duration: const Duration(milliseconds: -1),
      );
      expect(negativeDuration.barFraction(LayerMode.reset, _observed), isNull);
    });

    test('invalid optional numbers and reset timestamps remain missing', () {
      final invalid = _limit(used: null, remaining: null, maximum: null);
      invalid['amount'] = {
        'unit': 'percent',
        'used': 'unknown',
        'remainingFraction': -0.5,
      };
      invalid['window'] = {
        'id': '5h',
        'resetsAt': 'tomorrow',
        'durationMs': 'five hours',
      };
      final limit = _snapshot([
        _report(limits: [invalid]),
      ]).accounts.single.limits.single;
      expect(limit.used, isNull);
      expect(limit.remainingFraction, isNull);
      expect(limit.duration, isNull);
      expect(
        RegExp(r'\d').hasMatch(limit.valueText(LayerMode.used, _observed)),
        isFalse,
      );
      expect(limit.resetState(_observed), ResetState.unknown);
    });

    test(
      'unknown schema is rejected instead of appearing as an empty or zero report',
      () {
        expect(
          () => UsageSnapshot.fromOmpJson({'reports': []}),
          throwsA(isA<Exception>()),
        );
        expect(
          () => UsageSnapshot.fromOmpJson({
            'generatedAt': _observed.millisecondsSinceEpoch,
            'reports': {},
          }),
          throwsA(isA<Exception>()),
        );
        expect(
          () => UsageSnapshot.fromOmpJson({
            'generatedAt': _observed.toIso8601String(),
            'reports': [],
          }),
          throwsA(isA<Exception>()),
        );
        final partial = _snapshot([
          {
            'provider': 'anthropic',
            'metadata': {'email': 'partial@example.invalid'},
          },
        ]);
        expect(partial.accounts.single.limits, isEmpty);
        expect(partial.accounts.single.issue, isNotNull);
      },
    );
  });

  group('OMP subprocess failure lifecycle', () {
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('usage-cli-test-');
    });
    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test(
      'cancellation kills the actual child rather than leaving a stuck fetch',
      () async {
        final executable = await _fixtureExecutable(
          directory,
          'printf "%s" "\$\$" > "\$0.pid"\nexec /bin/sleep 120',
        );
        final adapter = OmpAdapter(executable: executable.path);
        final operation = adapter.fetch();
        final completion = expectLater(
          operation,
          throwsA(
            predicate<Object>((error) => error.toString().contains('已取消')),
          ),
        );
        try {
          final marker = File('${executable.path}.pid');
          await _waitUntil(marker.existsSync);
          final childPid = int.parse(await marker.readAsString());
          adapter.cancel();
          await completion.timeout(const Duration(seconds: 5));
          await _waitUntil(
            () => !Process.killPid(childPid, ProcessSignal.sigcont),
          );
        } finally {
          adapter.cancel();
        }
      },
      skip: !(Platform.isMacOS || Platform.isLinux),
    );

    test(
      'provider stderr is not exposed through a user-facing error',
      () async {
        const secret = 'SECRET_STDERR_TEST_SENTINEL';
        final executable = await _fixtureExecutable(
          directory,
          'printf "$secret" >&2\nexit 1',
        );
        final adapter = OmpAdapter(executable: executable.path);
        try {
          await expectLater(
            adapter.fetch(),
            throwsA(
              predicate<Object>((error) {
                final message = error.toString();
                return message.contains('查詢失敗') && !message.contains(secret);
              }),
            ),
          ).timeout(const Duration(seconds: 5));
        } finally {
          adapter.cancel();
        }
      },
      skip: !(Platform.isMacOS || Platform.isLinux),
    );

    test(
      'unbounded stdout aborts the CLI instead of exhausting memory',
      () async {
        final executable = await _fixtureExecutable(
          directory,
          'exec /usr/bin/yes OVERFLOW_TEST',
        );
        final adapter = OmpAdapter(executable: executable.path);
        try {
          await expectLater(
            adapter.fetch(),
            throwsA(
              predicate<Object>((error) => error.toString().contains('安全大小上限')),
            ),
          ).timeout(const Duration(seconds: 5));
        } finally {
          adapter.cancel();
        }
      },
      skip: !(Platform.isMacOS || Platform.isLinux),
    );
  });

  group('private persisted consumer state', () {
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('usage-core-test-');
    });
    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test(
      'v1 pin styles migrate in memory without losing consumer settings',
      () async {
        final legacy = {
          'schemaVersion': 1,
          'selectedAgent': 'alternate-agent',
          'ompPath': '/custom/bin/omp',
          'dense': true,
          'rawValues': true,
          'layout': 'focus',
          'theme': 'light',
          'pins': [
            {
              'id': 'text',
              'accountKey': 'account-one',
              'label': 'Text label',
              'color': '#abcdef',
              'style': 'text',
              'top': {'limitId': 'five-hour', 'mode': 'remaining'},
              'bottom': {'limitId': 'weekly', 'mode': 'reset'},
              'labelWidth': 6,
              'showIcon': false,
            },
            {
              'id': 'bars-quota',
              'accountKey': 'account-one',
              'label': 'Quota label',
              'color': 'auto',
              'style': 'bars',
              'top': {'limitId': 'five-hour', 'mode': 'remaining'},
              'bottom': {'limitId': 'weekly', 'mode': 'used'},
              'labelWidth': 0,
              'showIcon': true,
            },
            {
              'id': 'bars-reset',
              'accountKey': 'account-two',
              'label': 'Reset label',
              'color': '#445566',
              'style': 'bars',
              'top': {'limitId': 'five-hour', 'mode': 'used'},
              'bottom': {'limitId': 'weekly', 'mode': 'reset'},
              'labelWidth': 4,
              'showIcon': false,
            },
            {
              'id': 'icon',
              'accountKey': 'account-two',
              'label': 'Previously hidden label',
              'color': '#998877',
              'style': 'icon',
              'top': {'limitId': 'five-hour', 'mode': 'remaining'},
              'bottom': {'limitId': 'weekly', 'mode': 'reset'},
              'labelWidth': 8,
              'showIcon': false,
            },
          ],
          'accountPreferences': {
            'account-one': {
              'alias': 'Work',
              'hiddenLimitIds': ['extra', 'retired-window'],
            },
            'account-two': {
              'alias': 'Personal',
              'hiddenLimitIds': ['daily'],
            },
          },
          'accountOrder': ['account-two', 'account-one'],
        };
        final file = File('${directory.path}/preferences.json');
        final original = jsonEncode(legacy);
        await file.writeAsString(original);
        final storage = AppStorage(directory: directory);
        final migrated = await storage.loadPreferences();
        expect(await file.readAsString(), original);
        final converted = migrated.toJson();
        for (final field in [
          'selectedAgent',
          'ompPath',
          'dense',
          'rawValues',
          'layout',
          'theme',
          'accountPreferences',
          'accountOrder',
        ]) {
          expect(converted[field], legacy[field], reason: field);
        }
        final oldPins = legacy['pins'] as List;
        final newPins = converted['pins'] as List;
        for (var index = 0; index < oldPins.length; index++) {
          final oldPin = oldPins[index] as Map;
          final newPin = newPins[index] as Map;
          for (final field in ['id', 'accountKey', 'label', 'color']) {
            expect(
              newPin[field],
              oldPin[field],
              reason: '${oldPin['id']} $field',
            );
          }
          expect(newPin.containsKey('style'), isFalse);
          if (oldPin['style'] != 'icon') {
            expect(newPin['labelWidth'], oldPin['labelWidth']);
            expect(newPin['showIcon'], oldPin['showIcon']);
          }
        }
        final text = migrated.pins[0];
        expect(text.top!.text!.limitId, 'five-hour');
        expect(text.top!.text!.mode, LayerMode.remaining);
        expect(text.top!.bar, isNull);
        expect(text.bottom!.text!.limitId, 'weekly');
        expect(text.bottom!.text!.mode, LayerMode.reset);
        expect(text.bottom!.bar, isNull);
        final quota = migrated.pins[1];
        expect(quota.top!.text!.toJson(), {
          'limitId': 'five-hour',
          'mode': 'remaining',
        });
        expect(quota.top!.bar!.toJson(), quota.top!.text!.toJson());
        expect(quota.bottom!.text!.toJson(), {
          'limitId': 'weekly',
          'mode': 'used',
        });
        expect(quota.bottom!.bar!.toJson(), quota.bottom!.text!.toJson());
        final reset = migrated.pins[2];
        expect(reset.top!.bar!.toJson(), reset.top!.text!.toJson());
        expect(reset.bottom!.text!.limitId, 'weekly');
        expect(reset.bottom!.text!.mode, LayerMode.reset);
        expect(reset.bottom!.bar, isNull);
        final icon = migrated.pins[3];
        expect(icon.top, isNull);
        expect(icon.bottom, isNull);
        expect(icon.label, 'Previously hidden label');
        expect(icon.labelWidth, 0);
        expect(icon.showIcon, isTrue);

        await storage.savePreferences(migrated);
        final saved = jsonDecode(await file.readAsString()) as Map;
        expect(saved['schemaVersion'], 2);
        expect(saved, converted);
        final reloaded = await AppStorage(
          directory: directory,
        ).loadPreferences();
        expect(reloaded.toJson(), converted);
      },
    );

    test(
      'queued edits survive relaunch with independent per-pin layers and ordering',
      () async {
        final accounts = _snapshot([
          _report(account: 'one', email: 'one@example.invalid'),
          _report(account: 'two', email: 'two@example.invalid'),
        ]).accounts;
        final first = Preferences(
          pins: [
            PinPreference(
              id: 'pin-one',
              accountKey: accounts.first.key,
              label: 'Work',
              top: const PinLayer(
                text: PinMetric(
                  limitId: 'five-hour',
                  mode: LayerMode.remaining,
                ),
                bar: PinMetric(limitId: 'weekly', mode: LayerMode.used),
              ),
              bottom: const PinLayer(
                text: PinMetric(limitId: 'weekly', mode: LayerMode.reset),
              ),
            ),
            PinPreference(
              id: 'pin-two',
              accountKey: accounts.last.key,
              label: 'Personal',
              color: '#123456',
              labelWidth: 4,
              showIcon: false,
              top: const PinLayer(
                bar: PinMetric(limitId: 'weekly', mode: LayerMode.used),
              ),
            ),
          ],
          accountPreferences: {
            accounts.first.key: AccountPreference(
              alias: 'Work account',
              hiddenLimitIds: ['extra'],
            ),
          },
          accountOrder: [accounts.last.key, accounts.first.key],
        );
        final edited = first.copyWith(
          pins: [
            first.pins.last,
            PinPreference(
              id: 'pin-one',
              accountKey: accounts.first.key,
              label: 'Work',
              top: first.pins.first.top,
              bottom: const PinLayer(
                bar: PinMetric(limitId: 'five-hour', mode: LayerMode.reset),
              ),
            ),
          ],
          rawValues: true,
          theme: ThemeChoice.dark,
          layout: PanelLayout.table,
        );
        final storage = AppStorage(directory: directory);
        final firstSave = storage.savePreferences(first);
        final laterSave = storage.savePreferences(edited);
        await Future.wait([firstSave, laterSave]);
        final restored = await AppStorage(
          directory: directory,
        ).loadPreferences();
        expect(restored.pins.map((pin) => pin.id), ['pin-two', 'pin-one']);
        expect(restored.pins.first.accountKey, accounts.last.key);
        expect(restored.pins.first.top!.text, isNull);
        expect(restored.pins.first.top!.bar!.limitId, 'weekly');
        expect(restored.pins.first.top!.bar!.mode, LayerMode.used);
        expect(restored.pins.first.bottom, isNull);
        expect(restored.pins.first.color, '#123456');
        expect(restored.pins.first.showIcon, isFalse);
        expect(restored.pins.last.top!.text!.limitId, 'five-hour');
        expect(restored.pins.last.top!.text!.mode, LayerMode.remaining);
        expect(restored.pins.last.top!.bar!.limitId, 'weekly');
        expect(restored.pins.last.top!.bar!.mode, LayerMode.used);
        expect(restored.pins.last.bottom!.text, isNull);
        expect(restored.pins.last.bottom!.bar!.limitId, 'five-hour');
        expect(restored.pins.last.bottom!.bar!.mode, LayerMode.reset);
        expect(
          restored.accountPreferences[accounts.first.key]!.hiddenLimitIds,
          ['extra'],
        );
        expect(
          restored.accountPreferences[accounts.first.key]!.alias,
          'Work account',
        );
        expect(restored.accountOrder, [accounts.last.key, accounts.first.key]);
        expect(restored.rawValues, isTrue);
        expect(restored.theme, ThemeChoice.dark);
        expect(restored.layout, PanelLayout.table);
        final temporaryFiles = await directory
            .list()
            .where((entry) => entry.path.endsWith('.tmp'))
            .toList();
        expect(temporaryFiles, isEmpty);
        if (Platform.isMacOS || Platform.isLinux) {
          expect((await directory.stat()).mode & 0x1ff, 0x1c0);
          expect(
            (await File('${directory.path}/preferences.json').stat()).mode &
                0x1ff,
            0x180,
          );
        }
      },
    );

    test(
      'cached timestamps and expired resets survive without fabricated freshness',
      () async {
        final old = _observed.subtract(const Duration(days: 10));
        final snapshot = _snapshot([
          _report(
            fetchedAt: old,
            limits: [_limit(resetsAt: old.add(const Duration(hours: 5)))],
          ),
        ]);
        final storage = AppStorage(directory: directory);
        await storage.saveSnapshot('omp', snapshot);
        final saved =
            jsonDecode(
                  await File(
                    '${directory.path}/snapshot-omp.json',
                  ).readAsString(),
                )
                as Map;
        expect(saved['schemaVersion'], 1);
        final restored = (await AppStorage(
          directory: directory,
        ).loadSnapshot('omp'))!;
        expect(restored.generatedAt, _observed);
        expect(restored.accounts.single.fetchedAt, old);
        expect(
          restored.accounts.single.limits.single.resetState(_observed),
          ResetState.due,
        );
        expect(restored.accounts.single.limits.single.remaining, 75);
      },
    );

    test(
      'corrupt preferences remain visible and are not overwritten by a subsequent save',
      () async {
        final file = File('${directory.path}/preferences.json');
        const original = '{invalid json';
        await file.writeAsString(original);
        final storage = AppStorage(directory: directory);
        await expectLater(storage.loadPreferences(), throwsA(isA<Exception>()));
        await expectLater(
          storage.savePreferences(Preferences()),
          throwsA(isA<Exception>()),
        );
        expect(await file.readAsString(), original);
        // Also protect corruption when a caller attempts to save before loading.
        await expectLater(
          AppStorage(directory: directory).savePreferences(Preferences()),
          throwsA(isA<Exception>()),
        );
        expect(await file.readAsString(), original);
      },
    );

    test(
      'explicit reset preserves the damaged file and permits subsequent edits',
      () async {
        final file = File('${directory.path}/preferences.json');
        const original = '{damaged preferences';
        await file.writeAsString(original);
        final storage = AppStorage(directory: directory);
        await expectLater(storage.loadPreferences(), throwsA(isA<Exception>()));
        await storage.resetPreferences(Preferences());
        await storage.savePreferences(
          Preferences(
            pins: [const PinPreference(id: 'chosen', accountKey: 'account')],
          ),
        );
        final restored = await AppStorage(
          directory: directory,
        ).loadPreferences();
        expect(restored.pins.single.id, 'chosen');
        final backup = await directory
            .list()
            .where((entry) => entry.path.contains('preferences.backup-'))
            .single;
        expect(await File(backup.path).readAsString(), original);
      },
    );

    test(
      'unsupported preference versions are preserved rather than reset',
      () async {
        final file = File('${directory.path}/preferences.json');
        for (final version in [0, 3, 99]) {
          final json = Preferences().toJson()..['schemaVersion'] = version;
          final original = jsonEncode(json);
          await file.writeAsString(original);
          final storage = AppStorage(directory: directory);
          await expectLater(
            storage.loadPreferences(),
            throwsA(isA<Exception>()),
          );
          await expectLater(
            storage.savePreferences(Preferences()),
            throwsA(isA<Exception>()),
          );
          expect(await file.readAsString(), original);
        }
      },
    );

    test('unknown cache version and unsafe agent paths are rejected', () async {
      await File('${directory.path}/snapshot-omp.json').writeAsString(
        jsonEncode({
          'schemaVersion': 2,
          'generatedAt': _observed.toIso8601String(),
          'accounts': [],
        }),
      );
      final storage = AppStorage(directory: directory);
      await expectLater(storage.loadSnapshot('omp'), throwsA(isA<Exception>()));
      await expectLater(
        storage.loadSnapshot('../outside'),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        storage.saveSnapshot('../outside', _snapshot([])),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'structurally corrupt preferences cannot silently discard pin configuration',
      () async {
        final json = Preferences(
          pins: [
            const PinPreference(
              id: 'pin',
              accountKey: 'known',
              top: PinLayer(
                text: PinMetric(limitId: 'weekly', mode: LayerMode.reset),
              ),
            ),
          ],
        ).toJson();
        ((json['pins'] as List).first as Map<String, dynamic>)['top'] = {
          'text': {'limitId': 'weekly', 'mode': 'future-mode'},
        };
        final file = File('${directory.path}/preferences.json');
        final original = jsonEncode(json);
        await file.writeAsString(original);
        final storage = AppStorage(directory: directory);
        await expectLater(storage.loadPreferences(), throwsA(isA<Exception>()));
        await expectLater(
          storage.savePreferences(Preferences()),
          throwsA(isA<Exception>()),
        );
        expect(await file.readAsString(), original);
      },
    );
  });
}
