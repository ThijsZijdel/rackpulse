package boots

import (
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"time"

	"github.com/en3sis/rackpulse/agent/internal/history"
)

type Range struct {
	First int64
	Last  int64
}

var journalTimestamp = regexp.MustCompile(`\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC`)

func parseJSON(data []byte) ([]Range, bool) {
	var entries []struct {
		FirstEntry int64 `json:"first_entry"`
		LastEntry  int64 `json:"last_entry"`
	}
	trimmed := strings.TrimSpace(string(data))
	if !strings.HasPrefix(trimmed, "[") {
		return nil, false
	}
	if err := json.Unmarshal([]byte(trimmed), &entries); err != nil {
		return nil, false
	}
	boots := make([]Range, 0, len(entries))
	for _, entry := range entries {
		if entry.FirstEntry > 0 && entry.LastEntry >= entry.FirstEntry {
			boots = append(boots, Range{First: entry.FirstEntry / 1e6, Last: entry.LastEntry / 1e6})
		}
	}
	return boots, true
}

func parseText(data []byte) []Range {
	var boots []Range
	for _, line := range strings.Split(string(data), "\n") {
		stamps := journalTimestamp.FindAllString(line, -1)
		if len(stamps) != 2 {
			continue
		}
		first, err1 := time.Parse("2006-01-02 15:04:05 MST", stamps[0])
		last, err2 := time.Parse("2006-01-02 15:04:05 MST", stamps[1])
		if err1 != nil || err2 != nil || last.Before(first) {
			continue
		}
		boots = append(boots, Range{First: first.Unix(), Last: last.Unix()})
	}
	return boots
}

func FromJournal() []Range {
	run := func(args ...string) ([]byte, error) {
		ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
		defer cancel()
		cmd := exec.CommandContext(ctx, "journalctl", args...)
		cmd.Env = append(os.Environ(), "TZ=UTC")
		return cmd.Output()
	}
	out, err := run("--list-boots", "--no-pager", "-o", "json")
	if err == nil {
		if boots, ok := parseJSON(out); ok {
			return boots
		}
		if boots := parseText(out); len(boots) > 0 {
			return boots
		}
	}
	out, err = run("--list-boots", "--no-pager")
	if err != nil {
		return nil
	}
	return parseText(out)
}

func Apply(host *history.Host, boots []Range, now int64) bool {
	windowStart := now - history.RetentionSeconds
	var earliest int64
	for _, boot := range boots {
		if boot.Last < windowStart {
			continue
		}
		first := max(boot.First, windowStart)
		host.MarkRange(first, boot.Last, now)
		if earliest == 0 || first < earliest {
			earliest = first
		}
	}
	if earliest == 0 {
		return false
	}
	host.LowerCoverageStart(earliest)
	return true
}
