#!/usr/bin/env tclsh
# ============================================================================
# adventure.tcl -- entry point
#
#   tclsh adventure.tcl
#
# Layers:
#   frames.tcl  the knowledge representation (Minsky frames)
#   engine.tcl  the adventure engine (matching, demons, verbs, main loop)
#   world.tcl   the demonstration world (stereotypes and individuals)
# ============================================================================

set dir [file dirname [file normalize [info script]]]
source [file join $dir frames.tcl]
source [file join $dir engine.tcl]

# Optional query cache for slow hosts (sourced if present, before world.tcl
# so world definition happens after the cache wrappers exist).
if {[file exists [file join $dir cache.tcl]]} {
    source [file join $dir cache.tcl]
}

# Optional compatibility shims for embedded hosts (no rand(), etc.).
if {[file exists [file join $dir shims.tcl]]} {
    source [file join $dir shims.tcl]
}

source [file join $dir world.tcl]

::game::start
