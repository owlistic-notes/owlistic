import 'note.dart';

class Notebook {
  final String id;
  final String name;
  final String description;
  final String userId;
  final List<Note> notes;

  Notebook({
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
          .toList() ?? [],
    );
  }
}
