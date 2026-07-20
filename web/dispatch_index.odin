package web
// uruquim:file application

// WP29 — the route index. A segment-keyed radix tree, chosen from measurement.
//
// WP28 measured seven representations across four shapes and four
// cardinalities (`planning/router-shootout.md`). This is `radix_idx`: nodes in
// a flat array, children by index, static child tried before the parametric one
// at every level. At 5,000 mixed routes it matched in ~1.4 us against the flat
// scan's ~191 us, and — the property that actually mattered — it is FLAT from
// 5 routes to 5,000 while every linear variant grows with the table.
//
// WHY INDICES AND NOT POINTERS. The timing did not choose: `radix_ptr` and
// `radix_idx` are the same algorithm in two layouts and their medians differed
// by less than either measurement's own spread. The choice was made on
// ownership. A `^Node` held across an `append` to the node array dangles the
// moment the array reallocates — the same class of defect as P8, which the
// middleware pool's `chain_start`/`chain_len` index pairs already exist to make
// impossible (spec §2.2). This file inherits that discipline: `index_node`
// returns an int, and every parent is re-indexed AFTER its child exists.
//
// WHY A MAP INSIDE A NODE. Measured too, and against the alternative the idiom
// guide's warning would have favoured. A sorted array with binary search lost
// in eight cells out of eight, by 19% to 84% — including on the deep, narrow
// shape where fan-out is ten and binary search should have won. The guide's
// rule about maps in hot dispatch is not overturned, it is SCOPED: it is right
// about PER-REQUEST maps, which allocate. This map is built at registration and
// only read afterwards, and lookup allocates nothing.
//
// THE PERIMETER OF THE CLAIM, because the capacity ledger requires one: WP28
// measured MATCHERS IN ISOLATION. Against the WP26 end-to-end baseline, route
// matching is roughly 10% of dispatch p95 at 5,000 routes. This file makes that
// 10% nearly free. It does not make a request ten times faster, and no document
// may say that it does.
//
// THE FLAT ARRAY REMAINS THE SOURCE OF TRUTH. `a.private.routes` still owns
// every pattern, every handler and every chain index pair, and `mount` still
// copies into it. This tree is an INDEX over that array — it stores integers
// into it and nothing else — so registration, teardown and mounting keep the
// ownership they were specified with, and a bug here can lose a lookup but can
// never lose a pattern.

// ROUTE_NODE_NONE marks an absent child or an unregistered method.
@(private)
ROUTE_NODE_NONE :: -1

@(private)
Route_Node :: struct {
	// Static children, keyed by the segment text. The keys are VIEWS into
	// App-owned patterns, which outlive the index — both die at `destroy`.
	children:    map[string]int,

	// The single parametric child, or ROUTE_NODE_NONE. One, not many: a node
	// cannot usefully have two `:param` children, since they would match the
	// same segments and precedence between them would have to be invented.
	param_child: int,

	// The route index in `a.private.routes` for each method, or
	// ROUTE_NODE_NONE. A fixed array rather than a list because `Method` is a
	// closed six-member enum: it makes method lookup an index, makes
	// `allow_value` a walk of six slots, and gives first-registration-wins for
	// free.
	by_method:   [Method]int,
}

// Route_Index is lazy in the same sense the rest of the App is: an application
// that registers no route allocates nothing here.
@(private)
Route_Index :: struct {
	nodes: [dynamic]Route_Node,
}

// index_node appends one node and returns its index, or ROUTE_NODE_NONE if it
// could not be allocated.
//
// EVERY ALLOCATION HERE IS CHECKED, and that is not defensive habit — WP18
// Amendment 1 exists because discarding an `append` result is precisely how
// routes disappear in silence while the application still reports healthy.
// `mount` is fail-closed by contract, so an index that cannot grow must say so
// rather than leave a half-built tree that answers some paths and not others.
@(private)
index_node :: proc(a: ^App) -> int {
	node := Route_Node {
		children    = make(map[string]int, allocator = a.private.routes.allocator),
		param_child = ROUTE_NODE_NONE,
	}
	for m in Method {
		node.by_method[m] = ROUTE_NODE_NONE
	}
	appended, err := append(&a.private.route_index.nodes, node)
	if err != nil || appended != 1 {
		// The map is this procedure's own until the append succeeds, so it is
		// this procedure that must release it on the failing path.
		delete_map(node.children)
		return ROUTE_NODE_NONE
	}
	return len(a.private.route_index.nodes) - 1
}

