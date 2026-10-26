package boots

import (
	"reflect"
	"testing"

	"github.com/en3sis/rackpulse/agent/internal/history"
)

func TestParseJSON(t *testing.T) {
	data := []byte(`[{"index":-1,"boot_id":"a","first_entry":1761400000123456,"last_entry":1761410000999999},{"index":0,"boot_id":"b","first_entry":1761420000000000,"last_entry":1761480000000000}]`)
	got, ok := parseJSON(data)
	want := []Range{{1761400000, 1761410000}, {1761420000, 1761480000}}
	if !ok || !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v %v", got, ok)
	}
	if _, ok := parseJSON([]byte("IDX BOOT ID")); ok {
		t.Fatal("text accepted as JSON")
	}
}

func TestParseText(t *testing.T) {
	newer := "IDX BOOT ID                          FIRST ENTRY                 LAST ENTRY\n" +
		" -1 0b2d3c6a8f1e4b7c9d0e1f2a3b4c5d6e Sat 2025-10-25 13:46:40 UTC Sat 2025-10-25 16:33:20 UTC\n" +
		"  0 630178f6a2a444d68f31017d39323fac Sat 2025-10-25 19:20:00 UTC Sun 2025-10-26 12:00:00 UTC\n"
	older := "-1 0b2d3c6a8f1e4b7c9d0e1f2a3b4c5d6e Sat 2025-10-25 13:46:40 UTC\u2014Sat 2025-10-25 16:33:20 UTC\n" +
		" 0 630178f6a2a444d68f31017d39323fac Sat 2025-10-25 19:20:00 UTC\u2014Sun 2025-10-26 12:00:00 UTC\n"
	want := []Range{{1761400000, 1761410000}, {1761420000, 1761480000}}
	for name, data := range map[string]string{"newer": newer, "older": older} {
		if got := parseText([]byte(data)); !reflect.DeepEqual(got, want) {
			t.Errorf("%s: got %v", name, got)
		}
	}
}

func TestApplyBoots(t *testing.T) {
	now := int64(1761480000)
	h := history.NewHost(now)
	boots := []Range{{now - 40*86400, now - 39*86400}, {now - 32*86400, now - 30*86400}, {now - 3600, now}}
	if !Apply(h, boots, now) {
		t.Fatal("no boots applied")
	}
	if c := h.Query(0, now).CoverageStart; c != now-history.RetentionSeconds {
		t.Fatalf("coverage %d", c)
	}
	r := h.Query(now-2*3600, now)
	if r.Hours["1761476400"] != 60 || r.Hours["1761480000"] != 1 {
		t.Fatalf("hours %v", r.Hours)
	}
}
