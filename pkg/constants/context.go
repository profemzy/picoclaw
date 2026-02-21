package constants

// contextKey is used for storing user context in request context.
type contextKey string

const (
	// ContextKeyJWTToken stores the raw JWT token for skill script passthrough.
	ContextKeyJWTToken contextKey = "jwt_token"
	// ContextKeyUserID stores the authenticated user's ID.
	ContextKeyUserID contextKey = "user_id"
	// ContextKeyBusinessID stores the requested business ID.
	ContextKeyBusinessID contextKey = "business_id"
)
