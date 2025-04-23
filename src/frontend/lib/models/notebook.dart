import 'note.dart';

class Notebook {
  final String id;
  final String name;
  final String description;
  final String userId;
  final List<Note> notes;
  final DateTime? createdAt;
  final DateTime? deletedAt;

  const Notebook({
    required this.id,
    required this.name,
    required this.description,
    required this.userId,
    this.notes = const [],
    this.createdAt,
    this.deletedAt,
  });

  factory Notebook.fromJson(Map<String, dynamic> json) {
    List<Note> notesList = [];
    
    // Correctly handle notes data with proper logging
    if (json.containsKey('notes')) {
      final notesJson = json['notes'];
      if (notesJson != null) {
        try {
          if (notesJson is List) {
            notesList = notesJson
              .where((noteJson) => noteJson != null)
              .map<Note>((noteJson) => Note.fromJson(noteJson))
              .toList();
          }
        } catch (e) {
          print('Error parsing notes in notebook: $e');
        }
      }
    }
    
    // Parse createdAt and deletedAt
    DateTime? createdAt;
    if (json['created_at'] != null) {
      try {
        createdAt = DateTime.parse(json['created_at']);
      } catch (e) {
        print('Error parsing created_at: $e');
      }
    }

    DateTime? deletedAt;
    if (json['deleted_at'] != null) {
      try {
        deletedAt = DateTime.parse(json['deleted_at']);
      } catch (e) {
        print('Error parsing deleted_at: $e');
      }
    }
    
    return Notebook(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      notes: notesList,
      createdAt: createdAt,
      deletedAt: deletedAt,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'user_id': userId,
      'notes': notes.map((note) => note.toJson()).toList(),
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (deletedAt != null) 'deleted_at': deletedAt!.toIso8601String(),
    };
  }
  
  /// Creates a copy of this notebook with the given fields replaced with the new values
  Notebook copyWith({
    String? id,
    String? name,
    String? description,
    String? userId,
    List<Note>? notes,
    DateTime? createdAt,
    DateTime? deletedAt,
  }) {
    return Notebook(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      userId: userId ?? this.userId,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
