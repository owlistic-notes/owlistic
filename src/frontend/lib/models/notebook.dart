import 'note.dart';

class Notebook {
  final String id;
  final String name;
  final String description;
  final String userId;
  final List<Note> notes;

  const Notebook({
    required this.id,
    required this.name,
    required this.description,
    required this.userId,
    this.notes = const [],
  });

  factory Notebook.fromJson(Map<String, dynamic> json) {
    return Notebook(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      notes: (json['notes'] as List<dynamic>?)
          ?.map((note) => Note.fromJson(note))
          .toList() ?? const [],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'user_id': userId,
      'notes': notes.map((note) => note.toJson()).toList(),
    };
  }
  
  /// Creates a copy of this notebook with the given fields replaced with the new values
  Notebook copyWith({
    String? id,
    String? name,
    String? description,
    String? userId,
    List<Note>? notes,
  }) {
    return Notebook(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      userId: userId ?? this.userId,
      notes: notes ?? this.notes,
    );
  }
}
