package health

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/sipeed/picoclaw/pkg/agent"
	"github.com/sipeed/picoclaw/pkg/config"
	"github.com/sipeed/picoclaw/pkg/constants"
	"github.com/sipeed/picoclaw/pkg/utils"
)

// LedgerForgeClaims represents the JWT claims from LedgerForge auth tokens.
type LedgerForgeClaims struct {
	Sub      string `json:"sub"`
	Username string `json:"username"`
	Email    string `json:"email"`
	Role     string `json:"role"`
	jwt.RegisteredClaims
}

type Server struct {
	server    *http.Server
	mu        sync.RWMutex
	ready     bool
	checks    map[string]Check
	startTime time.Time

	// API layer fields
	agentLoop      *agent.AgentLoop
	requirePairing bool
	pairedTokens   map[string]bool // token hash -> true
	pairingCode    string
	pairingUsed    bool
	configPath     string
	model          string
	jwtSecret      string
}

type Check struct {
	Name      string    `json:"name"`
	Status    string    `json:"status"`
	Message   string    `json:"message,omitempty"`
	Timestamp time.Time `json:"timestamp"`
}

type StatusResponse struct {
	Status string           `json:"status"`
	Uptime string           `json:"uptime"`
	Paired bool             `json:"paired,omitempty"`
	Checks map[string]Check `json:"checks,omitempty"`
}

type WebhookRequest struct {
	Message    string `json:"message"`
	BusinessID string `json:"business_id,omitempty"`
}

type WebhookResponse struct {
	Response *string `json:"response"`
	Model    *string `json:"model"`
	Error    *string `json:"error"`
}

// ServerOption configures the health server.
type ServerOption func(*Server)

// WithAgentLoop enables the webhook API with the given agent loop.
func WithAgentLoop(al *agent.AgentLoop) ServerOption {
	return func(s *Server) {
		s.agentLoop = al
	}
}

// WithPairing enables bearer token pairing.
func WithPairing(require bool, tokenHashes []string, configPath string) ServerOption {
	return func(s *Server) {
		s.requirePairing = require
		s.configPath = configPath
		for _, h := range tokenHashes {
			s.pairedTokens[h] = true
		}
	}
}

// WithModel sets the model name returned in webhook responses.
func WithModel(model string) ServerOption {
	return func(s *Server) {
		s.model = model
	}
}

// WithJWTAuth enables LedgerForge JWT validation on the webhook endpoint.
func WithJWTAuth(secret string) ServerOption {
	return func(s *Server) {
		s.jwtSecret = secret
	}
}

func NewServer(host string, port int, opts ...ServerOption) *Server {
	s := &Server{
		ready:        false,
		checks:       make(map[string]Check),
		startTime:    time.Now(),
		pairedTokens: make(map[string]bool),
	}

	for _, opt := range opts {
		opt(s)
	}

	// Generate pairing code if agent loop is enabled
	if s.agentLoop != nil {
		s.pairingCode = generatePairingCode()
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", s.healthHandler)
	mux.HandleFunc("/ready", s.readyHandler)

	if s.agentLoop != nil {
		mux.HandleFunc("POST /webhook", s.webhookHandler)
		mux.HandleFunc("POST /pair", s.pairHandler)
	}

	writeTimeout := 5 * time.Second
	if s.agentLoop != nil {
		writeTimeout = 150 * time.Second
	}

	addr := fmt.Sprintf("%s:%d", host, port)
	s.server = &http.Server{
		Addr:         addr,
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: writeTimeout,
	}

	return s
}

// GetPairingCode returns the one-time pairing code.
func (s *Server) GetPairingCode() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if s.pairingUsed {
		return ""
	}
	return s.pairingCode
}

func (s *Server) Start() error {
	s.mu.Lock()
	s.ready = true
	s.mu.Unlock()
	return s.server.ListenAndServe()
}

func (s *Server) StartContext(ctx context.Context) error {
	s.mu.Lock()
	s.ready = true
	s.mu.Unlock()

	errCh := make(chan error, 1)
	go func() {
		errCh <- s.server.ListenAndServe()
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		return s.server.Shutdown(context.Background())
	}
}

func (s *Server) Stop(ctx context.Context) error {
	s.mu.Lock()
	s.ready = false
	s.mu.Unlock()
	return s.server.Shutdown(ctx)
}

func (s *Server) SetReady(ready bool) {
	s.mu.Lock()
	s.ready = ready
	s.mu.Unlock()
}

func (s *Server) RegisterCheck(name string, checkFn func() (bool, string)) {
	s.mu.Lock()
	defer s.mu.Unlock()

	status, msg := checkFn()
	s.checks[name] = Check{
		Name:      name,
		Status:    statusString(status),
		Message:   msg,
		Timestamp: time.Now(),
	}
}

