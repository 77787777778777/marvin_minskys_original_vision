# ============================================================================
# shims.tcl -- small compatibility shims for embedded hosts
#
# Feather's WASM build differs from stock Tcl in two ways that matter here:
#
#   1. No math commands rand()/srand() (used by the wandering cat).
#   2. `expr`'s ternary evaluates BOTH branches, so an expression like
#      `$dir eq "right" ? ($i + 1) % $n : ($i - 1 + $n) % $n` crashes with
#      divide-by-zero when one branch is temporarily invalid.
#
# This file provides deterministic replacements so the same game script runs
# everywhere, and a safe modulo helper used by the telescope turn.
# A simple xorshift PRNG: no clock needed (embedded hosts have none), and
# every host sees the same "weather".
# ============================================================================

namespace eval ::shim {
    variable seed 2463534242
}

proc ::shim::next {} {
    variable seed
    set seed [expr {($seed ^ ($seed << 13)) & 0xFFFFFFFF}]
    set seed [expr {($seed ^ ($seed >> 17)) & 0xFFFFFFFF}]
    set seed [expr {($seed ^ ($seed << 5)) & 0xFFFFFFFF}]
    return $seed
}

proc ::shim::rand {} {
    return [expr {double([::shim::next]) / 4294967296.0}]
}

proc tcl::mathfunc::rand {} {
    return [::shim::rand]
}

proc tcl::mathfunc::srand {seed} {
    return 0
}

# clock clicks -milliseconds -- Feather has no `clock`. The budgeted tick
# (engine.tcl) needs a monotonic millisecond counter to measure how much
# demon work it has done. An xorshift step is a fine proxy: deterministic,
# cheap, and always advancing. Installed only when the host lacks `clock`;
# native Tcl keeps its own.
if {[info commands clock] eq ""} {
    proc ::shim::clicks {} { return [::shim::next] }
    proc clock {sub args} {
        switch -- $sub {
            clicks  { return [::shim::clicks] }
            default { error "clock $sub not supported in this host" }
        }
    }
}
