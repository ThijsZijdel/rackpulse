package history

import (
	"encoding/json"
	"os"
	"sync"

	"github.com/en3sis/rackpulse/agent/internal/atomicfile"
	"github.com/en3sis/rackpulse/agent/internal/collect"
)

const containerRetention = 7 * 86400

type ContainerSample struct {
	T      int64    `json:"t"`
	CPU    *float64 `json:"cpu"`
	Memory *int64   `json:"memory"`
}

func (s ContainerSample) at() int64 { return s.T }

type containerSeries struct {
	LastSeen    int64             `json:"lastSeen"`
	Minutes     []ContainerSample `json:"minutes"`
	FiveMinutes []ContainerSample `json:"fiveMinutes"`
}

type containerHistoryFile struct {
	Containers map[string]*containerSeries `json:"containers"`
}

type ContainerResponse struct {
	Time    int64             `json:"time"`
	Step    int               `json:"step"`
	Samples []ContainerSample `json:"samples"`
}

type Containers struct {
	mu     sync.Mutex
	series map[string]*containerSeries
}

func NewContainers() *Containers {
	return &Containers{series: map[string]*containerSeries{}}
}

func LoadContainers(path string) (*Containers, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var file containerHistoryFile
	if err := json.Unmarshal(data, &file); err != nil {
		return nil, err
	}
	history := NewContainers()
	for name, series := range file.Containers {
		if series != nil && name != "" {
			history.series[name] = series
		}
	}
	return history, nil
}

func (h *Containers) Save(path string) error {
	h.mu.Lock()
	data, err := json.Marshal(containerHistoryFile{Containers: h.series})
	h.mu.Unlock()
	if err != nil {
		return err
	}
	return atomicfile.Write(path, data, 0o600)
}

func (h *Containers) Record(containers []collect.Container, now int64) {
	h.mu.Lock()
	defer h.mu.Unlock()
	minute := now - now%fineStep
	for _, container := range containers {
		if container.Name == "" {
			continue
		}
		series := h.series[container.Name]
		if series == nil {
			series = &containerSeries{}
			h.series[container.Name] = series
		}
		series.LastSeen = now
		if container.State == "running" {
			series.Minutes = appendMinute(series.Minutes, ContainerSample{T: minute, CPU: container.CPU, Memory: container.Memory})
		}
	}
	h.pruneLocked(now)
}

func (h *Containers) pruneLocked(now int64) {
	currentBucket := now - now%coarseStep
	for name, series := range h.series {
		if series.LastSeen < now-containerRetention {
			delete(h.series, name)
			continue
		}
		series.FiveMinutes = rollUp(series.Minutes, series.FiveMinutes, currentBucket, averageContainerSamples)
		series.Minutes = dropBefore(series.Minutes, now-minuteRetention)
		series.FiveMinutes = dropBefore(series.FiveMinutes, now-containerRetention)
	}
}

func (h *Containers) Prune(now int64) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.pruneLocked(now)
}

func averageContainerSamples(bucket int64, group []ContainerSample) ContainerSample {
	average := ContainerSample{T: bucket}
	var cpuSum float64
	var memorySum int64
	cpuCount, memoryCount := 0, 0
	for _, sample := range group {
		if sample.CPU != nil {
			cpuSum += *sample.CPU
			cpuCount++
		}
		if sample.Memory != nil {
			memorySum += *sample.Memory
			memoryCount++
		}
	}
	if cpuCount > 0 {
		cpu := roundTo(cpuSum/float64(cpuCount), 2)
		average.CPU = &cpu
	}
	if memoryCount > 0 {
		memory := memorySum / int64(memoryCount)
		average.Memory = &memory
	}
	return average
}

func (h *Containers) Query(name string, since, now int64) (ContainerResponse, bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	series, ok := h.series[name]
	if !ok {
		return ContainerResponse{}, false
	}
	response := ContainerResponse{Time: now, Step: coarseStep}
	source := series.FiveMinutes
	if since >= now-minuteRetention {
		source = series.Minutes
		response.Step = fineStep
	}
	response.Samples = samplesSince(source, since)
	return response, true
}
