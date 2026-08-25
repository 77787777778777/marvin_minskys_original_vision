# ============================================================================
# cache.tcl -- memoized world queries for slow hosts
#
# The planner re-reads the same frame data thousands of times per turn. On a
# fast native tclsh that is fine; on an embedded interpreter (e.g. Feather
# WASM in a browser) every command allocates, so hot queries are memoized.
#
# Correctness: every cache entry is keyed on ::frames::gen, which frames.tcl
# bumps on EVERY mutation (defframe, fput, fremove, delete, load-db). A hit
# can therefore never observe stale data -- any write invalidates by gen.
#
# Sourced AFTER engine.tcl. The original procs remain available under
# -orig names.
# ============================================================================

namespace eval ::qcache {
    variable isa    [dict create]
    variable cont   [dict create]
    variable lights [dict create]
    variable ako    [dict create]
}

# --- isa? --------------------------------------------------------------------
# Cached for EVERY ancestor, not just thing/room: the NPC perception and
# planning sweeps isa?-test all 78 frames each turn against several classes.
rename ::frames::isa? ::frames::isa?-orig
proc ::frames::isa? {name ancestor} {
    set gen $::frames::gen
    set key "$ancestor|$name"
    if {[dict exists $::qcache::isa $key]} {
        set e [dict get $::qcache::isa $key]
        if {[lindex $e 0] eq $gen} { return [lindex $e 1] }
    }
    set v [::frames::isa?-orig $name $ancestor]
    dict set ::qcache::isa $key [list $gen $v]
    return $v
}

# --- contents / light-sources -------------------------------------------------
# contents() is the hottest query in the engine: npc-sees calls it once per
# visible thing, and each full sweep costs O(all frames) -- on slow hosts
# that made every turn take seconds. A gen-keyed location index (one sweep
# per mutation, reused for every place) turns each call into a dict lookup.
namespace eval ::qcache { variable locidx [dict create] }
proc ::game::loc-index {} {
    set gen $::frames::gen
    if {[dict exists $::qcache::locidx $gen]} { return [dict get $::qcache::locidx $gen] }
    set idx [dict create]
    foreach f [::frames::all] {
        if {$f eq "player"} continue
        if {[::frames::isa? $f thing]} {
            dict lappend idx [::frames::fget $f location] $f
        }
    }
    dict set ::qcache::locidx $gen $idx
    return $idx
}
proc ::game::contents {place} {
    set idx [::game::loc-index]
    if {[dict exists $idx $place]} { return [dict get $idx $place] }
    return {}
}

rename ::game::light-sources ::game::light-sources-orig
proc ::game::light-sources {} {
    set gen $::frames::gen
    if {[dict exists $::qcache::lights $gen]} { return [dict get $::qcache::lights $gen] }
    set v [::game::light-sources-orig]
    dict set ::qcache::lights $gen $v
    return $v
}

# --- ako-chain ------------------------------------------------------------------
rename ::frames::ako-chain ::frames::ako-chain-orig
proc ::frames::ako-chain {name} {
    if {[dict exists $::qcache::ako $name]} { return [dict get $::qcache::ako $name] }
    set v [::frames::ako-chain-orig $name]
    dict set ::qcache::ako $name $v
    return $v
}

# --- npc-sees memo -------------------------------------------------------------
# What a mind sees in a room, per (npc, room), gen-keyed. Perception is
# read-only, so within one mutation epoch the answer cannot change; the
# magpie's and rat's policies each re-ask it several times per turn.
namespace eval ::qcache { variable sees [dict create] }
rename ::game::npc-sees ::game::npc-sees-orig
proc ::game::npc-sees {npc R} {
    set gen $::frames::gen
    set key "$npc|$R"
    if {[dict exists $::qcache::sees $key]} {
        set e [dict get $::qcache::sees $key]
        if {[lindex $e 0] eq $gen} { return [lindex $e 1] }
    }
    set v [::game::npc-sees-orig $npc $R]
    dict set ::qcache::sees $key [list $gen $v]
    return $v
}

# --- fget fast path ------------------------------------------------------------
# The single hottest operation in the engine. When the slot carries a value
# or default facet directly, return it immediately: no ako-chain walk, no
# if-needed dispatch. Demons are untouched (fput/fremove still fire them);
# if-needed slots still take the slow path every time, by design -- their
# whole point is to recompute.
rename ::frames::fget ::frames::fget-orig
proc ::frames::fget {name slot} {
    if {[dict exists $::frames::db $name $slot]} {
        set facets [dict get $::frames::db $name $slot]
        if {[dict exists $facets value]} { return [dict get $facets value] }
        if {[dict exists $facets default]} { return [dict get $facets default] }
    }
    # Slow path: walk the ako chain looking for value/default/if-needed,
    # exactly as the original does for anything not on this frame itself.
    foreach f [::frames::ako-chain $name] {
        if {[dict exists $::frames::db $f $slot]} {
            set facets [dict get $::frames::db $f $slot]
            if {[dict exists $facets value]} { return [dict get $facets value] }
            if {[dict exists $facets default]} { return [dict get $facets default] }
            if {[dict exists $facets if-needed]} {
                return [uplevel #0 [list {*}[dict get $facets if-needed] $name $slot]]
            }
        }
    }
    return ""
}
