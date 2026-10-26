package pairing

import (
	"strings"
	"testing"
)

func TestProofMatchesMacVector(t *testing.T) {
	got := Proof("rb1_key", "ab", "cd")
	want := "5d0152a01ec90e3a2bb4b8ff9d4d3ea9383740440aaa615cc99dcdbbcdaba102"
	if got != want {
		t.Fatalf("proof %s, want %s", got, want)
	}
}

func TestValidNonce(t *testing.T) {
	cases := map[string]bool{
		strings.Repeat("a", 64):         true,
		strings.Repeat("Ab09", 16):      true,
		strings.Repeat("a", 63):         false,
		strings.Repeat("a", 65):         false,
		strings.Repeat("g", 64):         false,
		"":                              false,
		strings.Repeat("a", 62) + "\n0": false,
	}
	for nonce, want := range cases {
		if got := ValidNonce(nonce); got != want {
			t.Errorf("ValidNonce(%q) = %v, want %v", nonce, got, want)
		}
	}
}
