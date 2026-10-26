package config

import (
	"strings"
	"testing"
)

func TestValidateToken(t *testing.T) {
	if err := ValidateToken("rb1_" + strings.Repeat("aZ0-_", 8) + "abc"); err != nil {
		t.Errorf("valid key rejected: %v", err)
	}
	for _, token := range []string{"", "rb2_" + strings.Repeat("a", 43), "rb1_short", "rb1_" + strings.Repeat("a", 42) + "=", "rb1_" + strings.Repeat("a", 42) + " "} {
		if ValidateToken(token) == nil {
			t.Errorf("invalid key %q accepted", token)
		}
	}
}
