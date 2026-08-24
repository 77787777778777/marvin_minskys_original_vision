# ============================================================================
# frames.tcl -- A Minsky frame system for Tcl
#
# Implements the core machinery of Marvin Minsky's "A Framework for
# Representing Knowledge" (MIT AI Memo 306, 1974):
#
#   * FRAMES        -- named structures representing stereotyped situations
#   * TERMINALS     -- slots that get filled with the particulars of an
#                      instance ("slots" below)
#   * FACETS        -- each slot carries several kinds of attached
#                      information:
#                        value      a confirmed assignment
#                        default    a "loosely bound" expectation, easily
#                                   displaced by real data
#                        if-needed  a procedure run to compute a value on
#                                   demand (procedural attachment)
#                        if-added   a demon fired when a value is assigned
#                        if-removed a demon fired when a value is retracted
#                        required / question / kind -- markers and
#                                   conditions a filler must satisfy
#   * AKO HIERARCHY -- frames inherit defaults and demons from more
#                      general frames ("a-kind-of"), so knowledge is
#                      stored once at the most general level that holds.
#
# Storage model: one big dict
#     db :: frameName -> ( slotName -> ( facetName -> value ) )
# ============================================================================

namespace eval ::frames {
    variable db [dict create]
    variable gen 0 ;# bumped on every mutation; used by hosts to cache derived queries
}

# ----------------------------------------------------------------------------
# defframe -- define a new frame, or extend an existing one.
#
#   frames::defframe lamp {
#       ako   {value thing}
#       lit   {default 0  if-added ::game::on-lamp}
#       short {value "brass lamp"}
#   }
# ----------------------------------------------------------------------------
proc ::frames::bump {} {
    variable gen
    incr gen
}

proc ::frames::defframe {name spec} {
    variable db
    bump
    set frame [expr {[dict exists $db $name] ? [dict get $db $name] : [dict create]}]
    foreach {slot facets} $spec {
        foreach {facet val} $facets {
            dict set frame $slot $facet $val
        }
    }
    dict set db $name $frame
    return $name
}

proc ::frames::exists {name} {
    variable db
    dict exists $db $name
}

proc ::frames::all {} {
    variable db
    dict keys $db
}

proc ::frames::delete {name} {
    variable db
    bump
    dict unset db $name
}

# ----------------------------------------------------------------------------
# ako-chain -- the frame followed by its chain of more general ancestors.
# This is the path along which defaults and demons are inherited.
# ----------------------------------------------------------------------------
proc ::frames::ako-chain {name} {
    variable db
    set chain {}
    set f $name
    while {$f ne "" && [dict exists $db $f] && [lsearch -exact $chain $f] < 0} {
        lappend chain $f
        set f [expr {[dict exists $db $f ako value]
                        ? [dict get $db $f ako value] : ""}]
    }
    return $chain
}

proc ::frames::isa? {name ancestor} {
    expr {[lsearch -exact [ako-chain $name] $ancestor] >= 0}
}

# ----------------------------------------------------------------------------
# facet -- fetch a raw facet of a slot, searching up the AKO hierarchy.
# Used for markers like `required`, `question`, and `kind`.
# ----------------------------------------------------------------------------
proc ::frames::facet {name slot facet} {
    variable db
    foreach f [ako-chain $name] {
        if {[dict exists $db $f $slot $facet]} {
            return [dict get $db $f $slot $facet]
        }
    }
    return ""
}

# Does any frame in the AKO chain declare this slot at all?
proc ::frames::has-slot {name slot} {
    variable db
    foreach f [ako-chain $name] {
        if {[dict exists $db $f $slot]} { return 1 }
    }
    return 0
}

# ----------------------------------------------------------------------------
# fget -- retrieve a slot value. Within each frame, Minsky's order of
# preference applies:
#
#   1. an explicit VALUE      (a confirmed terminal assignment)
#   2. a DEFAULT              (a weakly bound expectation)
#   3. an IF-NEEDED procedure (compute the answer on demand)
#
# and the search climbs the AKO chain from most to least specific, so the
# knowledge of a nearer stereotype always wins over a more distant one
# (a container's computed description beats the generic thing's default).
#
# If nothing applies, returns the empty string.
# ----------------------------------------------------------------------------
proc ::frames::fget {name slot} {
    variable db
    foreach f [ako-chain $name] {
        if {[dict exists $db $f $slot value]} {
            return [dict get $db $f $slot value]
        }
        if {[dict exists $db $f $slot default]} {
            return [dict get $db $f $slot default]
        }
        if {[dict exists $db $f $slot if-needed]} {
            set demon [dict get $db $f $slot if-needed]
            return [uplevel #0 [list {*}$demon $name $slot]]
        }
    }
    return ""
}

# ----------------------------------------------------------------------------
# fput -- assign a value to a terminal, firing the nearest IF-ADDED demon.
# Demons receive: frameName slotName newValue
# ----------------------------------------------------------------------------
proc ::frames::fput {name slot value} {
    variable db
    bump
    dict set db $name $slot value $value
    foreach f [ako-chain $name] {
        if {[dict exists $db $f $slot if-added]} {
            set demon [dict get $db $f $slot if-added]
            uplevel #0 [list {*}$demon $name $slot $value]
            break
        }
    }
    return $value
}

# ----------------------------------------------------------------------------
# fremove -- retract a terminal assignment, firing the nearest IF-REMOVED
# demon. The slot's defaults and if-needed procedures become visible again,
# which is exactly Minsky's picture of expectations resurfacing when a
# confirmed observation is withdrawn.
# ----------------------------------------------------------------------------
proc ::frames::fremove {name slot} {
    variable db
    if {![dict exists $db $name $slot value]} { return }
    bump
    set old [dict get $db $name $slot value]
    dict unset db $name $slot value
    foreach f [ako-chain $name] {
        if {[dict exists $db $f $slot if-removed]} {
            set demon [dict get $db $f $slot if-removed]
            uplevel #0 [list {*}$demon $name $slot $old]
            break
        }
    }
    return $old
}

# ----------------------------------------------------------------------------
# instantiate -- stamp out an individual from a stereotype. The new frame
# is AKO its prototype, so every unfilled terminal falls back on the
# prototype's defaults and attached procedures.
# ----------------------------------------------------------------------------
proc ::frames::instantiate {name proto {spec {}}} {
    defframe $name [concat [list ako [list value $proto]] $spec]
}

# ----------------------------------------------------------------------------
# save-db / load-db -- the entire state of the world is one dict, so
# persistence is trivial: write the frame database out, read it back in.
# ----------------------------------------------------------------------------
proc ::frames::save-db {path} {
    variable db
    # Hosts can override ::frames::db-write / ::frames::db-read to store the
    # serialized world somewhere other than a plain file (e.g. localStorage).
    if {[info commands ::frames::db-write] ne ""} {
        ::frames::db-write $path $db
        return
    }
    set f [open $path w]
    puts -nonewline $f $db
    close $f
}

proc ::frames::load-db {path} {
    variable db
    bump
    if {[info commands ::frames::db-read] ne ""} {
        set db [::frames::db-read $path]
        # Normalize the freshly-loaded string into a real dict NOW: one parse
        # up front instead of a full string re-parse on every later dict op
        # (a large win on hosts where list parsing is expensive).
        set db [dict create {*}$db]
        return
    }
    set f [open $path r]
    set db [read $f]
    close $f
}
