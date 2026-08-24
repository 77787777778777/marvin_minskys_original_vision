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
rename ::game::contents ::game::contents-orig
proc ::game::contents {place} {
    set gen $::frames::gen
    set key "c|$place"
    if {[dict exists $::qcache::cont $key]} {
        set e [dict get $::qcache::cont $key]
        if {[lindex $e 0] eq $gen} { return [lindex $e 1] }
    }
    set v [::game::contents-orig $place]
    dict set ::qcache::cont $key [list $gen $v]
    return $v
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
