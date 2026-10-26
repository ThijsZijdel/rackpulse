package history

import "sort"

type timedSample interface {
	at() int64
}

func (s Sample) at() int64 { return s.T }

func dropBefore[S timedSample](samples []S, cutoff int64) []S {
	index := sort.Search(len(samples), func(i int) bool { return samples[i].at() >= cutoff })
	if index == 0 {
		return samples
	}
	return append([]S(nil), samples[index:]...)
}

func appendMinute[S timedSample](samples []S, sample S) []S {
	if n := len(samples); n > 0 && samples[n-1].at() >= sample.at() {
		if samples[n-1].at() == sample.at() {
			samples[n-1] = sample
		}
		return samples
	}
	return append(samples, sample)
}

func rollUp[S timedSample](minutes, fiveMinutes []S, currentBucket int64, average func(bucket int64, group []S) S) []S {
	var last int64 = -1
	if n := len(fiveMinutes); n > 0 {
		last = fiveMinutes[n-1].at()
	}
	var bucket int64 = -1
	var group []S
	flush := func() {
		if len(group) > 0 {
			fiveMinutes = append(fiveMinutes, average(bucket, group))
		}
	}
	for _, sample := range minutes {
		sampleBucket := sample.at() - sample.at()%coarseStep
		if sampleBucket <= last || sampleBucket >= currentBucket {
			continue
		}
		if sampleBucket != bucket {
			flush()
			bucket = sampleBucket
			group = group[:0]
		}
		group = append(group, sample)
	}
	flush()
	return fiveMinutes
}

func samplesSince[S timedSample](samples []S, since int64) []S {
	out := make([]S, 0, len(samples))
	for _, sample := range samples {
		if sample.at() >= since {
			out = append(out, sample)
		}
	}
	return out
}
