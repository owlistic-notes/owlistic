package broker

const (
	UserSubject     string = "user"
	NotebookSubject string = "notebook"
	NoteSubject     string = "note"
	BlockSubject    string = "block"
	TaskSubject     string = "task"
)

var SubjectNames = []string{
	UserSubject,
	NotebookSubject,
	NoteSubject,
	BlockSubject,
	TaskSubject,
}

type EventType string

const (
	// Standardized event types in format: <resource>.<action>
	NoteCreated  EventType = "note.created"
	NoteUpdated  EventType = "note.updated"
	NoteDeleted  EventType = "note.deleted"
	NoteRestored EventType = "note.restored"

	NotebookCreated  EventType = "notebook.created"
	NotebookUpdated  EventType = "notebook.updated"
	NotebookDeleted  EventType = "notebook.deleted"
	NotebookRestored EventType = "notebook.restored"

	BlockCreated EventType = "block.created"
	BlockUpdated EventType = "block.updated"
	BlockDeleted EventType = "block.deleted"

	TaskCreated EventType = "task.created"
	TaskUpdated EventType = "task.updated"
	TaskDeleted EventType = "task.deleted"

	// User events
	UserCreated EventType = "user.created"
	UserUpdated EventType = "user.updated"
	UserDeleted EventType = "user.deleted"

	// Trash events
	TrashEmptied EventType = "trash.emptied"
)
