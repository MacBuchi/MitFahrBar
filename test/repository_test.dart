/// repository_test.dart – Verhalten des Fake-Repositories.
library;

import 'package:mitfahrbar/data/fake_repository.dart';
import 'package:mitfahrbar/models/trip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mehrere Fahrten am selben Tag sind erlaubt (zwei Autos)', () async {
    final repo = FakeCarpoolRepository();
    final date = DateTime(2026, 6, 23);

    await repo.createTrip(date, {'a': ParticipationStatus.driver});
    await repo.createTrip(date, {'b': ParticipationStatus.driver});

    final trips = await repo.loadTrips();
    expect(trips.where((t) => t.date == date), hasLength(2));
  });
}
