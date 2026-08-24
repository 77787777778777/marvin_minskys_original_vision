# ============================================================================
# game.tcl -- web/Feather entry point
#
# Sourced after frames.tcl / engine.tcl / world.tcl by the host. Provides:
#   game_init          -> boots the world, returns the opening text
#   game_cmd <line>    -> runs one player turn, returns the turn's text
#
# The engine's ::game::emit is redirected to a buffer that game_cmd drains,
# so the whole turn comes back as one string.
# ============================================================================

namespace eval ::web {
    variable buf {}
}

proc ::web::emit {text} {
    variable buf
    lappend buf $text
}

proc ::web::drain {} {
    variable buf
    set out [join $buf "\n"]
    set buf {}
    return $out
}

# Redirect the engine's output seam into the buffer.
proc ::game::emit {text} {
    ::web::emit $text
}

# Persistence: the host registers host_save/host_load (Feather host commands
# cannot use ::-prefixed names), backed by localStorage in the browser.
# NB: Feather's `info commands` does NOT list host commands, so presence is
# tested by calling under catch, never by name lookup.
proc ::frames::db-write {path data} {
    if {[catch {host_save $data} err]} {
        error "saving is not available here"
    }
}

proc ::frames::db-read {path} {
    if {[catch {set data [host_load]} err]} {
        error "there is no saved game to restore"
    }
    return $data
}

proc ::game::boot_web {} {
    ::game::boot
    return [::web::drain]
}

proc ::game::game_cmd {line} {
    if {[catch {::game::submit $line} err]} {
        ::game::say "Something went wrong inside a frame: $err"
    }
    set out [::web::drain]
    # The submit path ends with the promptless room text; hand back one
    # clean block. An empty turn still returns something printable.
    if {$out eq ""} { set out "..." }
    return $out
}