func (s *Server) healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	uptime := time.Since(s.startTime)
	resp := StatusResponse{
		Status: "ok",
		Uptime: uptime.String(),
	}

	// If agent loop is enabled, report paired status.
	// Check if the request has a valid token first; otherwise check if any tokens exist.
	if s.agentLoop != nil {
		if s.isAuthorized(r) {
			resp.Paired = true
		} else {
			resp.Paired = s.HasPairedClients()
		}
	}

	json.NewEncoder(w).Encode(resp)
}

func (s *Server) readyHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	s.mu.RLock()
	ready := s.ready
	checks := make(map[string]Check)
	for k, v := range s.checks {
		checks[k] = v
	}
	s.mu.RUnlock()

	if !ready {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(StatusResponse{
			Status: "not ready",
			Checks: checks,
		})
		return
	}

	for _, check := range checks {
		if check.Status == "fail" {
			w.WriteHeader(http.StatusServiceUnavailable)
			json.NewEncoder(w).Encode(StatusResponse{
				Status: "not ready",
				Checks: checks,
			})
			return
		}
	}

	w.WriteHeader(http.StatusOK)
	uptime := time.Since(s.startTime)
	json.NewEncoder(w).Encode(StatusResponse{
		Status: "ready",
		Uptime: uptime.String(),
		Checks: checks,
	})
}

func (s *Server) webhookHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// Try JWT auth first if configured, fall back to pc_ token auth
	var sessionKey string
	var userCtx context.Context
	rawToken := s.extractRawToken(r)

	if s.jwtSecret != "" && rawToken != "" && !strings.HasPrefix(rawToken, "pc_") {
		claims, err := s.validateJWT(rawToken)
		if err != nil {
			w.WriteHeader(http.StatusUnauthorized)
			errMsg := "unauthorized: " + err.Error()
			json.NewEncoder(w).Encode(WebhookResponse{Error: &errMsg})
			return
		}
		sessionKey = "user:" + claims.Sub
		// Store JWT and user context for skill script passthrough
		userCtx = context.WithValue(r.Context(), constants.ContextKeyJWTToken, rawToken)
		userCtx = context.WithValue(userCtx, constants.ContextKeyUserID, claims.Sub)
	} else {
		// Legacy pc_ token auth
		if !s.isAuthorized(r) {
			w.WriteHeader(http.StatusUnauthorized)
			errMsg := "unauthorized: invalid or missing bearer token"
			json.NewEncoder(w).Encode(WebhookResponse{Error: &errMsg})
			return
		}
		tokenHash := s.extractTokenHash(r)
		sessionKey = "api:" + tokenHash[:8]
		userCtx = r.Context()
	}

	var message string
	var businessID string
	var mediaPaths []string

	contentType := r.Header.Get("Content-Type")
	if strings.HasPrefix(contentType, "multipart/form-data") {
		// Multipart form: message + optional files (max 20MB)
		if err := r.ParseMultipartForm(20 << 20); err != nil {
			w.WriteHeader(http.StatusBadRequest)
			errMsg := "failed to parse multipart form"
			json.NewEncoder(w).Encode(WebhookResponse{Error: &errMsg})
			return
		}
		message = r.FormValue("message")
		businessID = r.FormValue("business_id")

		// Save uploaded files to workspace/media/ so the agent's read_file tool can access them
		workspace := s.agentLoop.DefaultWorkspace()

		if r.MultipartForm != nil && r.MultipartForm.File != nil {
			for _, fhs := range r.MultipartForm.File {
				for _, fh := range fhs {
					file, err := fh.Open()
					if err != nil {
						continue
					}
					localPath := utils.SaveUploadedFile(file, fh.Filename, workspace)
					file.Close()
					if localPath != "" {
						mediaPaths = append(mediaPaths, localPath)
					}
				}
			}
		}
	} else {
		// JSON body (existing path)
		var req WebhookRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			w.WriteHeader(http.StatusBadRequest)
			errMsg := "invalid request body"
			json.NewEncoder(w).Encode(WebhookResponse{Error: &errMsg})
			return
		}
		message = req.Message
		businessID = req.BusinessID
	}

	if strings.TrimSpace(message) == "" && len(mediaPaths) == 0 {
		w.WriteHeader(http.StatusBadRequest)
		errMsg := "message or file is required"
		json.NewEncoder(w).Encode(WebhookResponse{Error: &errMsg})
		return
	}

	// Default message for file-only uploads — include "receipt" keyword
	// so the skill's receipt detection triggers automatically
	if strings.TrimSpace(message) == "" {
		message = "Process the attached receipt"
	}

	// Store business_id in context if provided
	if businessID != "" {
		userCtx = context.WithValue(userCtx, constants.ContextKeyBusinessID, businessID)
	}

	ctx, cancel := context.WithTimeout(userCtx, 120*time.Second)
	defer cancel()

	response, err := s.agentLoop.ProcessDirectWithChannel(
		ctx, message, sessionKey, "api", "mobile-client", mediaPaths...,
	)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		errMsg := err.Error()
		json.NewEncoder(w).Encode(WebhookResponse{Error: &errMsg})
		return
	}

	w.WriteHeader(http.StatusOK)
	model := s.model
	json.NewEncoder(w).Encode(WebhookResponse{
		Response: &response,
		Model:    &model,
	})
}

