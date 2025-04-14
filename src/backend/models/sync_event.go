package models

import "encoding/json"

type SyncEvent struct {
	DeviceID    string `json:"device_id"`
	LastEventID string `json:"last_event_id"`
	Timestamp   string `json:"timestamp"`
}

func (s *SyncEvent) FromJSON(data []byte) error {
	return json.Unmarshal(data, s)
}

func (s *SyncEvent) ToJSON() ([]byte, error) {
	return json.Marshal(s)
}
