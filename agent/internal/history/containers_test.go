package history

import (
	"testing"

	"github.com/en3sis/rackpulse/agent/internal/collect"
)

func TestContainerHistoryAveragesAndRetention(t *testing.T) {
	start := int64(1761480000)
	h := NewContainers()
	for i := range 6 {
		now := start + int64(i)*60 + 5
		var cpu *float64
		if i > 0 {
			value := float64(i)
			cpu = &value
		}
		memory := int64(100 * (i + 1))
		h.Record([]collect.Container{{Name: "app-web-1", State: "running", CPU: cpu, Memory: &memory}, {Name: "stopped", State: "exited"}}, now)
	}
	now := start + 6*60
	if r, ok := h.Query("app-web-1", now-600, now); !ok || r.Step != fineStep || len(r.Samples) != 6 || r.Samples[0].CPU != nil {
		t.Fatalf("minute samples %+v", r)
	}
	r, ok := h.Query("app-web-1", now-2*86400, now)
	if !ok || r.Step != coarseStep || len(r.Samples) != 1 || *r.Samples[0].CPU != 2.5 || *r.Samples[0].Memory != 300 {
		t.Fatalf("five minute samples %+v", r.Samples)
	}
	if r, ok := h.Query("stopped", 0, now); !ok || len(r.Samples) != 0 {
		t.Fatalf("stopped container %+v %v", r, ok)
	}
	if _, ok := h.Query("missing", 0, now); ok {
		t.Fatal("unknown name found")
	}
	h.Prune(now + containerRetention + 3600)
	if _, ok := h.Query("app-web-1", 0, now); ok {
		t.Fatal("container kept after 7 days")
	}
}
