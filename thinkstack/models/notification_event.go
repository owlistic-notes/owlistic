package models

import "encoding/json"

type NotificationEvent struct {
	UserID    string `json:"user_id"`
	EventType string `json:"event_type"`
	Message   string `json:"message"`
	Timestamp string `json:"timestamp"`
}

func (n *NotificationEvent) FromJSON(data []byte) error {
	return json.Unmarshal(data, n)
}

func (n *NotificationEvent) ToJSON() ([]byte, error) {
	return json.Marshal(n)
}
