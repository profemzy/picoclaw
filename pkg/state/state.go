package state

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// AuthEntry stores auth context for a specific business.
type AuthEntry struct {
	JWTToken  string    `json:"jwt_token"`
	Channel   string    `json:"channel"`
	ChatID    string    `json:"chat_id"`
	UpdatedAt time.Time `json:"updated_at"`
}

// State represents the persistent state for a workspace.
// It includes information about the last active channel/chat.
type State struct {
	// LastChannel is the last channel used for communication
	LastChannel string `json:"last_channel,omitempty"`

	// LastChatID is the last chat ID used for communication
	LastChatID string `json:"last_chat_id,omitempty"`

	// ActiveAuth stores auth per business ID for heartbeat use
	ActiveAuth map[string]AuthEntry `json:"active_auth,omitempty"`

	// Timestamp is the last time this state was updated
	Timestamp time.Time `json:"timestamp"`
}

// Manager manages persistent state with atomic saves.
type Manager struct {
	workspace string
	state     *State
	mu        sync.RWMutex
	stateFile string
}

// NewManager creates a new state manager for the given workspace.
func NewManager(workspace string) *Manager {
	stateDir := filepath.Join(workspace, "state")
	stateFile := filepath.Join(stateDir, "state.json")
	oldStateFile := filepath.Join(workspace, "state.json")

	// Create state directory if it doesn't exist
	os.MkdirAll(stateDir, 0o755)

	sm := &Manager{
		workspace: workspace,
		stateFile: stateFile,
		state:     &State{},
	}

	// Try to load from new location first
	if _, err := os.Stat(stateFile); os.IsNotExist(err) {
		// New file doesn't exist, try migrating from old location
		if data, err := os.ReadFile(oldStateFile); err == nil {
			if err := json.Unmarshal(data, sm.state); err == nil {
				// Migrate to new location
				sm.saveAtomic()
				log.Printf("[INFO] state: migrated state from %s to %s", oldStateFile, stateFile)
			}
		}
	} else {
		// Load from new location
		sm.load()
	}

	return sm
}

// SetLastChannel atomically updates the last channel and saves the state.
// This method uses a temp file + rename pattern for atomic writes,
// ensuring that the state file is never corrupted even if the process crashes.
func (sm *Manager) SetLastChannel(channel string) error {
	sm.mu.Lock()
	defer sm.mu.Unlock()

	// Update state
	sm.state.LastChannel = channel
	sm.state.Timestamp = time.Now()

	// Atomic save using temp file + rename
	if err := sm.saveAtomic(); err != nil {
		return fmt.Errorf("failed to save state atomically: %w", err)
	}

	return nil
}

// SetLastChatID atomically updates the last chat ID and saves the state.
func (sm *Manager) SetLastChatID(chatID string) error {
	sm.mu.Lock()
	defer sm.mu.Unlock()

	// Update state
	sm.state.LastChatID = chatID
	sm.state.Timestamp = time.Now()

	// Atomic save using temp file + rename
	if err := sm.saveAtomic(); err != nil {
		return fmt.Errorf("failed to save state atomically: %w", err)
	}

	return nil
}

// GetLastChannel returns the last channel from the state.
func (sm *Manager) GetLastChannel() string {
	sm.mu.RLock()
	defer sm.mu.RUnlock()
	return sm.state.LastChannel
}

// GetLastChatID returns the last chat ID from the state.
func (sm *Manager) GetLastChatID() string {
	sm.mu.RLock()
	defer sm.mu.RUnlock()
	return sm.state.LastChatID
}

// SetBusinessAuth persists auth context for a specific business.
// Each business gets its own entry so heartbeat can serve all active businesses.
func (sm *Manager) SetBusinessAuth(businessID, jwtToken, channel, chatID string) error {
	sm.mu.Lock()
	defer sm.mu.Unlock()

	if sm.state.ActiveAuth == nil {
		sm.state.ActiveAuth = make(map[string]AuthEntry)
	}

	sm.state.ActiveAuth[businessID] = AuthEntry{
		JWTToken:  jwtToken,
		Channel:   channel,
		ChatID:    chatID,
		UpdatedAt: time.Now(),
	}
	sm.state.Timestamp = time.Now()

	if err := sm.saveAtomic(); err != nil {
		return fmt.Errorf("failed to save state atomically: %w", err)
	}

	return nil
}

// GetActiveAuth returns all active business auth entries.
func (sm *Manager) GetActiveAuth() map[string]AuthEntry {
	sm.mu.RLock()
	defer sm.mu.RUnlock()

	// Return a copy to avoid races
	result := make(map[string]AuthEntry, len(sm.state.ActiveAuth))
	for k, v := range sm.state.ActiveAuth {
		result[k] = v
	}
	return result
}

// GetTimestamp returns the timestamp of the last state update.
func (sm *Manager) GetTimestamp() time.Time {
	sm.mu.RLock()
	defer sm.mu.RUnlock()
	return sm.state.Timestamp
}

// saveAtomic performs an atomic save using temp file + rename.
// This ensures that the state file is never corrupted:
// 1. Write to a temp file
// 2. Rename temp file to target (atomic on POSIX systems)
// 3. If rename fails, cleanup the temp file
//
// Must be called with the lock held.
func (sm *Manager) saveAtomic() error {
	// Create temp file in the same directory as the target
	tempFile := sm.stateFile + ".tmp"

	// Marshal state to JSON
	data, err := json.MarshalIndent(sm.state, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal state: %w", err)
	}

	// Write to temp file
	if err := os.WriteFile(tempFile, data, 0o644); err != nil {
		return fmt.Errorf("failed to write temp file: %w", err)
	}

	// Atomic rename from temp to target
	if err := os.Rename(tempFile, sm.stateFile); err != nil {
		// Cleanup temp file if rename fails
		os.Remove(tempFile)
		return fmt.Errorf("failed to rename temp file: %w", err)
	}

	return nil
}

// load loads the state from disk.
func (sm *Manager) load() error {
	data, err := os.ReadFile(sm.stateFile)
	if err != nil {
		// File doesn't exist yet, that's OK
		if os.IsNotExist(err) {
			return nil
		}
		return fmt.Errorf("failed to read state file: %w", err)
	}

	if err := json.Unmarshal(data, sm.state); err != nil {
		return fmt.Errorf("failed to unmarshal state: %w", err)
	}

	return nil
}
