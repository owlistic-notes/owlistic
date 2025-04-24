package broker

type EventType string

const (
	// Standardized event types in format: <resource>.<action>
	NoteCreated     EventType = "note.created"
	NoteUpdated     EventType = "note.updated"
	NoteDeleted     EventType = "note.deleted"
	NotebookCreated EventType = "notebook.created"
	NotebookUpdated EventType = "notebook.updated"
	NotebookDeleted EventType = "notebook.deleted"
	BlockCreated    EventType = "block.created"
	BlockUpdated    EventType = "block.updated"
	BlockDeleted    EventType = "block.deleted"
	TaskCreated     EventType = "task.created"
	TaskUpdated     EventType = "task.updated"
	TaskDeleted     EventType = "task.deleted"
)
