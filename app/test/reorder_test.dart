import 'package:campaign_sms/data/models.dart';
import 'package:campaign_sms/ui/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// The batch list on Home is a *filter* of the real list, so a drag from
/// position 2 to position 0 on screen is almost never a move from 2 to 0
/// underneath. These pin down the mapping, which is where this kind of feature
/// goes wrong quietly: the list looks right until the tab is switched.
void main() {
  Batch batch(int id, {String status = BatchStatus.pending}) => Batch(
    id: id,
    name: 'Batch $id',
    size: 100,
    status: status,
    position: id,
    createdAt: 0,
    completedAt: null,
    total: 100,
    remaining: 100,
    sent: 0,
    replied: 0,
    failed: 0,
  );

  final all = [batch(1), batch(2), batch(3), batch(4), batch(5)];

  test('an unfiltered drag moves the batch to where it was dropped', () {
    expect(reorderedIds(all: all, shown: all, from: 3, to: 0), [4, 1, 2, 3, 5]);
    expect(reorderedIds(all: all, shown: all, from: 0, to: 4), [2, 3, 4, 5, 1]);
    expect(reorderedIds(all: all, shown: all, from: 2, to: 2), [1, 2, 3, 4, 5]);
  });

  test('a drag in a filtered list moves it past the batches it can see', () {
    // Tab showing only 2 and 4. Dragging 4 above 2 has to put it above 2 in
    // the full list, not merely one place up.
    final shown = [all[1], all[3]];
    expect(reorderedIds(all: all, shown: shown, from: 1, to: 0), [
      1,
      4,
      2,
      3,
      5,
    ]);

    // And the other way: 2 dropped after 4 lands directly after it.
    expect(reorderedIds(all: all, shown: shown, from: 0, to: 1), [
      1,
      3,
      4,
      2,
      5,
    ]);
  });

  test('a single visible batch has nowhere to go', () {
    // Nothing to drop it against, so the drag says nothing about where it
    // belongs among the batches the filter is hiding. Refused rather than
    // guessed — guessing here sent it to the back of the list.
    expect(reorderedIds(all: all, shown: [all[2]], from: 0, to: 0), isNull);
  });

  test('nonsense indices are refused rather than throwing', () {
    expect(reorderedIds(all: all, shown: all, from: -1, to: 0), isNull);
    expect(reorderedIds(all: all, shown: all, from: 9, to: 0), isNull);
    expect(reorderedIds(all: all, shown: all, from: 0, to: -1), isNull);
  });
}