// index_insert adds one already-registered route to the tree.
//
// It is called from `route_register` and from `mount`, immediately after the
// entry is appended, so the index is built at REGISTRATION and never during
// dispatch. That is deliberate: a tree built lazily at the first request would
// allocate inside that request, and claim C-5's perimeter — measured around
// `driver_run`/`driver_cleanup` — would start to include a one-off allocation
// that only the first caller pays.
//
// An invalid pattern is not indexed at all, which is exactly the existing
// contract: a registration this dispatcher cannot interpret must never win a
// match, and must never make a path look "known under another method" either.
// It reports whether the route reached the index. A caller that is fail-closed
// about allocation — `mount` — must reject the application when it did not.
@(private)
index_insert :: proc(a: ^App, entry_index: int) -> bool {
	entry := &a.private.routes[entry_index]
	if !entry.valid {
		// Not indexed, and not a failure: an unusable registration is supposed
		// to be absent from the index.
		return true
	}
	if len(entry.pattern) == 0 || entry.pattern[0] != '/' {
		return true
	}

	if len(a.private.route_index.nodes) == 0 {
		if index_node(a) == ROUTE_NODE_NONE {
			return false
		}
	}

	cursor := 1
	node := 0
	for {
		segment, ok := segment_next(entry.pattern, &cursor)
		if !ok {
			break
		}

		if len(segment) > 0 && segment[0] == ':' {
			if a.private.route_index.nodes[node].param_child == ROUTE_NODE_NONE {
				// The child is created FIRST and the parent re-indexed after:
				// `index_node` appends, and an append may reallocate the array
				// that `a.private.route_index.nodes[node]` addresses.
				child := index_node(a)
				if child == ROUTE_NODE_NONE {
					return false
				}
				a.private.route_index.nodes[node].param_child = child
			}
			node = a.private.route_index.nodes[node].param_child
			continue
		}

		child, found := a.private.route_index.nodes[node].children[segment]
		if !found {
			child = index_node(a)
			if child == ROUTE_NODE_NONE {
				return false
			}
			a.private.route_index.nodes[node].children[segment] = child
			// A map insert reports no error, so the insert is VERIFIED. Under a
			// failing allocator it silently does nothing, and an unverified
			// insert would leave a node unreachable — the same silent-loss
			// shape WP18 Amendment 1 was written about.
			if _, stored := a.private.route_index.nodes[node].children[segment]; !stored {
				return false
			}
		}
		node = child
	}

	// FIRST REGISTRATION WINS, which is what the flat scan did: it returned the
	// first entry in table order that matched, so a duplicate method+pattern
	// never reached dispatch. Overwriting here would silently change that.
	if a.private.route_index.nodes[node].by_method[entry.method] == ROUTE_NODE_NONE {
		a.private.route_index.nodes[node].by_method[entry.method] = entry_index
	}
	return true
}

// index_destroy frees the tree exactly once and returns it to its zero state.
//
// One array and one map per node — and the maps are the only owned storage,
// since every key is a view into a pattern the flat table owns and frees.
@(private)
index_destroy :: proc(a: ^App) {
	if a.private.route_index.nodes == nil {
		return
	}
	// `delete_map` / `delete_dynamic_array` rather than the `delete` builtin:
	// inside `package web` that name is the HTTP verb `web.delete`. The rest of
	// the package already spells it this way.
	for &node in a.private.route_index.nodes {
		delete_map(node.children)
	}
	delete_dynamic_array(a.private.route_index.nodes)
	a.private.route_index.nodes = nil
}

// index_walk finds the route for one method and path.
//
// STATIC BEFORE PARAMETRIC, at every level, and the fall-back is the part that
// is easy to get wrong: a static branch that matches deeper segments and then
// dead-ends must yield to the parametric branch rather than declaring a miss.
// The recursion below does that by trying the static child first and continuing
// when it returns `found = false`.
//
// The cursor is passed BY VALUE, so each branch resumes from its own position
// and no segment array is materialised. There is therefore no depth limit and
// no per-request allocation — a path of any length is walked in place.
@(private)
index_walk :: proc(
	a: ^App,
	node: int,
	path: string,
	cursor: int,
	method: Method,
	param_name: string,
	param_value: string,
) -> (
	entry: int,
	name: string,
	value: string,
	found: bool,
) {
	local := cursor
	segment, ok := segment_next(path, &local)
	if !ok {
		hit := a.private.route_index.nodes[node].by_method[method]
		if hit != ROUTE_NODE_NONE {
			return hit, param_name, param_value, true
		}
		return ROUTE_NODE_NONE, "", "", false
	}

	if child, has := a.private.route_index.nodes[node].children[segment]; has {
		if e, n, v, f := index_walk(a, child, path, local, method, param_name, param_value); f {
			return e, n, v, true
		}
	}

	pc := a.private.route_index.nodes[node].param_child
	if pc != ROUTE_NODE_NONE && len(segment) > 0 {
		// The parameter's NAME lives on the pattern and the VALUE on the path;
		// neither is copied, and neither survives the request (G-05).
		if e, n, v, f := index_walk(a, pc, path, local, method, param_name, segment); f {
			_ = n
			_ = v
			return e, index_param_name(a, e), segment, true
		}
	}

	return ROUTE_NODE_NONE, "", "", false
}

// index_param_name recovers the parameter's declared name from the winning
// entry's own pattern.
//
// Storing it on the node would duplicate a string the pattern already owns, and
// two copies of a name is two chances for them to disagree. The pattern is
// walked once, only on a parametric hit, and the result is a view into it.
@(private)
index_param_name :: proc(a: ^App, entry_index: int) -> string {
	pattern := a.private.routes[entry_index].pattern
	cursor := 1
	for {
		segment, ok := segment_next(pattern, &cursor)
		if !ok {
			return ""
		}
		if len(segment) > 0 && segment[0] == ':' {
			return segment[1:]
		}
	}
}

// index_collect unions the methods registered at every node a path can reach.
//
// `allow_value` needs the whole set, not the first hit, so this explores BOTH
// the static and the parametric branch instead of stopping at the first
// terminal — a path can be served by a static route under GET and a parametric
// one under POST, and the `Allow` header must name both.
@(private)
index_collect :: proc(a: ^App, node: int, path: string, cursor: int, methods: ^bit_set[Method]) {
	local := cursor
	segment, ok := segment_next(path, &local)
	if !ok {
		for m in Method {
			if a.private.route_index.nodes[node].by_method[m] != ROUTE_NODE_NONE {
				methods^ += {m}
			}
		}
		return
	}

	if child, has := a.private.route_index.nodes[node].children[segment]; has {
		index_collect(a, child, path, local, methods)
	}
	pc := a.private.route_index.nodes[node].param_child
	if pc != ROUTE_NODE_NONE && len(segment) > 0 {
		index_collect(a, pc, path, local, methods)
	}
}
