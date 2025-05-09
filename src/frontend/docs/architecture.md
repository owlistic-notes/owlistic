# Owlistic Frontend Architecture

## Model-View-Presenter (MVP) Pattern

Owlistic uses the Model-View-Presenter (MVP) pattern with a few adaptations for Flutter:

### Components

1. **Models**: Plain Dart classes that represent data entities (Notebook, Note, Block, Task)
2. **Views**: Flutter widgets (screens) that display UI and forward user actions to presenters
3. **Presenters**: Providers that handle business logic and data manipulation

### Implementation Details

- **Providers as Presenters**: Instead of creating separate presenter classes, we leverage Flutter's Provider system to act as presenters. This avoids duplication of functionality.
- **Screens as Views**: Flutter widgets (screens) act as passive views that simply display data and handle user input.
- **ChangeNotifier**: Presenters extend ChangeNotifier to notify views of data changes.

### Benefits of This Approach

1. **Simplified Architecture**: Using providers directly as presenters reduces boilerplate code.
2. **Better State Management**: Leverages the Provider package's strengths for state management.
3. **Testability**: Business logic is isolated in presenters (providers), making it easier to test.
4. **Separation of Concerns**: UI logic is separated from business logic.

### Interaction Flow

1. User interacts with the View (Screen)
2. View calls methods on the Presenter (Provider)
3. Presenter updates the Model or performs business logic
4. Presenter notifies the View of changes via ChangeNotifier
5. View rebuilds to display updated data

### Example

```dart
// View (Screen)
class NotesScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Get the presenter
    final presenter = context.notesPresenter(listen: true);
    
    return Scaffold(
      body: ListView.builder(
        itemCount: presenter.notes.length,
        itemBuilder: (ctx, index) => NoteItem(presenter.notes[index]),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => presenter.createNote(...),
        child: Icon(Icons.add),
      ),
    );
  }
}

// Presenter (Provider)
class NotesProvider with ChangeNotifier {
  List<Note> _notes = [];
  List<Note> get notes => [..._notes];
  
  Future<void> createNote(...) async {
    // Business logic
    final note = await ApiService.createNote(...);
    _notes.add(note);
    notifyListeners(); // Notify view to rebuild
  }
}
```

### Real-time Updates with WebSockets

The MVP pattern is extended to handle real-time updates:

1. WebSocketProvider acts as a central presenter for real-time events
2. Domain-specific presenters (NotesProvider, NotebooksProvider, etc.) subscribe to relevant events
3. When WebSocket events arrive, the appropriate presenter updates its model and notifies views

This architecture provides a clean separation of concerns while efficiently handling real-time data updates.
