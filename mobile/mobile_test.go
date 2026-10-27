package mobile

import (
	"encoding/json"
	"testing"
	"time"
)

type testListener struct{ progress int }

func (l *testListener) OnProgress(stage string, done, total int) { l.progress++ }
func (l *testListener) OnLog(msg string)                         {}

func TestRunEmptyIP(t *testing.T) {
	if _, err := Run(NewConfig(), nil); err == nil {
		t.Fatal("expected error for empty IP text")
	}
}

func TestRunInvalidIPSkipped(t *testing.T) {
	cfg := NewConfig()
	cfg.IPRanges = "not-an-ip\n127.0.0.1/32"
	cfg.PingTimes = 1
	cfg.DisableDownload = true
	l := &testListener{}
	out, err := Run(cfg, l)
	if err != nil {
		t.Fatal(err)
	}
	var results []Result
	if err := json.Unmarshal([]byte(out), &results); err != nil {
		t.Fatalf("invalid json %q: %v", out, err)
	}
	if l.progress == 0 {
		t.Fatal("expected progress callbacks")
	}
}

func TestStop(t *testing.T) {
	cfg := NewConfig()
	cfg.IPRanges = "192.0.2.0/24,198.51.100.0/24,203.0.113.0/24"
	cfg.Routines = 1
	cfg.PingTimes = 1
	cfg.DisableDownload = true
	go func() {
		time.Sleep(200 * time.Millisecond)
		Stop()
	}()
	start := time.Now()
	if _, err := Run(cfg, nil); err != nil {
		t.Fatal(err)
	}
	if time.Since(start) > 3*time.Second {
		t.Fatalf("Stop did not interrupt run, took %v", time.Since(start))
	}
}
