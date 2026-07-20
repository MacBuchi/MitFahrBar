/// group.dart – Eine Fahrgemeinschaft (Mandant). Eine Gruppe = ein Login.
library;

enum GroupStatus { pending, active, rejected }

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

  factory Group.fromJson(Map<String, dynamic> json) => Group(
    id: json['id'] as String,
    name: json['name'] as String,
    handle: json['handle'] as String,
    status: GroupStatus.values.byName(json['status'] as String),
    isAdmin: json['is_admin'] as bool? ?? false,
    createdAt: json['created_at'] == null
        ? null
        : DateTime.parse(json['created_at'] as String),
  );
}