// validateJWT validates a LedgerForge JWT token and returns its claims.
func (s *Server) validateJWT(tokenString string) (*LedgerForgeClaims, error) {
	claims := &LedgerForgeClaims{}
	token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (any, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return []byte(s.jwtSecret), nil
	})
	if err != nil {
		return nil, fmt.Errorf("invalid token: %w", err)
	}
	if !token.Valid {
		return nil, fmt.Errorf("token is not valid")
	}
	if claims.Sub == "" {
		return nil, fmt.Errorf("token missing sub claim")
	}
	return claims, nil
}

// extractRawToken extracts the raw bearer token from the Authorization header.
func (s *Server) extractRawToken(r *http.Request) string {
	auth := r.Header.Get("Authorization")
	if !strings.HasPrefix(auth, "Bearer ") {
		return ""
	}
	return strings.TrimPrefix(auth, "Bearer ")
}

func (s *Server) pairHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	code := r.Header.Get("X-Pairing-Code")
	if code == "" {
		w.WriteHeader(http.StatusBadRequest)
		errMsg := "X-Pairing-Code header is required"
		json.NewEncoder(w).Encode(WebhookResponse{Error: &errMsg})
		return
	}

	s.mu.Lock()
	if s.pairingUsed {
		s.mu.Unlock()
		w.WriteHeader(http.StatusGone)
		errMsg := "pairing code already used"
		json.NewEncoder(w).Encode(WebhookResponse{Error: &errMsg})
		return
	}

	if code != s.pairingCode {
		s.mu.Unlock()
		w.WriteHeader(http.StatusForbidden)
		errMsg := "invalid pairing code"
		json.NewEncoder(w).Encode(WebhookResponse{Error: &errMsg})
		return
	}

	// Generate bearer token
	token, tokenHash := generateBearerToken()
	s.pairedTokens[tokenHash] = true
	s.pairingUsed = true
	s.mu.Unlock()

	// Persist the token hash to config
	if s.configPath != "" {
		s.persistTokenHash(tokenHash)
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{
		"paired":  true,
		"token":   token,
		"message": "paired successfully",
		"error":   nil,
	})
}

// isAuthorized checks if the request has a valid bearer token.
func (s *Server) isAuthorized(r *http.Request) bool {
	// If no pairing required and no tokens exist, skip auth
	s.mu.RLock()
	tokenCount := len(s.pairedTokens)
	requirePairing := s.requirePairing
	s.mu.RUnlock()

	if !requirePairing && tokenCount == 0 {
		return true
	}

	auth := r.Header.Get("Authorization")
	if !strings.HasPrefix(auth, "Bearer ") {
		return false
	}

	token := strings.TrimPrefix(auth, "Bearer ")
	hash := hashToken(token)

	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.pairedTokens[hash]
}

// extractTokenHash returns the SHA-256 hash of the bearer token from the request.
func (s *Server) extractTokenHash(r *http.Request) string {
	auth := r.Header.Get("Authorization")
	token := strings.TrimPrefix(auth, "Bearer ")
	return hashToken(token)
}

// persistTokenHash saves the token hash to the config file.
func (s *Server) persistTokenHash(tokenHash string) {
	cfg, err := config.LoadConfig(s.configPath)
	if err != nil {
		return
	}

	// Add the new token hash if not already present
	for _, existing := range cfg.Gateway.PairedTokens {
		if existing == tokenHash {
			return
		}
	}
	cfg.Gateway.PairedTokens = append(cfg.Gateway.PairedTokens, tokenHash)

	config.SaveConfig(s.configPath, cfg)
}

func generatePairingCode() string {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		// Fallback - should never happen
		return "000000"
	}
	return fmt.Sprintf("%06d", n.Int64())
}

func generateBearerToken() (string, string) {
	b := make([]byte, 32)
	rand.Read(b)
	token := "pc_" + hex.EncodeToString(b)
	return token, hashToken(token)
}

func hashToken(token string) string {
	h := sha256.Sum256([]byte(token))
	return hex.EncodeToString(h[:])
}

func statusString(ok bool) string {
	if ok {
		return "ok"
	}
	return "fail"
}

// GenerateNewPairingCode generates a new pairing code and resets the used flag.
func (s *Server) GenerateNewPairingCode() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.pairingCode = generatePairingCode()
	s.pairingUsed = false
	return s.pairingCode
}

// HasPairedClients returns true if there are any paired clients.
func (s *Server) HasPairedClients() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return len(s.pairedTokens) > 0
}

// ResetPairingCode is called after a failed pair attempt to generate a new code.
func (s *Server) ResetPairingCode() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.pairingUsed {
		return
	}
	s.pairingCode = generatePairingCode()
	s.pairingUsed = false
}

func init() {
	// Suppress unused import warnings during development
	_ = os.Stderr
}
