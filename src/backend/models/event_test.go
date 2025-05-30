package models

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestNewEvent(t *testing.T) {
	testCases := []struct {
		name      string
		event     string
		entity    string
		operation string
		actorID   string
		data      interface{}
		wantErr   bool
	}{
		{
			name:      "Valid event",
			event:     "test.created",
			entity:    "test",
			operation: "create",
			actorID:   "user-123",
			data:      map[string]interface{}{"key": "value"},
			wantErr:   false,
		},
		{
			name:      "Invalid JSON data",
			event:     "test.created",
			entity:    "test",
			data:      make(chan int), // Unmarshalable type
			wantErr:   true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			event, err := NewEvent(tc.event, tc.entity, tc.operation, tc.actorID, tc.data)
			if tc.wantErr {
				assert.Error(t, err)
				return
			}

			assert.NoError(t, err)
			assert.NotNil(t, event)
			assert.Equal(t, tc.event, event.Event)
			assert.Equal(t, tc.entity, event.Entity)
			assert.Equal(t, "pending", event.Status)
			assert.False(t, event.Dispatched)
			assert.Nil(t, event.DispatchedAt)
		})
	}
}
