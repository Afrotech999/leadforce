import 'package:campaign_sms/data/models.dart';
import 'package:campaign_sms/ui/thread_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Message _msg(int at) => Message(
  id: at,
  contactId: 1,
  campaignId: null,
  direction: 'outbound',
  body: 'm$at',
  segments: 1,
  status: 'sent',
  error: null,
  createdAt: at,
  sentAt: at,
  deliveredAt: null,
);

CallEntry _call(int at, {int type = 1, int duration = 60}) =>
    CallEntry(type: type, date: at, durationSeconds: duration);

void main() {
  test('the thread weaves calls between messages in time order', () {
    // Calls arrive newest-first from the log; the weave must not care.
    final items = threadTimeline(
      [_msg(10), _msg(30), _msg(50)],
      [_call(40), _call(20)],
    );
    expect(items.map((i) => i.at), [10, 20, 30, 40, 50]);
    expect(items[1].call, isNotNull);
    expect(items[2].message, isNotNull);
  });

  test('either side can be empty', () {
    expect(threadTimeline([_msg(1)], const []).length, 1);
    expect(threadTimeline(const [], [_call(1)]).single.call, isNotNull);
    expect(threadTimeline(const [], const []), isEmpty);
  });

  test(
    'a call and a message in the same millisecond keep the message first',
    () {
      final items = threadTimeline([_msg(10)], [_call(10)]);
      expect(items.first.message, isNotNull);
      expect(items.last.call, isNotNull);
    },
  );

  test('call entries read like the dialler', () {
    expect(_call(0, type: 2).label, 'Outgoing call');
    expect(_call(0, type: 3).isMissed, isTrue);
    expect(_call(0, type: 5).label, 'Declined call');
    expect(_call(0, duration: 45).length, '45s');
    expect(_call(0, duration: 250).length, '4 min');
    expect(_call(0, duration: 0).length, '');
  });
}
