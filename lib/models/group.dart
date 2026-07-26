/// group.dart – Eine Fahrgemeinschaft (Mandant). Eine Gruppe = ein Login.
library;

/// `archived` ist der Ruhezustand für Gruppen, die stillgelegt wurden — er
/// wird heute von nichts gesetzt und ist bewusst schon hier: siehe
/// [Group.fromJson].
enum GroupStatus { pending, active, rejected, archived }

class Group {
  const Group({
    required this.id,
    required this.name,
    required this.handle,
    required this.status,
    required this.isAdmin,
    this.createdAt,
  });

  final String id;
  final String name;
  final String handle;
  final GroupStatus status;
  final bool isAdmin;
  final DateTime? createdAt;

  bool get isActive => status == GroupStatus.active;

  /// Ein Status, den diese Fassung nicht kennt, gilt als [GroupStatus.archived]
  /// — also als „nicht aktiv".
  ///
  /// Das ist keine Vorsichtsmaßnahme auf Vorrat, sondern die Bedingung dafür,
  /// dass der Server je einen neuen Zustand einführen kann: `byName` **wirft**
  /// bei unbekanntem Namen, der Fehler landete in `myGroupProvider`, und die
  /// Nutzerin sähe „Fehler: Invalid argument" statt einer Erklärung. Jede
  /// Stilllegung bräuchte dann erst ein Client-Release — und der Sperr-Schirm
  /// greift bewusst nie, solange es keines gibt. Die sichere Seite ist immer
  /// „kein Zugang": Ein unbekannter Status darf niemals als aktiv durchgehen.
  static GroupStatus statusFrom(String raw) => GroupStatus.values.firstWhere(
    (s) => s.name == raw,
    orElse: () => GroupStatus.archived,
  );

  factory Group.fromJson(Map<String, dynamic> json) => Group(
    id: json['id'] as String,
    name: json['name'] as String,
    handle: json['handle'] as String,
    status: statusFrom(json['status'] as String),
    isAdmin: json['is_admin'] as bool? ?? false,
    createdAt: json['created_at'] == null
        ? null
        : DateTime.parse(json['created_at'] as String),
  );
}
