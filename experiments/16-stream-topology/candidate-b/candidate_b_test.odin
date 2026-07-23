// Experiment 16, candidate B — the Handler returns a producer polled by the
// owner lane.
//
// The framework side is deliberately simple: the lane polls each registered
// producer every tick and writes whatever it yields. The measured cost of that
// simplicity is exactly what this prototype exists to record:
//
//   1. cross-thread delivery is NOT framework work here — the application must
//      build its own synchronized, bounded hand-off buffer (this file has to
//      build one just to make ten updates flow, and so would every user);
//   2. the framework cannot see or enforce boundedness: the app buffer below
//      is bounded because THIS app chose a cap — nothing in the model refuses
//      an unbounded one, so G7-4 becomes a convention, not a contract;
//   3. an idle producer still costs a poll per tick per stream (counted).
//
// DISPOSABLE PROTOTYPE (WP86): never imported by `web`.
package wp86_candidate_b

import "core:sync"
import "core:thread"
import "core:testing"
import "core:time"

APP_BUFFER_CAP :: 8
EVENT_BYTES    :: 64

App_Event :: struct {
	len:  int,
	data: [EVENT_BYTES]u8,
}

// The application-owned hand-off buffer. THE POINT: this synchronization,
// this cap and this full policy are all re-invented per application under
// candidate B — the framework never sees them.
App_Feed :: struct {
	mu:    sync.Mutex,
	queue: [APP_BUFFER_CAP]App_Event,
	head:  int,
	count: int,
	done:  bool,
}

app_feed_push :: proc(f: ^App_Feed, data: []u8) -> bool {
	sync.mutex_lock(&f.mu)
	defer sync.mutex_unlock(&f.mu)
	if f.count >= APP_BUFFER_CAP {
		return false // this app refuses; another app may grow unbounded — unchecked
	}
	e := &f.queue[(f.head + f.count) % APP_BUFFER_CAP]
	e.len = min(len(data), EVENT_BYTES)
	copy(e.data[:e.len], data[:e.len])
	f.count += 1
	return true
}

// The producer signature the Handler would return: polled ON the owner lane.
poll :: proc(f: ^App_Feed) -> (event: App_Event, has: bool, done: bool) {
	sync.mutex_lock(&f.mu)
	defer sync.mutex_unlock(&f.mu)
	if f.count == 0 {
		return App_Event{}, false, f.done
	}
	event = f.queue[f.head]
	f.head = (f.head + 1) % APP_BUFFER_CAP
	f.count -= 1
	return event, true, false
}

Stream :: struct {
	feed:        ^App_Feed,
	sink:        [dynamic]u8,
	sink_events: int,
	closed:      bool,
}

Lane :: struct {
	streams:     []Stream,
	stop:        bool, // atomic
	empty_polls: int,  // idle-producer cost, the number candidate C does not pay
	thread:      ^thread.Thread,
}

lane_main :: proc(l: ^Lane) {
	for !sync.atomic_load(&l.stop) {
		for &s in l.streams {
			if s.closed {continue}
			event, has, done := poll(s.feed)
			if has {
				append(&s.sink, ..event.data[:event.len])
				s.sink_events += 1
			} else {
				l.empty_polls += 1
				if done {s.closed = true}
			}
		}
		time.sleep(time.Millisecond) // the poll cadence IS the latency floor
	}
}

Feeder :: struct {
	feed:   ^App_Feed,
	base:   u8,
	thread: ^thread.Thread,
}

feeder_main :: proc(fd: ^Feeder) {
	for i in 0 ..< 10 {
		msg := [2]u8{fd.base, u8('0' + i)}
		for !app_feed_push(fd.feed, msg[:]) {
			time.sleep(time.Millisecond)
		}
	}
	sync.mutex_lock(&fd.feed.mu)
	fd.feed.done = true
	sync.mutex_unlock(&fd.feed.mu)
}

@(test)
ten_updates_flow_but_the_hand_off_is_application_work :: proc(t: ^testing.T) {
	feeds: [2]App_Feed
	streams := [2]Stream{{feed = &feeds[0]}, {feed = &feeds[1]}}
	lane := Lane{streams = streams[:]}
	lane.thread = thread.create_and_start_with_poly_data(&lane, lane_main)

	feeders := [2]Feeder{{feed = &feeds[0], base = 'a'}, {feed = &feeds[1], base = 'b'}}
	for &fd in feeders {
		fd.thread = thread.create_and_start_with_poly_data(&fd, feeder_main)
	}
	for &fd in feeders {
		thread.join(fd.thread)
		thread.destroy(fd.thread)
	}
	deadline := time.tick_now()
	for {
		all := true
		for &s in lane.streams {
			if !sync.atomic_load(&s.closed) {all = false}
		}
		if all {break}
		if time.tick_since(deadline) > 2 * time.Second {break}
		time.sleep(time.Millisecond)
	}
	sync.atomic_store(&lane.stop, true)
	thread.join(lane.thread)
	thread.destroy(lane.thread)

	for &s, i in lane.streams {
		testing.expect_value(t, s.sink_events, 10)
		in_order := true
		for e in 0 ..< 10 {
			if s.sink[e * 2] != u8('a' + i) || s.sink[e * 2 + 1] != u8('0' + e) {
				in_order = false
			}
		}
		testing.expect(t, in_order, "per-feed order must survive the poll path")
		delete(s.sink)
	}
	// The recorded evidence: even in a run this short, idle polls accumulate.
	testing.expect(t, lane.empty_polls > 0, "the poll model pays for idle producers; record the count")
}

@(test)
detach_requires_the_application_to_keep_state_alive :: proc(t: ^testing.T) {
	// The Handler has returned; the ONLY thing keeping the feed valid is that
	// this test (the application) placed it in storage that outlives the
	// Handler frame. Candidate B has no framework-owned lifetime: an app that
	// stack-allocates the feed hands the lane a dangling pointer, and no
	// generation/stale check exists to refuse it. This control documents the
	// escape shape rather than dereferencing freed memory.
	feed := new(App_Feed) // application heap allocation, application's burden
	defer free(feed)
	ok := app_feed_push(feed, []u8{'x'})
	testing.expect(t, ok)
	event, has, _ := poll(feed)
	testing.expect(t, has)
	testing.expect_value(t, event.len, 1)
	// No token, no generation: nothing distinguishes a live feed from a freed
	// one at the type level. That absence is the finding.
}
