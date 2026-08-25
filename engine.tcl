# ============================================================================
# engine.tcl -- the adventure engine built on the frame system
#
# The engine treats the entire game as frame manipulation:
#
#   * Every VERB is an action frame whose terminals carry markers: a `kind`
#     condition the filler must satisfy, a `required` flag, a `question` to
#     ask when an expected terminal stays empty, a `literal` flag for
#     terminals filled with a raw word rather than a matched thing (topics
#     of conversation, spoken words), and optionally an `if-needed`
#     procedure proposing a default filler.
#
#   * Parsing is MATCHING: the engine instantiates the action frame and
#     fills its terminals from the words typed and the things in view.
#     Multi-word names are matched by the longest run of tokens; when two
#     candidates match equally well, the frame asks which was meant.
#     Pronouns resolve against a FOCUS terminal -- the frame currently
#     occupying the player's attention. Unconfirmed expectations turn
#     into questions back to the player.
#
#   * When an action's preconditions fail, the failure carries a pointer
#     along a SIMILARITY LINK to a neighbouring action frame that could
#     transform the situation ("open" fails on a locked chest and points
#     at "unlock").
#
#   * Moving between rooms is a FRAME TRANSFORMATION: assigning the
#     player's `location` terminal fires a demon that swaps the current
#     room frame and re-describes the scene.
#
#   * SCENARIO frames implement Minsky's scripts: a stereotyped sequence
#     of events with an expectation of what comes next, narration as each
#     expectation is confirmed, and a complaint-and-reset when events
#     arrive out of order.
#
#   * NPCs are frames with discourse terminals: a `topics` dict, a
#     `greet`, a `default-reply`, a `wants` expectation that "give"
#     can satisfy, and demons that fire when they are satisfied.
#
#   * Each turn, EACH-TURN demons fire on any frame that declares one --
#     this is how the cat wanders.
# ============================================================================

namespace eval ::game {
    variable here     ""
    variable running  1
    variable seq      0
    variable savefile "framework.sav"
    variable pending  {} ;# a plan awaiting the player's yes/no confirmation
    variable teach     0  ;# has the difference-network aside been shown yet?
    variable asked     {} ;# topics already discussed with anyone (see `ask`)
    variable glossary_terms {} ;# Minsky vocabulary words (set by do-frame)
    variable planroom   "" ;# room the planner is reasoning about (here, or a remote goal room)
    variable planremote 0  ;# 1 when planning at a distance: only carried tools are usable
    variable quiet       0  ;# suppress full room descriptions while a plan is being carried out
    variable actor       player ;# whom the planner is currently reasoning for (player, or an NPC)
    variable usebeliefs  0  ;# 1 = resolve object locations through `beliefs` (a fallible mind), not the truth
    variable beliefs     {} ;# the belief map in force while usebeliefs is set
    variable noise    {the a an at with to onto in on of about for as
                       please around some my that this using}
    variable pronouns {it him her them}
    variable dirmap   [dict create \
        n north  north north  s south  south south \
        e east   east east    w west   west west \
        u up     up up        d down   down down]
}

# ---------------------------------------------------------------- output ---
# Output goes through ::game::emit so hosts can redirect it (the terminal
# build defaults to puts; the web build registers its own emitter).
proc ::game::emit {text} {
    puts $text
}

proc ::game::say {text} {
    if {$text eq ""} { emit "" ; return }
    set line ""
    foreach w [split $text] {
        if {$w eq ""} continue
        if {$line ne "" && [string length "$line $w"] > 72} {
            emit $line
            set line $w
        } else {
            set line [expr {$line eq "" ? $w : "$line $w"}]
        }
    }
    if {$line ne ""} { emit $line }
}

# "a brass lamp" / "an iron key"
proc ::game::an {frame} {
    set s [frames::fget $frame short]
    set art [expr {[string first [string index $s 0] "aeiou"] >= 0 ? "an" : "a"}]
    return "$art $s"
}

proc ::game::the {frame} {
    set s [frames::fget $frame short]
    # Proper/already-articled names (rooms like "The Cellar", "yourself")
    # are used as-is.
    if {[string match {[A-Z]*} $s] || $s eq "yourself"} { return $s }
    return "the $s"
}

# --------------------------------------------------------- world queries ---
proc ::game::contents {place} {
    set out {}
    foreach f [frames::all] {
        if {$f eq "player"} continue
        if {[frames::isa? $f thing] && [frames::fget $f location] eq $place} {
            lappend out $f
        }
    }
    return $out
}

proc ::game::lit-here {} {
    variable here
    if {[frames::fget $here lit] eq "1"} { return 1 }
    foreach f [concat [contents $here] [contents player]] {
        if {[frames::fget $f light-source] eq "1" && [frames::fget $f lit] eq "1"} {
            return 1
        }
    }
    return 0
}

# Things the player can currently refer to: carried items always, plus the
# room's contents (and the contents of open containers) when there is light.
proc ::game::visible {} {
    variable here
    set scope [contents player]
    if {[lit-here]} {
        set scope [concat $scope [contents $here]]
        # Things held by a creature standing here can be seen -- and seized
        # (so loot a thief is carrying can be taken back).
        foreach c [contents $here] {
            if {[frames::fget $c animate] eq "1"} {
                set scope [concat $scope [contents $c]]
            }
        }
    }
    set i 0
    while {$i < [llength $scope]} {
        set c [lindex $scope $i]
        if {[frames::fget $c container] eq "1" && [frames::fget $c open] eq "1"} {
            set scope [concat $scope [contents $c]]
        }
        incr i
    }
    return $scope
}

# ------------------------------------------------------------ the parser ---
proc ::game::tokenize {input} {
    variable noise
    set toks {}
    foreach t [split [string tolower $input]] {
        set t [string trim $t ".,!?\""]
        if {$t ne "" && [lsearch -exact $noise $t] < 0} { lappend toks $t }
    }
    return $toks
}

proc ::game::find-action {verb} {
    foreach f [frames::all] {
        if {[frames::isa? $f action] && $f ne "action"} {
            if {[lsearch -exact [frames::fget $f verbs] $verb] >= 0} { return $f }
        }
    }
    return ""
}

# match-run -- starting at token position i, find the thing(s) in scope
# matching the longest run of consecutive tokens, so "brass lamp" prefers
# a frame matching both words over one matching only "brass". Returns
# {candidateList runLength}. A tie at the best length means the words
# were genuinely ambiguous.
proc ::game::match-run {tokens i scope used} {
    set bestLen 0
    set best {}
    foreach f $scope {
        if {[lsearch -exact $used $f] >= 0} continue
        set names [frames::fget $f names]
        if {![llength $names]} continue
        set len 0
        for {set j $i} {$j < [llength $tokens]} {incr j} {
            if {[lsearch -exact $names [lindex $tokens $j]] >= 0} {
                incr len
            } else {
                break
            }
        }
        if {$len > $bestLen} {
            set bestLen $len
            set best [list $f]
        } elseif {$len > 0 && $len == $bestLen && [lsearch -exact $best $f] < 0} {
            lappend best $f
        }
    }
    return [list $best $bestLen]
}

# execute -- the heart of the engine: select an action frame, instantiate
# it, fill its terminals by matching, fall back on defaults, complain about
# unmet expectations, check preconditions, then perform.
proc ::game::execute {input} {
    variable dirmap
    variable pronouns
    variable pending
    variable seq

    # --- a plan may be waiting for confirmation ----------------------------
    set firstword [lindex [split [string tolower [string trim $input]]] 0]
    if {[dict size $pending] > 0} {
        if {[lsearch -exact {yes y yeah yep sure ok okay aye affirmative please} $firstword] >= 0} {
            set p $pending
            set pending {}
            run-plan $p
            return
        } elseif {[lsearch -exact {no n nope cancel stop nevermind nvm forget} $firstword] >= 0} {
            set pending {}
            say "All right -- I'll leave it."
            return
        } else {
            # Anything else abandons the plan and is treated as a fresh command.
            set pending {}
        }
    } elseif {[lsearch -exact {yes y no n yeah nope sure aye} $firstword] >= 0} {
        say "There's nothing to confirm right now."
        return
    }

    set toks [tokenize $input]
    if {![llength $toks]} { return }

    # A bare direction is shorthand for "go <direction>".
    set verb [lindex $toks 0]
    if {[dict exists $dirmap $verb]} {
        set toks [list go $verb]
        set verb go
    }

    set action [find-action $verb]
    if {$action eq ""} {
        # Glossary shortcut: a bare Minsky term ("default", "demon") is
        # shorthand for "frame <term>".
        if {[lsearch -exact $::game::glossary_terms $verb] >= 0} {
            set toks [concat frame $toks]
            set action frame
            set verb frame
        } else {
            say "I don't know how to \"$verb\"."
            return
        }
    }

    # --- instantiate the stereotype ----------------------------------------
    set inst "${action}#[incr seq]"
    frames::instantiate $inst $action
    set nouns [lrange $toks 1 end]
    frames::fput $inst words $nouns

    # --- try to fill each declared terminal --------------------------------
    set scope [visible]
    set terms [frames::fget $action terminals]
    if {$terms eq ""} { set terms {object second} }
    set used {}
    set wideObj 0

    foreach term $terms {
        if {![frames::has-slot $action $term]} { continue }
        set literal [expr {[frames::facet $action $term literal] eq "1"}]
        set hadNouns [llength $nouns]
        set thing ""

        if {$literal} {
            # A terminal filled by a raw word: a topic, a spoken word.
            if {[llength $nouns]} {
                set thing [lindex $nouns 0]
                set nouns [lrange $nouns 1 end]
            }
        } else {
            # Scan the remaining words for the first thing in view.
            for {set i 0} {$i < [llength $nouns]} {incr i} {
                set tok [lindex $nouns $i]

                # Pronouns resolve against the focus terminal: the frame
                # currently occupying the player's attention.
                if {[lsearch -exact $pronouns $tok] >= 0} {
                    set foc [frames::fget player focus]
                    if {$foc ne "" && [lsearch -exact $scope $foc] >= 0
                                   && [lsearch -exact $used $foc] < 0} {
                        set thing $foc
                        set nouns [lreplace $nouns $i $i]
                        break
                    }
                    continue
                }

                lassign [match-run $nouns $i $scope $used] cands len
                if {$len > 0} {
                    if {[llength $cands] > 1} {
                        # Two frames matched equally well: the system asks
                        # which stereotype it should be instantiating.
                        set opts {}
                        foreach c $cands { lappend opts [the $c] }
                        say "Which do you mean: [join $opts { or }]?"
                        frames::delete $inst
                        return
                    }
                    set thing [lindex $cands 0]
                    set nouns [lreplace $nouns $i [expr {$i + $len - 1}]]
                    break
                }
            }
            # No word filled the terminal: consult defaults and if-needed
            # procedures inherited from the action frame.
            if {$thing eq ""} {
                set thing [frames::fget $inst $term]
            }
        }

        # Still empty: an unconfirmed expectation. The frame complains --
        # unless the thing named is present but merely out of reach (in the
        # dark, or inside a closed container), in which case we accept it
        # provisionally and let the planner work out how to get at it.
        if {$thing eq ""} {
            if {[frames::facet $action $term required] eq "1"} {
                if {$hadNouns && !$literal} {
                    set w [wide-match [frames::fget $inst words] $used]
                    if {$w eq ""} {
                        set w [global-match [frames::fget $inst words] $used]
                    }
                    if {$w ne ""} {
                        set thing $w
                        set wideObj 1
                    }
                }
                if {$thing eq ""} {
                    if {$hadNouns && !$literal} {
                        say "You don't see any \"[lindex $nouns 0]\" here."
                    } else {
                        say [frames::facet $action $term question]
                    }
                    frames::delete $inst
                    return
                }
            } else {
                continue
            }
        }

        # The marker condition: a filler must be the right KIND of thing,
        # either by ancestry (AKO) or by carrying the property itself.
        if {!$literal} {
            set kind [frames::facet $action $term kind]
            if {$kind ne "" && ![frames::isa? $thing $kind]
                            && [frames::fget $thing $kind] ne "1"} {
                say "You can't $verb [the $thing]."
                frames::delete $inst
                return
            }
        }

        frames::fput $inst $term $thing
        lappend used $thing
        if {$term eq "object" && !$literal} {
            frames::fput player focus $thing
        }
    }

    # --- can the situation be transformed to make this possible? -----------
    # Walk the difference network: if the action cannot be performed as
    # things stand, try to assemble the chain of operators that would make
    # it possible, and offer to carry it out. Each operator is itself an
    # action frame whose own preconditions are resolved recursively.
    set pobj    [frames::fget $inst object]
    set psecond [frames::fget $inst second]
    set plan [try-plan $action $pobj $psecond]
    if {$plan ne ""} {
        offer-plan $plan
        frames::delete $inst
        return
    }
    if {$wideObj} {
        # An omnipresent frame (the curator, the house's hint system)
        # answers from anywhere -- ask/talk reach him across the whole
        # house. Everything else named-but-elsewhere stays out of reach.
        if {[frames::fget $pobj omnipresent] ne "1" || ![frames::isa? $pobj person]} {
            say "You can't get at that from here."
            frames::delete $inst
            return
        }
    }

    # --- preconditions, with similarity links on failure -------------------
    set chk [frames::fget $action check]
    if {$chk ne ""} {
        set res [uplevel #0 [list {*}$chk $inst]]
        if {[lindex $res 0] eq "fail"} {
            say [lindex $res 1]
            set sim [lindex $res 2]
            if {$sim ne "" && [frames::exists $sim]} {
                say "(Perhaps \"[lindex [frames::fget $sim verbs] 0]\" would transform this situation.)"
            }
            frames::delete $inst
            return
        }
    }

    # --- perform ------------------------------------------------------------
    uplevel #0 [list {*}[frames::fget $action perform] $inst]
    frames::delete $inst
}

# tick -- fire the each-turn demon of every frame that declares one.
#
# On slow hosts (Feather WASM in a browser) a full pass over every demon
# blocks the player's next command for many seconds. So the work is
# BUDGETED: each tick spends at most ::game::tick-budget-ms of measured
# time on demons, then remembers where it stopped (::sched::cursor) and
# resumes there on the next tick. The world keeps turning -- one slice of
# NPC attention per turn -- while the player stays responsive. Fast hosts
# finish the whole rotation within budget and never notice.
namespace eval ::sched {
    variable order  {}  ;# demons to run, discovered once
    variable cursor {}  ;# resume point after a budget expiry
    variable used   0   ;# ms spent this tick
    variable budget_ms 150
}
proc ::game::tick {} {
    set t0 [clock clicks -milliseconds]
    if {[llength $::sched::order] == 0} {
        foreach f [frames::all] {
            if {[llength [frames::fget $f each-turn]]} { lappend ::sched::order $f }
        }
    }
    set n [llength $::sched::order]
    if {$n == 0} return
    set start 0
    if {$::sched::cursor ne ""} {
        set idx [lsearch -exact $::sched::order $::sched::cursor]
        if {$idx >= 0} { set start [expr {($idx + 1) % $n}] }
    }
    for {set k 0} {$k < $n} {incr k} {
        set idx [expr {($start + $k) % $n}]
        set f [lindex $::sched::order $idx]
        set demon [frames::fget $f each-turn]
        if {$demon eq ""} continue
        set d0 [clock clicks -milliseconds]
        uplevel #0 [list {*}$demon $f]
        incr ::sched::used [expr {[clock clicks -milliseconds] - $d0}]
        set next [lindex $::sched::order [expr {($idx + 1) % $n}]]
        if {$::sched::used >= $::sched::budget_ms} {
            set ::sched::cursor $next
            return
        }
    }
    set ::sched::cursor {}
}

# ===========================================================================
# SCENARIO FRAMES -- Minsky's scripts: stereotyped event sequences
# ===========================================================================
#
# A scenario frame holds an ordered list of expected events in `steps`,
# a `progress` pointer, narration for each confirmed expectation in
# `murmurs`, a `finale`, and an `order-hint` complaint. Feeding it an
# event either advances the expectation, or -- if the event belongs to
# the script but arrives out of order -- the half-built structure
# collapses and the frame explains what it was expecting.

frames::defframe scenario {
    steps      {default {}}
    progress   {default 0}
    done       {default 0}
    place      {default ""}
    murmurs    {default {}}
    finale     {default ""}
    order-hint {default "That is not the expected order of events."}
}

proc ::game::scenario-event {scn event} {
    variable here
    if {[frames::fget $scn done] eq "1"} { return }
    set place [frames::fget $scn place]
    if {$place ne "" && $here ne $place} { return }
    set steps [frames::fget $scn steps]
    set p [frames::fget $scn progress]
    if {$event eq [lindex $steps $p]} {
        frames::fput $scn progress [expr {$p + 1}]  ;# demon narrates/completes
    } elseif {[lsearch -exact $steps $event] >= 0} {
        if {$p > 0} { frames::fput $scn progress 0 } ;# demon narrates collapse
        say [frames::fget $scn order-hint]
    }
}

# Fire a thing's scenario hook, if it has one. A thing may declare
#     scenario-role {value {ritual bell}}
# meaning: this object, when activated, is the "bell" event of the
# "ritual" scenario.
proc ::game::scenario-hook {obj} {
    set role [frames::fget $obj scenario-role]
    if {[llength $role] == 2} {
        scenario-event [lindex $role 0] [lindex $role 1]
    }
}

# ===========================================================================
# DEMONS -- procedures attached to slots of world frames
# ===========================================================================

# Fired when the player's `location` terminal is reassigned: the frame
# transformation between rooms.
proc ::game::on-move {frame slot value} {
    variable quiet
    set ::game::here $value
    # A perspective is a framing of a particular scene; leaving the scene
    # drops the framing.
    frames::fput player viewpoint plain
    if {$quiet} {
        say "  ... to [frames::fget $value short]."
    } else {
        ::game::look-around
    }
}

# Fired when a lamp's or candle's `lit` terminal changes.
proc ::game::on-lamp {frame slot value} {
    if {$value eq "1"} {
        say "The [frames::fget $frame short] flickers to life, casting a warm glow."
    } else {
        say "The [frames::fget $frame short] goes dark."
    }
    # If the room itself sheds no light, the change is dramatic: re-view.
    if {[frames::fget $::game::here lit] ne "1"} { look-around }
}

# Fired when a container's `open` terminal changes: reveal the contents.
proc ::game::on-open-change {frame slot value} {
    if {$value ne "1"} { return }
    set inside {}
    foreach f [contents $frame] { lappend inside [an $f] }
    if {[llength $inside]} {
        say "Opening [the $frame] reveals [join $inside {, }]."
    }
}

# Fired when the player's `score` terminal is raised.
proc ::game::on-score {frame slot value} {
    set max [frames::fget player max-score]
    say "\[Your score has just gone up: $value of $max.\]"
    if {$value == $max} {
        say ""
        say "*** You have mastered the Framework. You win! ***"
        say "(You may keep exploring, or type \"quit\".)"
        # The win is no longer the end of learning: insights and deeds are
        # tracked separately, so a solver who never spoke to anyone can see
        # what talking would have taught them.
        set n [llength $::game::asked]
        if {$n < 6} {
            say "(Insights gathered: $n of 6. The house's archives hold more --"
            say "ask its people about things, even ordinary things.)"
        } else {
            say "(All six insights gathered. A mind, as Minsky said, meets each"
            say "new moment with a frame -- and you leave knowing whose.)"
        }
    }
}

proc ::game::add-score {} {
    frames::fput player score [expr {[frames::fget player score] + 1}]
}

# Fired by scenario `progress` changes: narrate confirmation, collapse,
# or completion of the script's expectations.
proc ::game::on-scenario-progress {frame slot value} {
    set total [llength [frames::fget $frame steps]]
    if {$value == 0} {
        say "The half-formed enchantment unravels with a sigh."
        return
    }
    if {$value < $total} {
        say [lindex [frames::fget $frame murmurs] [expr {$value - 1}]]
        return
    }
    frames::fput $frame done 1
    say [frames::fget $frame finale]
    set fin [frames::fget $frame on-complete]
    if {$fin ne ""} { uplevel #0 [list {*}$fin $frame] }
}

# Fired when an NPC's `satisfied` terminal is set by a welcome gift.
proc ::game::on-npc-satisfied {frame slot value} {
    if {$value ne "1"} { return }
    frames::fput $frame hostile 0
    say [frames::fget $frame satisfied-msg]
    add-score
}

# ---------------------------------------------------------------------------
# WHY -- the engine narrates its own reasoning.
#
# Minsky's paper is a theory of what happens inside the matcher; the `why`
# verb turns that inside out, so that at any moment you can ask the engine
# to show its work: which frame it selected for this place and how it came
# to be held, what defaults are quietly standing in for unobserved fact,
# and what the situation is currently asking of you (its open questions).
# Educationally this is the load-bearing verb: every mechanism the papers
# describe becomes inspectable state rather than a footnote.
# ---------------------------------------------------------------------------
proc ::game::do-why {inst} {
    variable here

    say "Why not? Here is the frame I am holding on this place:"
    set vp [frames::fget player viewpoint]
    if {$vp ne "" && $vp ne "plain"} {
        say "  You imposed [frames::fget $vp label] on it (you asked to view it that way)."
        say "  The scene underneath is unchanged; only the reading of its shared"
        say "  terminals differs. Type \"view plain\" to drop the framing."
    } else {
        say "  The $here frame was selected when you arrived: a room is a"
        say "  stereotype, and this room fills its terminals."
    }

    # Defaults standing in for unobserved fact -- Minsky's weakly-bound
    # expectations, shown as the guesses they are.
    set dflt {}
    foreach f [concat [list $here] [contents $here]] {
        if {![dict exists $::frames::db $f]} continue
        foreach slot [dict keys [dict get $::frames::db $f]] {
            if {![dict exists $::frames::db $f $slot default]} continue
            if {[dict exists $::frames::db $f $slot value]} continue ;# confirmed: no guess needed
            set v [dict get $::frames::db $f $slot default]
            if {$v eq "" || $v eq "0"} continue ;# silent defaults aren't interesting
            lappend dflt [list $f $slot $v]
        }
    }
    if {[llength $dflt]} {
        say ""
        say "Defaults standing in for things nobody has told me:"
        foreach entry $dflt {
            lassign $entry f slot v
            if {$v eq "1"} { set v "yes" }
            say "  [the $f]'s $slot -- assumed \"$v\" until you look properly."
        }
    }

    # Open questions: the terminals the current situation wants filled.
    # Minsky 2.8: the terminals of a frame ARE the questions about it.
    set q {}
    foreach p [contents $here] {
        if {[frames::isa? $p person] && ![frames::fget $p satisfied]} {
            set w [frames::fget $p wants]
            if {$w ne ""} { lappend q "What would please [the $p]? (It expects something.)" }
        }
    }
    foreach scn [frames::all] {
        if {![frames::isa? $scn scenario] || $scn eq "scenario"} continue
        if {[frames::fget $scn done] eq "1"} continue
        set pl [frames::fget $scn place]
        if {$pl ne "" && $pl ne $here} continue
        set steps [frames::fget $scn steps]
        set prog [frames::fget $scn progress]
        if {$prog == 0} {
            lappend q "[string totitle $scn]: nothing confirmed yet -- it awaits [lindex $steps 0]."
        } elseif {$prog < [llength $steps]} {
            lappend q "[string totitle $scn]: awaiting [lindex $steps $prog]."
        }
    }
    if {[llength $q]} {
        say ""
        say "Questions this situation is still asking:"
        foreach x $q { say "  - $x" }
    }
    say ""
    say "(Every line above is one of the paper's mechanisms, mid-run.)"
}

# If-needed procedure: compute a container's description from its state.
proc ::game::describe-container {frame slot} {
    set s [frames::fget $frame short]
    set state [expr {[frames::fget $frame open] eq "1" ? "open" : "closed"}]
    if {[frames::fget $frame locked] eq "1"} { append state " and locked" }
    set txt "The $s is $state."
    if {[frames::fget $frame open] eq "1"} {
        set inside {}
        foreach f [contents $frame] { lappend inside [an $f] }
        if {[llength $inside]} { append txt " Inside you see [join $inside {, }]." }
    }
    return $txt
}

# If-needed procedure for unlock's `second` terminal: the default
# assumption is "whatever key you happen to be carrying".
proc ::game::default-key {frame slot} {
    foreach f [::game::contents player] {
        if {[frames::isa? $f key]} { return $f }
    }
    return ""
}

# Each-turn demon: a creature that wanders its haunts. Movement is only
# narrated when it crosses the player's (lit) field of view.
proc ::game::wanderer {frame} {
    variable here
    if {rand() >= 0.25} { return }
    set loc [frames::fget $frame location]
    set haunts [frames::fget $frame haunts]
    set opts {}
    foreach {dir dest} [frames::fget $loc exits] {
        if {[lsearch -exact $haunts $dest] >= 0} { lappend opts $dest }
    }
    if {![llength $opts]} { return }
    set dest [lindex $opts [expr {int(rand() * [llength $opts])}]]
    set wasHere [expr {$loc eq $here}]
    frames::fput $frame location $dest
    if {[lit-here]} {
        if {$wasHere} {
            say "[string totitle [the $frame]] pads silently away."
        } elseif {$dest eq $here} {
            say "[string totitle [an $frame]] pads in and studies you with yellow eyes."
        }
    }
}

# If-needed: describe a scenery feature through the player's current
# perspective. The feature is a SINGLE frame -- one shared terminal -- but
# its meaning is supplied by whichever frame the observer has imposed. This
# is Minsky's point that the same terminal is read differently from
# different viewpoints (the duck and the rabbit are one set of lines).
proc ::game::describe-by-viewpoint {frame slot} {
    set vp [frames::fget player viewpoint]
    set notes [frames::fget $frame lens-notes]
    if {[dict exists $notes $vp]}    { return [dict get $notes $vp] }
    if {[dict exists $notes plain]}  { return [dict get $notes plain] }
    return "You see nothing special about it."
}

# If-needed: the turnable/viewer thing in the current room (so "turn left"
# and "peer" work without naming the telescope).
proc ::game::default-turnable {frame slot} {
    foreach f [::game::visible] {
        if {[frames::fget $f turnable] eq "1" || [frames::fget $f viewer] eq "1"} {
            return $f
        }
    }
    return ""
}

# ---------------------------------------------------------------------------
# The telescope as a FRAME-SYSTEM.
#
# The sky is represented as a ring of viewpoint frames (skyview), connected
# by transformations: turning the telescope moves you to an adjacent member
# of the system. Adjacent viewpoints SHARE a boundary star -- the same
# entity appearing in two frames of the system -- and it is exactly these
# shared terminals that knit the views into a stable whole. Here the four
# shared stars are, fittingly, the four corners of a constellation the old
# charts call "the Frame".
# ---------------------------------------------------------------------------

# The star a viewpoint shares with another (the hinge of the transformation).
proc ::game::sky-shared {a b} {
    foreach s [frames::fget $a stars] {
        if {[lsearch -exact [frames::fget $b stars] $s] >= 0} { return $s }
    }
    return ""
}

# Describe the field the telescope is currently aimed at, mark it observed,
# and -- once every field has been swept -- let the player connect the
# shared corners into the whole figure.
proc ::game::peer-telescope {tel} {
    set aim [frames::fget $tel aim]
    set ring [frames::fget $tel ring]
    set stars [frames::fget $aim stars]
    lassign $stars left mid right

    say "Through the eyepiece, [frames::fget $aim label] swims into focus."
    say "Two bright stars anchor the field -- $left at the left edge and $right at the right -- with $mid guttering faintly between them."

    # Name the neighbours each bright corner is shared with: the continuity
    # of the system made visible.
    set i [lsearch -exact $ring $aim]
    set n [llength $ring]
    set prev [lindex $ring [expr {($i - 1 + $n) % $n}]]
    set next [lindex $ring [expr {($i + 1) % $n}]]
    say "$left is the very star you can pick up again in the field to the left; $right reappears in the field to the right. Each bright star belongs to two fields at once."

    # Mark this field as observed.
    set seen [frames::fget $tel seen]
    if {[lsearch -exact $seen $aim] < 0} {
        lappend seen $aim
        frames::fput $tel seen $seen
    }

    # When all fields have been observed and the figure not yet recognised,
    # the shared corners assemble into the whole.
    if {[llength $seen] >= [llength $ring]
            && [frames::fget $tel figure-found] ne "1"} {
        frames::fput $tel figure-found 1
        say ""
        set corners {}
        foreach v $ring { lappend corners [lindex [frames::fget $v stars] 0] }
        say "Having swept the whole sky, you hold all four bright stars in mind at once and join them: [join $corners {, }]. They close into a single quadrilateral -- the faint stars tracing its sides -- that the old charts label, simply, THE FRAME. The four corners are precisely the stars each shared between two fields: the shared points were the structure all along."
        add-score
    }
}

proc ::game::do-peer {inst} {
    peer-telescope [frames::fget $inst object]
}

proc ::game::do-turn {inst} {
    set tel [frames::fget $inst object]
    set ring [frames::fget $tel ring]
    if {[llength $ring] == 0} {
        say "It turns a little, then sticks. Nothing comes of it."
        return
    }
    set words [frames::fget $inst words]
    set dir right
    foreach w $words {
        if {[lsearch -exact {left widdershins counter back} $w] >= 0} { set dir left }
        if {[lsearch -exact {right clockwise sun forward} $w] >= 0}   { set dir right }
    }

    set aim [frames::fget $tel aim]
    set i [lsearch -exact $ring $aim]
    set n [llength $ring]
    # NB: written as if/else, not a ternary -- some embedded exprs evaluate
    # both branches, and the left-turn branch divides by a negative-wrapped
    # index that is invalid before normalization.
    if {$dir eq "right"} {
        set j [expr {($i + 1) % $n}]
    } else {
        set j [expr {($i - 1 + $n) % $n}]
    }
    set dest [lindex $ring $j]

    # The transformation, narrated through its shared terminal: the boundary
    # star slides across, the one thing both frames hold in common.
    set hinge [sky-shared $aim $dest]
    set fromEdge [expr {$dir eq "right" ? "right" : "left"}]
    set toEdge   [expr {$dir eq "right" ? "left"  : "right"}]
    say "You turn the telescope to the $dir."
    if {$hinge ne ""} {
        say "The bright star $hinge slides from the $fromEdge edge to the $toEdge edge -- the single star both fields share, the hinge the whole sky turns on."
    }
    frames::fput $tel aim $dest
    say ""
    peer-telescope $tel
}

# ---------------------------------------------------------------------------
# Perspectives on a room: impose, drop, or list the frames a scene affords.
# ---------------------------------------------------------------------------
proc ::game::do-view {inst} {
    variable here
    set lens [frames::fget $inst lens]
    set map  [frames::fget $here perspectives]

    if {$lens eq ""} {
        # List the perspectives this scene affords.
        set cur [frames::fget player viewpoint]
        if {$cur eq "" || $cur eq "plain"} {
            say "You are seeing [the $here] plainly."
        } else {
            say "You are seeing [the $here] through [frames::fget $cur label]."
        }
        if {[dict size $map] == 0} {
            say "Nothing here particularly rewards a change of framing."
            return
        }
        set shown {}
        say "Ways of regarding this place:"
        foreach {kw fr} $map {
            if {[lsearch -exact $shown $fr] >= 0} continue
            lappend shown $fr
            set known [expr {[lsearch -exact [frames::fget player lenses] $fr] >= 0}]
            set tag [expr {$known ? "" : "  (not yet learned)"}]
            say "  view as $kw -- [frames::fget $fr label]$tag"
        }
        say "  view plain -- set the framing aside"
        return
    }

    if {$lens eq "plain"} {
        frames::fput player viewpoint plain
        say "You let the framing fall away and see the room as it plainly is."
        look-around
        return
    }

    if {![dict exists $map $lens]} {
        say "Nothing here rewards looking at it that way."
        return
    }
    set fr [dict get $map $lens]
    if {[lsearch -exact [frames::fget player lenses] $fr] < 0} {
        say "You have heard there is a way of seeing this place as [frames::fget $fr label], but you haven't learned that framing yet. Perhaps someone could lend it to you."
        return
    }
    frames::fput player viewpoint $fr
    look-around
}

# ===========================================================================
# THE DIFFERENCE NETWORK AND THE MATCHING PROCESS
#
# Minsky: matching a situation to a frame can fail on a *difference* -- some
# condition that ought to hold but doesn't. Frames are joined by pointers
# labelled with the difference each removes, and the matcher follows them,
# transforming the situation until it fits. Here that idea is made to run.
#
#   * A DIFFERENCE is a frame (AKO `difference`) that knows how to test
#     whether it is present on a target, which OPERATOR (action frame)
#     removes it, and how to fill that operator's terminals.
#
#   * Each access action declares a `plan-needs` procedure: given its
#     resolved operands, it returns the differences that must first be
#     removed (or the token FAIL if the goal is hopeless).
#
#   * `achieve` resolves one difference by recursion: it finds the operator
#     that removes it, resolves THAT operator's own preconditions first
#     (sub-differences), and emits the operator as a plan step. This is
#     means-ends analysis grounded entirely in frames.
#
#   * `try-plan` assembles the full chain; the engine then offers it to the
#     player and, on assent, performs each operator in turn.
# ===========================================================================

# ----- world predicates the planner reasons over ---------------------------
proc ::game::carried? {f}  { expr {[frames::fget $f location] eq "player"} }
proc ::game::portable? {f} { expr {[frames::fget $f portable] eq "1"} }
proc ::game::locked? {f}   { expr {[frames::fget $f locked] eq "1"} }
proc ::game::closed-container? {f} {
    expr {[frames::fget $f container] eq "1" && [frames::fget $f open] ne "1"}
}
proc ::game::room-lit? {r} {
    if {[frames::fget $r lit] eq "1"} { return 1 }
    foreach f [concat [contents $r] [contents player]] {
        if {[frames::fget $f light-source] eq "1" && [frames::fget $f lit] eq "1"} {
            return 1
        }
    }
    return 0
}

# Everything the player could plausibly reach in this room WITHOUT moving:
# carried items, the room's contents, and the contents of containers here
# (open OR closed -- a closed chest is a thing you know you could open).
proc ::game::wide-scope {} {
    variable here
    set s [concat [contents player] [contents $here]]
    set i 0
    while {$i < [llength $s]} {
        set c [lindex $s $i]
        if {[frames::fget $c container] eq "1"} {
            set s [concat $s [contents $c]]
        }
        incr i
    }
    return $s
}

proc ::game::wide-match {nouns used} {
    foreach f [wide-scope] {
        if {[lsearch -exact $used $f] >= 0} continue
        foreach n $nouns {
            if {[lsearch -exact [frames::fget $f names] $n] >= 0} { return $f }
        }
    }
    return ""
}

proc ::game::container-of {obj} {
    set loc [frames::fget $obj location]
    if {$loc ne "" && [frames::fget $loc container] eq "1"} { return $loc }
    return ""
}

# The key that actually fits this lock, if it is in reach. When planning at
# a distance only what is carried counts -- the planner won't run a side
# errand to fetch a key from a third room.
proc ::game::find-key-for {obj} {
    variable planremote
    set k [frames::fget $obj unlocks-with]
    if {$k eq ""} { return "" }
    set scope [expr {$planremote ? [contents player] : [wide-scope]}]
    if {[lsearch -exact $scope $k] >= 0} { return $k }
    return ""
}

# A light source you could light right now: a carried one (you can find it
# even in the dark). A lamp lying in a dark room can't be located.
proc ::game::find-lightsource {} {
    foreach f [contents player] {
        if {[frames::fget $f light-source] eq "1"} { return $f }
    }
    return ""
}

# ----- difference frames ----------------------------------------------------
frames::defframe difference {}

frames::defframe diff-dark {
    ako   {value difference}
    test  {value ::game::dp-dark}
    oper  {value light}
    findo {value ::game::df-light}
    desc  {value ::game::dd-dark}
}
frames::defframe diff-closed {
    ako   {value difference}
    test  {value ::game::dp-closed}
    oper  {value open}
    desc  {value ::game::dd-closed}
}
frames::defframe diff-locked {
    ako   {value difference}
    test  {value ::game::dp-locked}
    oper  {value unlock}
    finds {value ::game::df-key}
    desc  {value ::game::dd-locked}
}
frames::defframe diff-uncarried {
    ako   {value difference}
    test  {value ::game::dp-uncarried}
    oper  {value take}
    desc  {value ::game::dd-uncarried}
}

proc ::game::dp-dark {t}      { expr {![room-lit? $t]} }
proc ::game::df-light {t}     { find-lightsource }
proc ::game::dd-dark {t}      { return "it is too dark to see" }
proc ::game::dp-closed {t}    { closed-container? $t }
proc ::game::dd-closed {t}    { return "[the $t] is closed" }
proc ::game::dp-locked {t}    { locked? $t }
proc ::game::df-key {t}       { find-key-for $t }
proc ::game::dd-locked {t}    { return "[the $t] is locked" }
proc ::game::dp-uncarried {t} { expr {![carried? $t] && [portable? $t]} }
proc ::game::dd-uncarried {t} { return "you aren't holding [the $t]" }

# ----- difference accessors -------------------------------------------------
proc ::game::diff-present {d t} { uplevel #0 [list {*}[frames::fget $d test] $t] }
proc ::game::diff-oper {d}      { frames::fget $d oper }
proc ::game::diff-object {d t} {
    set p [frames::fget $d findo]
    if {$p ne ""} { return [uplevel #0 [list {*}$p $t]] }
    return $t
}
proc ::game::diff-second {d t} {
    set p [frames::fget $d finds]
    if {$p ne ""} { return [uplevel #0 [list {*}$p $t]] }
    return ""
}
proc ::game::diff-desc {d t} { uplevel #0 [list {*}[frames::fget $d desc] $t] }

# ----- preconditions of operators (the `plan-needs` of each action) ---------
# Each returns a list of {difference target} goals, or the token FAIL.

# Differences that must be removed merely to REACH an object: darkness (for
# anything you aren't already holding) and a closed container around it.
# Darkness is judged in the room the planner is currently reasoning about
# (`planroom`), which is `here` for a local plan and the goal room for a
# remote one.
proc ::game::reach-goals {obj} {
    variable planroom
    set g {}
    if {![carried? $obj] && [dp-dark $planroom]} { lappend g [list diff-dark $planroom] }
    set c [container-of $obj]
    if {$c ne "" && [closed-container? $c]} { lappend g [list diff-closed $c] }
    return $g
}

proc ::game::plan-needs-take {obj second} {
    if {![portable? $obj]} { return FAIL }
    return [reach-goals $obj]
}
proc ::game::plan-needs-open {obj second} {
    set g [reach-goals $obj]
    if {[locked? $obj]} { lappend g [list diff-locked $obj] }
    return $g
}
proc ::game::plan-needs-unlock {obj second} {
    set key $second
    if {$key eq ""} { set key [find-key-for $obj] }
    if {$key eq "" || [frames::fget $obj unlocks-with] ne $key} { return FAIL }
    set g [reach-goals $obj]
    if {[dp-uncarried $key]} { lappend g [list diff-uncarried $key] }
    return $g
}
proc ::game::plan-needs-light {obj second} {
    if {[frames::fget $obj light-source] ne "1"} { return FAIL }
    return [reach-goals $obj]
}

proc ::game::needs-proc {verb} { frames::fget $verb plan-needs }

# ----- the recursion --------------------------------------------------------
proc ::game::achieve {goal depth visited} {
    if {$depth > 8} { return FAIL }
    lassign $goal d t
    if {[lsearch -exact $visited "$d:$t"] >= 0} { return FAIL }
    if {![diff-present $d $t]} { return {} }

    set obj    [diff-object $d $t]
    set second [diff-second $d $t]
    if {$obj eq ""} { return FAIL }

    set oper [diff-oper $d]
    set pn   [needs-proc $oper]
    set sub  {}
    if {$pn ne ""} {
        set sub [uplevel #0 [list {*}$pn $obj $second]]
        if {$sub eq "FAIL"} { return FAIL }
    }

    set steps {}
    set v2 [concat $visited [list "$d:$t"]]
    foreach g $sub {
        set r [achieve $g [expr {$depth + 1}] $v2]
        if {$r eq "FAIL"} { return FAIL }
        foreach s $r { if {[lsearch -exact $steps $s] < 0} { lappend steps $s } }
    }
    lappend steps [list $oper $obj $second]
    return $steps
}

# ----- locating things and routes across rooms ------------------------------
# The room an object ultimately sits in (following any chain of containers),
# or "player" if carried, or "" if nowhere placeable.
proc ::game::room-of {obj} {
    variable here
    set loc [frames::fget $obj location]
    if {$loc eq "player"} { return $here }
    set guard 0
    while {$loc ne "" && ![frames::isa? $loc room] && [incr guard] < 30} {
        if {$loc eq "player"} { return $here }
        set loc [frames::fget $loc location]
    }
    if {[frames::isa? $loc room]} { return $loc }
    return ""
}

# A hostile creature stationed in `room` that bars the exit `dir`, or "".
proc ::game::edge-guard {room dir} {
    foreach g [contents $room] {
        if {[frames::fget $g hostile] eq "1"} {
            set bl [frames::fget $g blocks]
            if {[llength $bl] == 2 && [lindex $bl 0] eq $room
                                   && [lindex $bl 1] eq $dir} { return $g }
        }
    }
    return ""
}

# Breadth-first search over the `exits` graph: rooms are place-frames joined
# by transformation-links, and a route is a sequence of those transforms. A
# guarded edge is traversable only if the guard's wanted item is in hand (a
# `give` is emitted before crossing); otherwise the edge is a wall. Returns a
# list of hops {dir give guard}, {} if already there, or FAIL if unreachable.
proc ::game::find-route {from to} {
    if {$from eq $to} { return {} }
    set queue [list $from]
    set seen  [list $from]
    set prev [dict create]
    while {[llength $queue]} {
        set cur [lindex $queue 0]
        set queue [lrange $queue 1 end]
        foreach {dir dest} [frames::fget $cur exits] {
            if {[lsearch -exact $seen $dest] >= 0} continue
            set give "" ; set guard ""
            set blk [edge-guard $cur $dir]
            if {$blk ne ""} {
                set want [frames::fget $blk wants]
                if {$want ne "" && [carried? $want]} {
                    set give $want ; set guard $blk
                } else {
                    continue
                }
            }
            dict set prev $dest [list $cur $dir $give $guard]
            lappend seen $dest
            lappend queue $dest
            if {$dest eq $to} {
                set hops {} ; set node $to
                while {$node ne $from} {
                    lassign [dict get $prev $node] p d g gd
                    set hops [linsert $hops 0 [list $d $g $gd]]
                    set node $p
                }
                return $hops
            }
        }
    }
    return FAIL
}

# Match a named thing ANYWHERE in the world (used only as a last resort, so
# the player can name a goal in another room and let the planner route there).
proc ::game::global-match {nouns used} {
    foreach f [frames::all] {
        if {$f eq "player" || [lsearch -exact $used $f] >= 0} continue
        if {![frames::isa? $f thing] || [frames::isa? $f room]} continue
        foreach n $nouns {
            if {[lsearch -exact [frames::fget $f names] $n] >= 0} { return $f }
        }
    }
    return ""
}

# ===========================================================================
# RECURSIVE CROSS-ROOM PLANNING OVER A PROJECTED WORLD-STATE
#
# Reaching a distant goal can demand changing the world along the way --
# fetching the bone before the troll will move, lighting the lamp before the
# cellar will yield its chest. A planner that judged each precondition
# against the world AS IT IS NOW would never see that picking the bone up
# makes the troll's staircase passable. So this planner reasons over a
# PROJECTED state S: an overlay of the changes its own steps would make.
# Predicates are read through S; each operator returns a new S; and goals
# (be somewhere, be carrying something, have a room lit, a guard satisfied)
# are achieved by recursion, threading S forward. It is a small means-ends /
# STRIPS planner in which routing, fetching, and appeasing a guard are all
# just goals -- exactly Minsky's composition of transformations, now able to
# set up the conditions each transformation needs.
# ===========================================================================

# ----- reading the projected state -----------------------------------------
proc ::game::p-get {S key dflt} {
    expr {[dict exists $S $key] ? [dict get $S $key] : $dflt}
}
proc ::game::p-here {S} { variable actor ; p-get $S here [frames::fget $actor location] }
proc ::game::p-loc {S obj} {
    if {[dict exists $S loc:$obj]} { return [dict get $S loc:$obj] }
    variable usebeliefs
    if {$usebeliefs} {
        # A fallible mind knows only what it has come to believe; about
        # anything it has never seen, it has no idea (so it cannot plan to
        # reach it).
        variable beliefs
        if {[dict exists $beliefs $obj]} { return [dict get $beliefs $obj] }
        return ""
    }
    return [frames::fget $obj location]
}
proc ::game::p-carried {S obj} { variable actor ; expr {[p-loc $S $obj] eq $actor} }
proc ::game::p-open {S c} { p-get $S open:$c [frames::fget $c open] }
proc ::game::p-locked {S c} { p-get $S locked:$c [frames::fget $c locked] }
proc ::game::p-lit {S l} { p-get $S lit:$l [frames::fget $l lit] }
proc ::game::p-sat {S g} {
    p-get $S sat:$g [expr {[frames::fget $g hostile] ne "1"}]
}
proc ::game::p-room-of {S obj} {
    variable actor
    set loc [p-loc $S $obj]
    if {$loc eq $actor} { return [p-here $S] }
    set g 0
    while {$loc ne "" && ![frames::isa? $loc room] && [incr g] < 30} {
        if {$loc eq $actor} { return [p-here $S] }
        set loc [p-loc $S $loc]
    }
    if {[frames::isa? $loc room]} { return $loc }
    return ""
}
proc ::game::p-container-of {S obj} {
    set loc [p-loc $S $obj]
    if {$loc ne "" && $loc ne "player" && [frames::fget $loc container] eq "1"} {
        return $loc
    }
    return ""
}
proc ::game::light-sources {} {
    set r {}
    foreach f [frames::all] {
        if {[frames::fget $f light-source] eq "1"} { lappend r $f }
    }
    return $r
}
proc ::game::p-room-lit {S R} {
    if {[frames::fget $R lit] eq "1"} { return 1 }
    foreach f [light-sources] {
        if {[p-lit $S $f] eq "1" && ([p-room-of $S $f] eq $R || [p-carried $S $f])} {
            return 1
        }
    }
    return 0
}

# ----- applying an operator to the projected state --------------------------
proc ::game::apply-op {S step} {
    variable actor
    lassign $step verb a b
    switch -- $verb {
        go     { dict set S here [dict get [frames::fget [p-here $S] exits] $a] }
        take   { dict set S loc:$a $actor }
        give   { dict set S loc:$a $b ; dict set S sat:$b 1 }
        unlock { dict set S locked:$a 0 }
        open   { dict set S open:$a 1 }
        light  { dict set S lit:$a 1 }
        drop   { dict set S loc:$a [p-here $S] }
    }
    return $S
}

# ----- routing in the projected graph ---------------------------------------
# Plain reachability ignoring guards, but skipping one named edge -- used to
# decide whether a guarded edge is worth crossing (its key/bribe must be
# fetchable without crossing that very edge).
proc ::game::reachable-excl {from target exr exd} {
    if {$from eq $target} { return 1 }
    set q [list $from] ; set seen [list $from]
    while {[llength $q]} {
        set cur [lindex $q 0] ; set q [lrange $q 1 end]
        foreach {dir dest} [frames::fget $cur exits] {
            if {$cur eq $exr && $dir eq $exd} continue
            if {[lsearch -exact $seen $dest] >= 0} continue
            if {$dest eq $target} { return 1 }
            lappend seen $dest ; lappend q $dest
        }
    }
    return 0
}

# BFS giving hops {dir guard}: a guarded edge is free if the guard is already
# satisfied in S; otherwise crossable (guard noted, to be appeased) only if
# the guard's wanted item could be fetched without using this same edge.
proc ::game::proute {S from to} {
    if {$from eq $to} { return {} }
    set q [list $from] ; set seen [list $from] ; set prev [dict create]
    while {[llength $q]} {
        set cur [lindex $q 0] ; set q [lrange $q 1 end]
        foreach {dir dest} [frames::fget $cur exits] {
            if {[lsearch -exact $seen $dest] >= 0} continue
            set guard [edge-guard $cur $dir]
            if {$guard ne "" && ![p-sat $S $guard]} {
                set want [frames::fget $guard wants]
                if {$want eq "" || ![reachable-excl $from [p-room-of $S $want] $cur $dir]} {
                    continue
                }
            } else {
                set guard ""
            }
            dict set prev $dest [list $cur $dir $guard]
            lappend seen $dest ; lappend q $dest
            if {$dest eq $to} {
                set hops {} ; set node $to
                while {$node ne $from} {
                    lassign [dict get $prev $node] p d gd
                    set hops [linsert $hops 0 [list $d $gd]]
                    set node $p
                }
                return $hops
            }
        }
    }
    return FAIL
}

# ----- achieving goals (state-threaded recursion) ---------------------------
# Each returns {steps Sout} or FAIL. A goal already true in S yields {}.
proc ::game::ach-seq {goals S depth visited} {
    set steps {}
    foreach g $goals {
        set r [ach $g $S $depth $visited]
        if {$r eq "FAIL"} { return FAIL }
        lassign $r gs S
        foreach x $gs { lappend steps $x }
    }
    return [list $steps $S]
}

proc ::game::ach {goal S depth visited} {
    if {$depth > 14 || [llength $visited] > 40} { return FAIL }
    set k [join $goal :]
    if {[lsearch -exact $visited $k] >= 0} { return FAIL }
    lappend visited $k
    lassign $goal type a
    switch -- $type {
        at         { return [ach-at $a $S $depth $visited] }
        carried    { return [ach-carried $a $S $depth $visited] }
        accessible { return [ach-accessible $a $S $depth $visited] }
        litroom    { return [ach-litroom $a $S $depth $visited] }
        opened     { return [ach-opened $a $S $depth $visited] }
        unlocked   { return [ach-unlocked $a $S $depth $visited] }
        satisfied  { return [ach-satisfied $a $S $depth $visited] }
    }
    return FAIL
}

proc ::game::ach-at {R S depth visited} {
    if {[p-here $S] eq $R} { return [list {} $S] }
    set route [proute $S [p-here $S] $R]
    if {$route eq "FAIL"} { return FAIL }
    set steps {} ; set cur $S
    # First appease any guard standing on the route (fetching its bribe may
    # move us about); then walk a now-unguarded route to R.
    foreach hop $route {
        lassign $hop dir guard
        if {$guard ne "" && ![p-sat $cur $guard]} {
            set r [ach [list satisfied $guard] $cur [expr {$depth + 1}] $visited]
            if {$r eq "FAIL"} { return FAIL }
            lassign $r gs cur
            foreach x $gs { lappend steps $x }
        }
    }
    set route2 [proute $cur [p-here $cur] $R]
    if {$route2 eq "FAIL"} { return FAIL }
    foreach hop $route2 {
        lassign $hop dir guard
        if {$guard ne ""} { return FAIL }
        lappend steps [list go $dir {}]
        set cur [apply-op $cur [list go $dir {}]]
    }
    return [list $steps $cur]
}

proc ::game::ach-satisfied {G S depth visited} {
    if {[p-sat $S $G]} { return [list {} $S] }
    set want [frames::fget $G wants]
    if {$want eq ""} { return FAIL }
    set r [ach-seq [list [list carried $want] [list at [p-room-of $S $G]]] \
                   $S [expr {$depth + 1}] $visited]
    if {$r eq "FAIL"} { return FAIL }
    lassign $r steps S1
    set op [list give $want $G]
    return [list [concat $steps [list $op]] [apply-op $S1 $op]]
}

proc ::game::ach-carried {O S depth visited} {
    if {[p-carried $S $O]} { return [list {} $S] }
    if {[frames::fget $O portable] ne "1"} { return FAIL }
    set r [ach [list accessible $O] $S [expr {$depth + 1}] $visited]
    if {$r eq "FAIL"} { return FAIL }
    lassign $r steps S1
    set op [list take $O {}]
    return [list [concat $steps [list $op]] [apply-op $S1 $op]]
}

proc ::game::ach-accessible {O S depth visited} {
    if {[p-carried $S $O]} { return [list {} $S] }
    set R [p-room-of $S $O]
    if {$R eq ""} { return FAIL }
    # Gather what the destination will need (light, an opened container)
    # BEFORE walking there, so tools are fetched in passing rather than after
    # a wasted trip to the goal and back.
    set goals {}
    if {![p-room-lit $S $R]} { lappend goals [list litroom $R] }
    set c [p-container-of $S $O]
    if {$c ne ""} { lappend goals [list opened $c] }
    lappend goals [list at $R]
    return [ach-seq $goals $S [expr {$depth + 1}] $visited]
}

proc ::game::ach-litroom {R S depth visited} {
    if {[p-room-lit $S $R]} { return [list {} $S] }
    set L ""
    foreach f [light-sources] { if {[p-carried $S $f]} { set L $f ; break } }
    if {$L eq ""} {
        foreach f [light-sources] {
            set fr [p-room-of $S $f]
            if {$fr ne "" && [p-room-lit $S $fr]} { set L $f ; break }
        }
    }
    if {$L eq ""} { return FAIL }
    set r [ach [list carried $L] $S [expr {$depth + 1}] $visited]
    if {$r eq "FAIL"} { return FAIL }
    lassign $r steps S1
    set op [list light $L {}]
    return [list [concat $steps [list $op]] [apply-op $S1 $op]]
}

proc ::game::ach-opened {C S depth visited} {
    if {[p-open $S $C]} { return [list {} $S] }
    set R [p-room-of $S $C]
    set goals {}
    if {![p-room-lit $S $R]} { lappend goals [list litroom $R] }
    lappend goals [list unlocked $C]
    lappend goals [list at $R]
    set r [ach-seq $goals $S [expr {$depth + 1}] $visited]
    if {$r eq "FAIL"} { return FAIL }
    lassign $r steps S1
    set op [list open $C {}]
    return [list [concat $steps [list $op]] [apply-op $S1 $op]]
}

proc ::game::ach-unlocked {C S depth visited} {
    if {![p-locked $S $C]} { return [list {} $S] }
    set key [frames::fget $C unlocks-with]
    if {$key eq ""} { return FAIL }
    set R [p-room-of $S $C]
    set goals {}
    if {![p-room-lit $S $R]} { lappend goals [list litroom $R] }
    lappend goals [list carried $key]
    lappend goals [list at $R]
    set r [ach-seq $goals $S [expr {$depth + 1}] $visited]
    if {$r eq "FAIL"} { return FAIL }
    lassign $r steps S1
    set op [list unlock $C $key]
    return [list [concat $steps [list $op]] [apply-op $S1 $op]]
}

# Describe a plan's obstacles from the operators it had to include.
proc ::game::plan-obstacles {steps} {
    set o {}
    foreach s $steps {
        lassign $s v a b
        set phrase ""
        switch -- $v {
            give   { set phrase "[the $b] bars the way" }
            light  { set phrase "it is dark along the way" }
            unlock { set phrase "[the $a] is locked" }
            open   { set phrase "[the $a] is shut" }
        }
        if {$phrase ne "" && [lsearch -exact $o $phrase] < 0} { lappend o $phrase }
    }
    return $o
}

# plan2 -- assemble a (possibly cross-room, possibly item-fetching) plan that
# makes <verb obj second> possible, or "" if there is no such plan.
proc ::game::plan2 {verb obj second} {
    variable actor
    variable usebeliefs
    set actor player
    set usebeliefs 0
    set S {}
    switch -- $verb {
        take {
            if {[frames::fget $obj portable] ne "1"} { return "" }
            set goals [list [list accessible $obj]]
        }
        light {
            if {[frames::fget $obj light-source] ne "1"} { return "" }
            set goals [list [list accessible $obj]]
        }
        open {
            set goals [list [list accessible $obj] [list unlocked $obj]]
        }
        unlock {
            set key $second
            if {$key eq ""} { set key [frames::fget $obj unlocks-with] }
            if {$key eq "" || [frames::fget $obj unlocks-with] ne $key} { return "" }
            set goals [list [list accessible $obj] [list carried $key]]
        }
        default { return "" }
    }
    set r [ach-seq $goals $S 0 {}]
    if {$r eq "FAIL"} { return "" }
    lassign $r steps S1
    if {[llength $steps] == 0 || [llength $steps] > 24} { return "" }
    return [dict create steps $steps obstacle [join-and [plan-obstacles $steps]] \
                        original [list $verb $obj $second] moved 1]
}

# Assemble a plan that makes <verb obj second> possible, or "" if the action
# is already possible (nothing to do) or no plan exists (hopeless).
proc ::game::try-plan {verb obj second} {
    variable here
    variable planroom
    variable planremote
    variable actor
    variable usebeliefs
    set actor player
    set usebeliefs 0
    set pn [needs-proc $verb]
    if {$pn eq ""} { return "" }

    # If the object lives in another room, plan a route there -- fetching
    # whatever the journey needs along the way.
    set R [room-of $obj]
    if {$R ne "" && $R ne $here && ![carried? $obj]} {
        return [plan2 $verb $obj $second]
    }

    # Local plan: reason about the current room, using anything within reach.
    set planroom $here ; set planremote 0
    set goals [uplevel #0 [list {*}$pn $obj $second]]
    if {$goals eq "FAIL"} { return "" }

    set obstacle {}
    foreach g $goals {
        lassign $g d t
        if {[diff-present $d $t]} { lappend obstacle [diff-desc $d $t] }
    }

    set steps {}
    foreach g $goals {
        set r [achieve $g 0 {}]
        if {$r eq "FAIL"} { return "" }
        foreach s $r { if {[lsearch -exact $steps $s] < 0} { lappend steps $s } }
    }
    if {[llength $steps] == 0} { return "" }
    return [dict create steps $steps obstacle [join-and $obstacle] \
                        original [list $verb $obj $second]]
}

# ----- describing and running a plan ----------------------------------------
proc ::game::join-and {items} {
    set n [llength $items]
    if {$n == 0} { return "" }
    if {$n == 1} { return [lindex $items 0] }
    if {$n == 2} { return "[lindex $items 0] and [lindex $items 1]" }
    return "[join [lrange $items 0 end-1] {, }], and [lindex $items end]"
}

proc ::game::step-phrase {verb obj second} {
    switch -- $verb {
        take    { return "take [the $obj]" }
        open    { return "open [the $obj]" }
        light   { return "light [the $obj]" }
        unlock  { return "unlock [the $obj] with [the $second]" }
        give    { return "give [the $obj] to [the $second]" }
        go      { return "go $obj" }
        default { return "$verb [the $obj]" }
    }
}

proc ::game::offer-plan {plan} {
    variable pending
    variable teach
    set steps [dict get $plan steps]
    set obst  [dict get $plan obstacle]
    set phrases {}
    foreach s $steps { lappend phrases [step-phrase {*}$s] }
    set orig [step-phrase {*}[dict get $plan original]]

    set lead [expr {$obst ne "" ? "[string totitle $obst]. " : ""}]
    if {[llength $phrases]} {
        say "${lead}I can [join-and $phrases], then $orig. Shall I? (yes/no)"
        # Once per session, name the machinery that just ran. This is
        # Minsky's matching process made visible: the situation refused to
        # fit, and the engine walked the difference network until it did.
        if {!$teach} {
            set teach 1
            say "(What just happened: the situation would not fit the frame, so"
            say "I followed a chain of differences -- each step removes one thing"
            say "that stood between you and the goal. Ask \"why\" anytime to see"
            say "the machinery laid bare.)"
        }
    } else {
        say "${lead}I can $orig. Shall I? (yes/no)"
    }
    set pending $plan
}

# perform-action -- run one resolved operator (no parsing, no re-planning).
# Returns 1 on success, 0 if its own check blocked it.
proc ::game::perform-action {verb obj second} {
    variable seq
    set inst "${verb}#plan[incr seq]"
    frames::instantiate $inst $verb
    if {$verb eq "go"} {
        # For movement the "operand" is a direction word, read from `words`.
        frames::fput $inst words [list $obj]
    } else {
        frames::fput $inst words {}
        if {$obj ne ""}    { frames::fput $inst object $obj }
        if {$second ne ""} { frames::fput $inst second $second }
    }
    set chk [frames::fget $verb check]
    if {$chk ne ""} {
        set res [uplevel #0 [list {*}$chk $inst]]
        if {[lindex $res 0] eq "fail"} {
            say [lindex $res 1]
            frames::delete $inst
            return 0
        }
    }
    uplevel #0 [list {*}[frames::fget $verb perform] $inst]
    frames::delete $inst
    return 1
}

proc ::game::run-plan {plan} {
    variable quiet
    set moved [expr {[dict exists $plan moved] && [dict get $plan moved]}]
    set quiet $moved
    foreach s [dict get $plan steps] {
        if {![perform-action {*}$s]} {
            set quiet 0
            say "(That puts a stop to the plan.)"
            return
        }
    }
    lassign [dict get $plan original] verb obj second
    set ok [perform-action $verb $obj $second]
    set quiet 0
    if {$obj ne ""} { frames::fput player focus $obj }
    # After a journey, show the player where they have ended up.
    if {$moved && $ok} { look-around }
}

# ===========================================================================
# AUTONOMOUS NPCs -- the same planner, run on a character's behalf
#
# A character may carry a `goal` terminal. Each turn its `pursue-goal` demon
# sets the planner's actor to that character and asks the very machinery the
# player uses (`ach`/`ach-seq` over a projected state) for a plan toward the
# goal -- then takes a single step of it. Because every projected predicate
# reads through the current actor, the planner reasons about the NPC's own
# position and possessions; only execution (`npc-do`) needs to know whose
# hands and feet are moving. So the cat fetching its toy is the player's
# fetch-and-carry expedition, run for a cat.
#
# Goal forms:  {goto R}            be in room R
#              {fetch O}           be holding object O
#              {bring O dest}      carry O to a room or to a character
#              {follow C}          keep arriving wherever C is
# ===========================================================================

# Where a `bring`/`follow` destination resolves to: a room is itself; a
# character is wherever it currently stands.
proc ::game::dest-room {d} {
    if {[frames::isa? $d room]} { return $d }
    return [room-of $d]
}

# A reactive policy: a thief that covets whatever shiny thing it can see in
# the player's hands. Holding loot, it flees to its lair; seeing the player
# flaunt something shiny, it forms the goal of coming to take it; otherwise
# it skulks back toward the lair. The goal it returns is pursued by exactly
# the same planner the player's own commands use.
# ----- perception and belief (a fallible mind) ------------------------------
# Can the NPC see in room R? (the room is lit for it -- it knows nothing in
# the pitch dark unless it carries its own light).
proc ::game::npc-can-see {npc R} {
    if {[frames::fget $R lit] eq "1"} { return 1 }
    foreach f [light-sources] {
        if {[frames::fget $f lit] eq "1"
                && ([frames::fget $f location] eq $R
                ||  [frames::fget $f location] eq $npc)} { return 1 }
    }
    return 0
}

# Descend into a thing the NPC can see past -- an open container, or a
# creature whose hands are in view -- gathering what it reveals. A closed
# container is opaque: its contents are simply not there to be seen. A bauble
# tucked away as a creature's pocketed BAIT is hidden the same way -- the
# cheek is a closed pouch -- so to every other eye it simply is not there.
proc ::game::npc-see-into {f seenVar} {
    upvar 1 $seenVar seen
    set animate  [expr {[frames::fget $f animate] eq "1"}]
    set opencont [expr {[frames::fget $f container] eq "1" && [frames::fget $f open] eq "1"}]
    if {$animate || $opencont} {
        set pocket [frames::fget $f bait]
        foreach h [contents $f] {
            if {$h ne "" && $h eq $pocket} continue
            lappend seen $h ; npc-see-into $h seen
        }
    }
}

# Everything the NPC can presently see in room R: what lies in the room and,
# recursively, whatever open containers and creatures there reveal -- but
# nothing shut away inside a closed box. (It also knows what it itself holds.)
proc ::game::npc-sees {npc R} {
    set seen {}
    foreach f [frames::all] {
        if {$f eq $npc} continue
        if {[frames::isa? $f thing] && [frames::fget $f location] eq $R} {
            lappend seen $f
            npc-see-into $f seen
        }
    }
    foreach h [contents $npc] { lappend seen $h ; npc-see-into $h seen }
    return $seen
}

# The room a belief places an object in (following believed containers/
# carriers), or "" if the belief doesn't pin it to a room.
proc ::game::bel-room {bel obj} {
    if {![dict exists $bel $obj]} { return "" }
    set loc [dict get $bel $obj]
    set g 0
    while {[incr g] < 12} {
        if {$loc eq ""} { return "" }
        if {[frames::isa? $loc room]} { return $loc }
        if {[dict exists $bel $loc]} { set loc [dict get $bel $loc] ; continue }
        # fall back to the true position of the carrier/container
        set loc [frames::fget $loc location]
    }
    return ""
}

# Update an NPC's beliefs from what it now sees: learn the truth about
# everything visible, and -- where it expected something in this room that
# isn't here -- be surprised, and forget. Returns 1 if a notable belief was
# overturned in front of the player.
proc ::game::npc-perceive {npc} {
    variable here
    set R [frames::fget $npc location]
    if {![npc-can-see $npc $R]} { return 0 }
    set bel     [frames::fget $npc beliefs]
    set seenmem [frames::fget $npc seen]
    set seen    [npc-sees $npc $R]
    set baffled 0
    # Contradictions: beliefs that placed something in R, now seen to be false.
    foreach obj [dict keys $bel] {
        if {[bel-room $bel $obj] eq $R && [lsearch -exact $seen $obj] < 0} {
            if {[frames::fget $obj shiny] eq "1" && $R eq $here && [lit-here]} {
                set baffled 1
            }
            dict unset bel $obj
        }
    }
    # Searched and not found: this room is no longer a lead for that thing.
    foreach obj [dict keys $seenmem] {
        if {[lsearch -exact $seen $obj] < 0} {
            set rooms [dict get $seenmem $obj]
            set i [lsearch -exact $rooms $R]
            if {$i >= 0} {
                if {[frames::fget $obj shiny] eq "1" && $R eq $here && [lit-here]} {
                    set baffled 1
                }
                set rooms [lreplace $rooms $i $i]
                if {[llength $rooms]} {
                    dict set seenmem $obj $rooms
                } else {
                    dict unset seenmem $obj
                }
            }
        }
    }
    # Learning: believe what you see, and remember where you saw a shiny thing.
    foreach obj $seen {
        dict set bel $obj [frames::fget $obj location]
        if {[frames::fget $obj shiny] eq "1"} {
            set rooms [expr {[dict exists $seenmem $obj] ? [dict get $seenmem $obj] : {}}]
            set i [lsearch -exact $rooms $R]
            if {$i >= 0} { set rooms [lreplace $rooms $i $i] }
            set rooms [linsert $rooms 0 $R]
            if {[llength $rooms] > 4} { set rooms [lrange $rooms 0 3] }
            dict set seenmem $obj $rooms
        }
    }
    frames::fput $npc beliefs $bel
    frames::fput $npc seen $seenmem
    return $baffled
}

# A reactive policy: a thief that covets any shiny thing it BELIEVES it knows
# the whereabouts of -- it must actually have laid eyes on it. Holding loot,
# it flees to its lair. If it has lost track of something it wants, it does
# not give up at once: it SEARCHES, returning to the rooms it remembers seeing
# the thing in, newest lead first, until it finds it or runs out of leads.
# Otherwise it perches and watches (which is how it comes to spot your silver
# in the first place). Because it can only believe in what it has seen, a coin
# shut in a closed pouch is, to the magpie, simply not there.
proc ::game::thief-policy {self} {
    foreach f [contents $self] {
        if {[frames::fget $f shiny] eq "1"} {
            return [list goto [frames::fget $self lair]]
        }
    }
    set bel [frames::fget $self beliefs]
    set loc [frames::fget $self location]
    # 1) Direct pursuit of any shiny it currently believes it can place.
    foreach {obj where} $bel {
        if {$where ne $self && [frames::fget $obj shiny] eq "1"
                && [bel-room $bel $obj] ne ""} {
            return [list fetch $obj]
        }
    }
    # 2) Search: a remembered shiny whose trail has gone cold -- go look where
    #    it was last seen, then the time before that, and so on.
    set seenmem [frames::fget $self seen]
    foreach {obj rooms} $seenmem {
        if {[frames::fget $obj shiny] ne "1"} continue
        if {[dict exists $bel $obj]} continue
        foreach r $rooms {
            if {$r ne $loc} { return [list search $obj $r] }
        }
    }
    return [list patrol]
}

# Another fallible mind, with a different scheme. The pack rat covets shiny
# things it has seen -- including loot in another thief's grasp -- and, once
# it has some, carries it down to its nest to bury it. Its nest is the dark
# cellar, so a fallible rival simply cannot perceive the loot once it is
# stashed: the rat hides its takings exactly where the magpie will not (and
# cannot) look. The contention this sets up converges, because concealment
# ends the chase.
# Theory of mind: choose where to hide loot by reasoning about a RIVAL's
# mind. The rat reads the magpie's beliefs, whereabouts, AND the rooms it
# remembers seeing the loot in -- the very rooms the magpie will search -- and
# picks the first of its preferred hiding rooms that appears in none of them:
# a place the magpie is not, does not expect, and will not think to look.
# Failing that, it falls back on the dark cellar, where no fallible eye can
# follow at all.
#
# And one step deeper still: if the rat has already SPENT a bauble on the
# rival's trail -- planted where the search will begin, or clutched by now in
# the rival's own claw -- then it reasons the search will end right there, at
# the bait, and every room deeper down the trail is safe after all. That is a
# belief about a belief: the rat plans over what the magpie will take itself
# to have found.
proc ::game::rat-hideout {self loot} {
    set avoid {}
    set rival [frames::fget $self rival]
    if {$rival ne "" && [frames::exists $rival]} {
        lappend avoid [frames::fget $rival location]
        set r [bel-room [frames::fget $rival beliefs] $loot]
        if {$r ne ""} { lappend avoid $r }
        set rseen [frames::fget $rival seen]
        set trail {}
        if {[dict exists $rseen $loot]} { set trail [dict get $rseen $loot] }
        if {[llength $trail]} {
            set head [lindex $trail 0]
            set bel  [frames::fget $self beliefs]
            set headed 0 ; set clutched 0
            foreach b [frames::fget $self spent] {
                if {![dict exists $bel $b]} continue
                if {[dict get $bel $b] eq $rival} { set clutched 1 }
                if {[bel-room $bel $b] eq $head} { set headed 1 }
            }
            if {$clutched} {
                # the prop is already in the rival's claw: no search at all
            } elseif {$headed} {
                lappend avoid $head    ;# the search dies at the bait
            } else {
                foreach r $trail { lappend avoid $r }
            }
        }
    }
    foreach nest [frames::fget $self nests] {
        if {[lsearch -exact $avoid $nest] < 0} { return $nest }
    }
    return [frames::fget $self lair]
}

# The pack rat's scheme, now with a ruse in it. The rat grades what it covets
# by WORTH -- a terminal the magpie's coarser treasure-frame does not even
# have -- and will spend a trifle to keep a treasure. Its masterstroke is the
# swap: coveting a treasure in its rival's grasp, it first lets its pocketed
# bauble fall on that very spot, and only THEN snatches the treasure --
# because it knows that the robbed magpie will seize the nearest glitter and
# count itself whole again. It plans over what the other mind will take
# itself to have found.
proc ::game::rat-policy {self} {
    # --- bookkeeping on the pocketed bait ---------------------------------
    set bait [frames::fget $self bait]
    if {$bait ne "" && [frames::fget $bait location] ne $self} {
        # Planted -- or pinched. Spent either way, and never coveted again:
        # the rat knows a prop when it has handled one.
        set spent [frames::fget $self spent]
        lappend spent $bait
        frames::fput $self spent $spent
        frames::fput $self bait ""
        set bait ""
    }
    set want [frames::fget $self bait-want]
    if {$want ne "" && [frames::fget $want location] eq $self} {
        frames::fput $self bait $want ; set bait $want
        frames::fput $self bait-want "" ; set want ""
    }
    set spent  [frames::fget $self spent]
    set bel    [frames::fget $self beliefs]
    set myroom [frames::fget $self location]
    set rival  [frames::fget $self rival]

    # --- holding a treasure: commit to a hiding place and go --------------
    set loot ""
    foreach f [contents $self] {
        if {$f eq $bait} continue
        if {[frames::fget $f shiny] eq "1"} { set loot $f ; break }
    }
    if {$loot ne ""} {
        set nest [frames::fget $self stash-target]
        if {$nest eq "" || ![frames::isa? $nest room]} {
            set nest [rat-hideout $self $loot]
            frames::fput $self stash-target $nest
        }
        return [list bring $loot $nest]
    }
    frames::fput $self stash-target ""

    # --- coveting: the dearest thing it believes it can place -------------
    set hoard [concat [frames::fget $self nests] [frames::fget $self lair]]
    set best "" ; set bestworth 0 ; set bestwhere "" ; set bestroom ""
    foreach {obj where} $bel {
        if {$obj eq $bait || [lsearch -exact $spent $obj] >= 0} continue
        if {$where eq $self || [frames::fget $obj shiny] ne "1"} continue
        set brm [bel-room $bel $obj]
        if {$brm eq ""} continue
        # Anything already lying in one of its own hoard-rooms is, to the rat,
        # already put away -- so it won't endlessly re-shuffle its own cache.
        if {[lsearch -exact $hoard $brm] >= 0} continue
        set w [frames::fget $obj worth]
        if {$w > $bestworth} {
            set best $obj ; set bestworth $w
            set bestwhere $where ; set bestroom $brm
        }
    }
    if {$best ne ""} {
        # THE SWAP, laid in advance: about to rob the rival of something
        # dearer than the bauble in its own pocket, the rat drops the bauble
        # first, on the very spot -- so that when the rival finds itself
        # robbed, the nearest glitter is already waiting to console it.
        if {$bait ne "" && $bestwhere eq $rival && $bestroom eq $myroom
                && $bestworth > [frames::fget $bait worth]} {
            return [list bring $bait $myroom]
        }
        return [list fetch $best]
    }

    # --- idle: keep a bauble about it, for next time -----------------------
    if {$bait eq ""} {
        if {$want ne ""} {
            if {[bel-room $bel $want] ne ""} { return [list fetch $want] }
            frames::fput $self bait-want ""
        } else {
            foreach {obj where} $bel {
                if {[lsearch -exact $spent $obj] >= 0} continue
                if {$where eq $self || $where eq $rival} continue
                if {[frames::fget $obj shiny] ne "1"} continue
                if {[frames::fget $obj worth] > 1} continue
                if {[bel-room $bel $obj] eq ""} continue
                frames::fput $self bait-want $obj
                return [list fetch $obj]
            }
        }
    }
    set post [frames::fget $self post]
    if {$post ne ""} { return [list goto $post] }
    return [list patrol]
}

# Translate a goal into planner goals (evaluated for the current actor).
proc ::game::npc-goals {actor goal} {
    lassign $goal type a b
    switch -- $type {
        goto    { return [list [list at $a]] }
        search  { return [list [list at $b]] }
        fetch   { return [list [list carried $a]] }
        follow  { return [list [list at [dest-room $a]]] }
        bring {
            set goals {}
            if {[frames::fget $a location] ne $actor} {
                lappend goals [list carried $a]
            }
            lappend goals [list at [dest-room $b]]
            return $goals
        }
    }
    return {}
}

# pursue-goal -- one turn of goal-directed behaviour for an NPC. A fallible
# mind acts on what it currently believes, THEN takes in its surroundings --
# so a creature you have just walked past gets a beat to notice you, and one
# that has lost sight of you pursues only your last-known whereabouts.
proc ::game::pursue-goal {frame} {
    variable actor
    variable usebeliefs
    variable beliefs

    set fallible [expr {[frames::fget $frame believes] eq "1"}]

    # Choose this turn's goal from what is currently believed.
    set chooser [frames::fget $frame choose-goal]
    if {$chooser ne ""} {
        frames::fput $frame goal [uplevel #0 [list {*}$chooser $frame]]
    }
    set goal [frames::fget $frame goal]

    set act 1
    if {$goal eq ""} {
        wanderer $frame ; set act 0   ;# an omniscient idler (the cat) roams
    } elseif {[lindex $goal 0] eq "patrol"} {
        set act 0                     ;# perch and watch
    }

    if {$act} {
        lassign $goal type a b
        if {$type eq "fetch" && [frames::fget $a location] eq $frame} {
            frames::fput $frame goal ""
        } elseif {$type eq "bring" && [frames::fget $a location] eq "player"} {
            frames::fput $frame goal ""
        } elseif {$type eq "bring" && [frames::fget $a location] eq $frame
                  && [frames::fget $frame location] eq [dest-room $b]} {
            npc-deliver $frame $a $b ; frames::fput $frame goal ""
        } else {
            set actor $frame
            if {$fallible} { set usebeliefs 1 ; set beliefs [frames::fget $frame beliefs] }
            set plan [ach-seq [npc-goals $frame $goal] {} 0 {}]
            set actor player ; set usebeliefs 0
            if {$plan ne "FAIL"} {
                lassign $plan steps S1
                if {[llength $steps] > 0} { npc-do $frame [lindex $steps 0] }
            }
        }
    }

    # Now look around, learning and being surprised. (Perceiving after acting
    # is what gives a watched creature its moment of noticing.)
    if {$fallible} {
        if {[npc-perceive $frame]} {
            say "[string totitle [the $frame]] casts about, plainly baffled to find nothing of the sort here."
        }
    }
}

# What an NPC is visibly holding, as a trailing clause (or ""). The pocketed
# bait is tucked out of sight, so it is not part of the picture.
proc ::game::npc-carry-desc {actor} {
    set held {}
    set pocket [frames::fget $actor bait]
    foreach f [contents $actor] {
        if {$f eq $pocket} continue
        lappend held [an $f]
    }
    if {[llength $held]} { return ", carrying [join-and $held]" }
    return ""
}

# Carry out one operator as the NPC, narrating only what the player can see.
proc ::game::npc-do {actor step} {
    variable here
    lassign $step verb a b
    set room [frames::fget $actor location]
    set gait [frames::fget $actor gait]
    switch -- $verb {
        go {
            set dest [dict get [frames::fget $room exits] $a]
            frames::fput $actor location $dest
            if {[lit-here]} {
                if {$dest eq $here} {
                    say "[string totitle [the $actor]] $gait in[npc-carry-desc $actor]."
                } elseif {$room eq $here} {
                    say "[string totitle [the $actor]] slips away."
                }
            }
        }
        take {
            set wasloc [frames::fget $a location]
            # Reality check, by sight: the thing must be something the NPC can
            # actually see here -- lying in the room, in an open container, or
            # in someone's hand. A mind acting on a stale belief reaches for
            # what is gone (or shut away out of view) and grasps only air.
            set present [expr {[lsearch -exact [npc-sees $actor $room] $a] >= 0}]
            if {!$present} {
                set bel [frames::fget $actor beliefs]
                dict unset bel $a
                frames::fput $actor beliefs $bel
                if {$room eq $here && [lit-here]} {
                    say "[string totitle [the $actor]] snatches at where it thought [the $a] would be, and comes up empty."
                }
                return
            }
            frames::fput $a location $actor
            # Was it effectively yours -- in your hand, or in something you
            # carry? Then it's a theft, not a tidy-up.
            set mine 0
            set l $wasloc ; set g 0
            while {$l ne "" && [incr g] < 12} {
                if {$l eq "player"} { set mine 1 ; break }
                if {[frames::isa? $l room]} break
                set l [frames::fget $l location]
            }
            if {$mine && $room eq $here && [lit-here]} {
                say "[string totitle [the $actor]] snatches [the $a] from you and makes off with it!"
            } elseif {[frames::exists $wasloc] && [frames::fget $wasloc animate] eq "1"
                      && $room eq $here && [lit-here]} {
                say "[string totitle [the $actor]] wrests [the $a] from [the $wasloc] and is gone!"
            } elseif {$room eq $here && [lit-here]} {
                say "[string totitle [the $actor]] picks up [the $a]."
            }
        }
        drop {
            frames::fput $a location $room
            if {$room eq $here && [lit-here]} {
                say "[string totitle [the $actor]] sets down [the $a]."
            }
        }
        give {
            frames::fput $a location $b
            if {$room eq $here && [lit-here]} {
                say "[string totitle [the $actor]] gives [the $a] to [the $b]."
            }
        }
    }
}

# Completing a `bring`: set the carried thing down. Flavoured by whether it
# is being delivered to the player or stashed away somewhere.
proc ::game::npc-deliver {actor obj dest} {
    frames::fput $obj location [frames::fget $actor location]
    if {[frames::fget $actor location] eq $::game::here && [lit-here]} {
        if {[frames::fget $actor bait] eq $obj} {
            say "[string totitle [the $actor]] lets [the $obj] fall, quite carelessly, just where it stands."
        } elseif {[frames::isa? $dest room]} {
            say "[string totitle [the $actor]] tucks [the $obj] away and turns to go."
        } else {
            say "[string totitle [the $actor]] deposits [the $obj] at your feet, with an air of enormous accomplishment."
        }
    }
}

# ===========================================================================
# ACTION FRAMES -- the verb vocabulary
# ===========================================================================

frames::defframe action {}

frames::defframe look {
    ako     {value action}
    verbs   {value {look l examine x inspect describe}}
    object  {kind thing}
    perform {value ::game::do-look}
}

frames::defframe go {
    ako     {value action}
    verbs   {value {go walk move head climb}}
    perform {value ::game::do-go}
}

frames::defframe take {
    ako        {value action}
    verbs      {value {take get grab pick}}
    object     {kind thing  required 1  question "Take what?"}
    plan-needs {value ::game::plan-needs-take}
    perform    {value ::game::do-take}
}

frames::defframe drop {
    ako     {value action}
    verbs   {value {drop discard}}
    object  {kind thing  required 1  question "Drop what?"}
    perform {value ::game::do-drop}
}

frames::defframe open {
    ako        {value action}
    verbs      {value {open}}
    object     {kind container  required 1  question "Open what?"}
    plan-needs {value ::game::plan-needs-open}
    check      {value ::game::check-open}
    perform    {value ::game::do-open}
}

frames::defframe close {
    ako     {value action}
    verbs   {value {close shut}}
    object  {kind container  required 1  question "Close what?"}
    check   {value ::game::check-close}
    perform {value ::game::do-close}
}

frames::defframe unlock {
    ako        {value action}
    verbs      {value {unlock}}
    object     {kind lockable  required 1  question "Unlock what?"}
    second     {kind key       required 1  question "With what?"
                if-needed ::game::default-key}
    plan-needs {value ::game::plan-needs-unlock}
    check      {value ::game::check-unlock}
    perform    {value ::game::do-unlock}
}

frames::defframe light {
    ako        {value action}
    verbs      {value {light ignite kindle}}
    object     {kind light-source  required 1  question "Light what?"}
    plan-needs {value ::game::plan-needs-light}
    perform    {value ::game::do-light}
}

frames::defframe extinguish {
    ako     {value action}
    verbs   {value {extinguish douse snuff}}
    object  {kind light-source  required 1  question "Extinguish what?"}
    perform {value ::game::do-extinguish}
}

frames::defframe read {
    ako     {value action}
    verbs   {value {read peruse study}}
    object  {kind thing  required 1  question "Read what?"}
    perform {value ::game::do-read}
}

frames::defframe put {
    ako     {value action}
    verbs   {value {put insert place stow}}
    object  {kind thing      required 1  question "Put what?"}
    second  {kind container  required 1  question "Put it in what?"}
    perform {value ::game::do-put}
}

frames::defframe give {
    ako     {value action}
    verbs   {value {give offer hand feed}}
    object  {kind thing    required 1  question "Give what?"}
    second  {kind animate  required 1  question "Give it to whom?"}
    perform {value ::game::do-give}
}

frames::defframe ask {
    ako       {value action}
    verbs     {value {ask talk greet question consult}}
    terminals {value {object topic}}
    object    {kind animate  required 1  question "Ask whom?"}
    topic     {literal 1}
    perform   {value ::game::do-ask}
}

frames::defframe say {
    ako       {value action}
    verbs     {value {say speak chant utter}}
    terminals {value {word}}
    word      {literal 1  required 1  question "Say what?"}
    perform   {value ::game::do-say}
}

frames::defframe ring {
    ako     {value action}
    verbs   {value {ring strike toll}}
    object  {kind ringable  required 1  question "Ring what?"}
    perform {value ::game::do-ring}
}

frames::defframe view {
    ako       {value action}
    verbs     {value {view perspective perspectives reframe lens}}
    terminals {value {lens}}
    lens      {literal 1}
    perform   {value ::game::do-view}
}

frames::defframe turn {
    ako     {value action}
    verbs   {value {turn rotate swing aim}}
    object  {kind turnable  required 1  question "Turn what?"
             if-needed ::game::default-turnable}
    perform {value ::game::do-turn}
}

frames::defframe peer {
    ako     {value action}
    verbs   {value {peer squint gaze}}
    object  {kind viewer  required 1  question "Peer through what?"
             if-needed ::game::default-turnable}
    perform {value ::game::do-peer}
}

frames::defframe wait {
    ako     {value action}
    verbs   {value {wait z rest}}
    perform {value ::game::do-wait}
}

frames::defframe inventory {
    ako     {value action}
    verbs   {value {inventory i inv}}
    perform {value ::game::do-inventory}
}

frames::defframe score {
    ako     {value action}
    verbs   {value {score points}}
    perform {value ::game::do-score}
}

frames::defframe save {
    ako     {value action}
    verbs   {value {save}}
    perform {value ::game::do-save}
}

frames::defframe restore {
    ako     {value action}
    verbs   {value {restore load}}
    perform {value ::game::do-restore}
}

frames::defframe help {
    ako     {value action}
    verbs   {value {help about commands}}
    perform {value ::game::do-help}
}

frames::defframe why {
    ako       {value action}
    verbs     {value {why}}
    terminals {value {}}
    perform   {value ::game::do-why}
}

# frame -- a living glossary. Each term of Minsky's vocabulary is defined
# and then pointed at its own occurrence in the house, so the player can go
# and stand inside the definition. This is the paper, cross-referenced
# against the world it built.
frames::defframe frame {
    ako       {value action}
    verbs     {value {frame}}
    terminals {value {term}}
    term      {literal 1}
    perform   {value ::game::do-frame}
}
proc ::game::do-frame {inst} {
    variable here
    set term [string tolower [join [frames::fget $inst term] " "]]
    set gloss [dict create \
        frame      {"A remembered stereotype of a situation: terminals to fill, defaults standing in for what goes unobserved." "This entire house is one. The dusty tome in the cellar is the paper itself."} \
        terminal   {"A slot on a frame awaiting a particular -- or standing in for the question that situation asks." "The troll's 'wants' terminal is a question; bring the bone and you have answered it."} \
        default    {"A weakly-bound expectation, displaced the moment reality supplies better. Reasoning by example instead of by axiom." "Type \"why\" here: every line under 'Defaults' is a guess the engine is quietly living on."} \
        marker     {"A condition a filler must meet before it may enter a terminal." "Try GIVE LAMP TO TROLL: the give-frame demands an animate second -- the lamp bounces off."} \
        ako        {"A-kind-of: the inheritance link. What is true of the general is presumed of the specific until contradicted." "The troll is a person is a thing; ask WHY after he moves aside."} \
        demon      {"A procedure attached to a slot, fired when a value is added or removed. Expectations with teeth." "Lift the amulet off its pedestal and listen for the gong. That was an if-removed demon."} \
        scenario   {"A script: an ordered set of expected events, confirmed one by one -- and collapsed by disorder." "The inscription in this library describes one. Ring the candle first and feel it unravel."} \
        difference {"A named gap between expectation and observation, with an operator attached that removes it." "In the dark cellar, ask TAKE TOME: darkness is a difference; LIGHT LAMP is its remover."} \
        similarity {"A link between frames labelled by the difference that leads from one to the other." "When OPEN fails on the chest, the engine offers UNLOCK -- that suggestion rode a similarity link."} \
        perspective {"A frame imposed on a scene whose features stay put while their meanings change." "Ask the curator about wine, then VIEW in the cellar: same hooks, same stain, different room."} \
        belief     {"One mind's map of the world -- updated only by what it perceives, so it can be wrong, and fooled." "There are two thieves abroad who act on belief alone. A closed pouch defeats both."} \
        system     {"Frames of the same situation joined by transformations, sharing terminals across viewpoints." "Sweep the telescope full circle: four fields, four shared stars -- the shared corners ARE the figure."} \
    ]
    set ::game::glossary_terms [dict keys $gloss]
    if {$term eq ""} {
        say "Minsky's vocabulary, as this house embodies it:"
        foreach t [dict keys $gloss] { say "  frame $t" }
        say "Any term may be asked about by name."
        return
    }
    if {![dict exists $gloss $term]} {
        say "That word is not one of the framework's. Try: [join [dict keys $gloss] {, }]."
        return
    }
    lassign [dict get $gloss $term] defn where
    say "$term:" ; say "  $defn"
    say "See it in the house:" ; say "  $where"
}

# why -- (action registered above)

frames::defframe quit {
    ako     {value action}
    verbs   {value {quit q exit}}
    perform {value ::game::do-quit}
}

# ===========================================================================
# PERFORM and CHECK procedures
# ===========================================================================

proc ::game::look-around {} {
    variable here
    say ""
    if {![lit-here]} {
        say "It is pitch dark. You can't see a thing."
        return
    }
    say "== [frames::fget $here short] =="
    # If the player has imposed a perspective and it is a perspective OF
    # this room, the room re-describes itself through that frame. The
    # underlying scene is the same; only the framing differs.
    set vp [frames::fget player viewpoint]
    if {$vp ne "" && $vp ne "plain" && [frames::fget $vp of] eq $here} {
        say [frames::fget $vp blurb]
        say "(You are regarding this place through [frames::fget $vp label]. Type \"view plain\" to stop.)"
    } else {
        say [frames::fget $here description]
    }
    # Scenery is woven into the prose above, so it is examinable but not
    # re-listed here.
    set stuff {}
    foreach f [contents $here] {
        if {[frames::fget $f scenery] eq "1"} continue
        lappend stuff [an $f]
    }
    if {[llength $stuff]} { say "You can see [join $stuff {, }] here." }
    set exits [frames::fget $here exits]
    if {[dict size $exits]} { say "Exits: [join [dict keys $exits] {, }]." }
}

proc ::game::do-look {inst} {
    set obj [frames::fget $inst object]
    if {$obj eq ""} {
        look-around
        return
    }
    # "look through telescope" / "look into telescope": if the thing affords
    # a look-through procedure and the player signalled it, defer to that.
    set lt [frames::fget $obj look-through]
    set words [frames::fget $inst words]
    if {$lt ne "" && ([lsearch -exact $words through] >= 0
                  ||  [lsearch -exact $words into] >= 0)} {
        uplevel #0 [list {*}$lt $obj]
        return
    }
    say [frames::fget $obj description]
}

proc ::game::do-go {inst} {
    variable here
    variable dirmap
    set dir [lindex [frames::fget $inst words] 0]
    if {[dict exists $dirmap $dir]} { set dir [dict get $dirmap $dir] }
    if {$dir eq ""} { say "Go where?" ; return }

    # A hostile creature may block a particular exit of its room.
    foreach g [contents $here] {
        if {[frames::fget $g hostile] eq "1"} {
            set bl [frames::fget $g blocks]
            if {[llength $bl] == 2 && [lindex $bl 0] eq $here
                                   && [lindex $bl 1] eq $dir} {
                say [frames::fget $g block-msg]
                return
            }
        }
    }

    set exits [frames::fget $here exits]
    if {[dict exists $exits $dir]} {
        # The frame transformation: reassigning one terminal fires the
        # on-move demon, which swaps the room frame and re-describes it.
        frames::fput player location [dict get $exits $dir]
    } else {
        say "You can't go that way."
    }
}

proc ::game::do-take {inst} {
    set obj [frames::fget $inst object]
    if {[frames::fget $obj animate] eq "1"} {
        say "[string totitle [the $obj]] would object strenuously."
        return
    }
    if {[frames::fget $obj portable] ne "1"} {
        say "[string totitle [the $obj]] won't budge."
        return
    }
    if {[frames::fget $obj location] eq "player"} {
        say "You already have it."
        return
    }
    set holder [frames::fget $obj location]
    set fromCreature [expr {[frames::exists $holder] && [frames::fget $holder animate] eq "1"}]
    frames::fremove $obj location      ;# fires if-removed demons (traps!)
    frames::fput $obj location player
    if {$fromCreature} {
        say "You snatch [the $obj] back from [the $holder]."
    } else {
        say "Taken."
    }
}

proc ::game::do-drop {inst} {
    variable here
    set obj [frames::fget $inst object]
    if {[frames::fget $obj location] ne "player"} {
        say "You aren't carrying that."
        return
    }
    frames::fremove $obj location
    frames::fput $obj location $here
    say "Dropped."
}

proc ::game::do-put {inst} {
    set obj  [frames::fget $inst object]
    set dest [frames::fget $inst second]
    if {[frames::fget $obj location] ne "player"} {
        say "You aren't carrying that."
        return
    }
    if {$obj eq $dest} { say "That would bend space alarmingly." ; return }
    if {[frames::fget $dest open] ne "1"} {
        say "[string totitle [the $dest]] is closed."
        return
    }
    frames::fremove $obj location
    frames::fput $obj location $dest
    say "You put [the $obj] into [the $dest]."
}

proc ::game::do-give {inst} {
    set obj [frames::fget $inst object]
    set who [frames::fget $inst second]
    if {[frames::fget $obj location] ne "player"} {
        say "You aren't carrying that."
        return
    }
    if {[frames::fget $who wants] eq $obj} {
        say [frames::fget $who accept-msg]
        frames::fremove $obj location
        frames::fput $obj location $who
        frames::fput $who satisfied 1   ;# fires the NPC's satisfaction demon
    } else {
        say "[string totitle [the $who]] doesn't seem interested in [the $obj]."
    }
}

proc ::game::do-ask {inst} {
    variable asked
    set who   [frames::fget $inst object]
    set topic [frames::fget $inst topic]
    if {$topic eq ""} {
        say [frames::fget $who greet]
        return
    }
    set topics [frames::fget $who topics]
    if {[dict exists $topics $topic]} {
        say [dict get $topics $topic]
    } else {
        say [frames::fget $who default-reply]
    }
    # Some answers lend you a new way of seeing: a frame is acquired.
    set teaches [frames::fget $who teaches]
    if {[dict exists $teaches $topic]} {
        set persp [dict get $teaches $topic]
        set known [frames::fget player lenses]
        if {[lsearch -exact $known $persp] < 0} {
            lappend known $persp
            frames::fput player lenses $known
            say "(You find you can now picture [frames::fget $persp of-name] through [frames::fget $persp label]. Try \"view\".)"
        }
    }
    # Learning is the game's real economy: a genuinely new fact learned
    # from an archive counts, once. Minsky 3.x -- memory requests filled by
    # consulting what knows. Reward curiosity without making it grindy:
    # re-asking costs nothing but scores nothing.
    set key "$who|$topic"
    if {[dict exists $topics $topic] && [lsearch -exact $asked $key] < 0} {
        lappend asked $key
        set n [llength $asked]
        if {$n <= 6} {
            say "(You have learned something genuinely new to you. \[Insight $n.\])"
            add-score
            if {$n == 6} {
                say "(That is every insight the house holds. The curator would be pleased.)"
            }
        }
    }
}

proc ::game::do-say {inst} {
    set w [frames::fget $inst word]
    say "You speak the word: \"$w\"."
    # Spoken words may be events some scenario is expecting.
    foreach f [frames::all] {
        if {[frames::isa? $f scenario] && $f ne "scenario"
                && [frames::fget $f word] eq $w} {
            scenario-event $f word
        }
    }
}

proc ::game::do-ring {inst} {
    set obj [frames::fget $inst object]
    say "[string totitle [the $obj]] rings out, bright and clear."
    scenario-hook $obj
}

proc ::game::check-open {inst} {
    set obj [frames::fget $inst object]
    if {[frames::fget $obj locked] eq "1"} {
        # Failure annotated with a similarity link to the frame that
        # could remove the difference.
        return [list fail "[string totitle [the $obj]] is locked." unlock]
    }
    if {[frames::fget $obj open] eq "1"} {
        return [list fail "It's already open." {}]
    }
    return ok
}

proc ::game::do-open {inst} {
    set obj [frames::fget $inst object]
    say "You open [the $obj]."
    frames::fput $obj open 1    ;# the on-open-change demon reveals contents
}

proc ::game::check-close {inst} {
    set obj [frames::fget $inst object]
    if {[frames::fget $obj open] ne "1"} {
        return [list fail "It's already closed." {}]
    }
    return ok
}

proc ::game::do-close {inst} {
    set obj [frames::fget $inst object]
    frames::fput $obj open 0
    say "You close [the $obj]."
}

proc ::game::check-unlock {inst} {
    set obj [frames::fget $inst object]
    if {[frames::fget $obj locked] ne "1"} {
        return [list fail "It isn't locked." {}]
    }
    return ok
}

proc ::game::do-unlock {inst} {
    set obj [frames::fget $inst object]
    set key [frames::fget $inst second]
    if {[frames::fget $obj unlocks-with] ne $key} {
        say "[string totitle [the $key]] doesn't fit the lock."
        return
    }
    frames::fput $obj locked 0
    say "You unlock [the $obj] with [the $key]."
}

proc ::game::do-light {inst} {
    set obj [frames::fget $inst object]
    if {[frames::fget $obj lit] eq "1"} { say "It's already lit." ; return }
    frames::fput $obj lit 1     ;# the on-lamp demon narrates and re-views
    scenario-hook $obj
}

proc ::game::do-extinguish {inst} {
    set obj [frames::fget $inst object]
    if {[frames::fget $obj lit] ne "1"} { say "It isn't lit." ; return }
    frames::fput $obj lit 0
}

proc ::game::do-read {inst} {
    set obj [frames::fget $inst object]
    set text [frames::fget $obj reading]
    if {$text eq ""} {
        say "Nothing is written on [the $obj]."
        return
    }
    say $text
    if {[frames::fget $obj prize] eq "1" && [frames::fget $obj scored] ne "1"} {
        frames::fput $obj scored 1
        add-score
    }
}

proc ::game::do-wait {inst} {
    say "Time passes."
}

proc ::game::do-inventory {inst} {
    set stuff {}
    foreach f [contents player] { lappend stuff [an $f] }
    if {[llength $stuff]} {
        say "You are carrying [join $stuff {, }]."
    } else {
        say "You are empty-handed."
    }
}

proc ::game::do-score {inst} {
    say "Your score is [frames::fget player score] of [frames::fget player max-score]."
}

proc ::game::do-save {inst} {
    variable savefile
    if {[catch {frames::save-db $savefile} err]} {
        say "The save failed: $err"
    } else {
        say "The state of every frame has been written to $savefile."
    }
}

proc ::game::do-restore {inst} {
    variable savefile
    variable here
    if {[catch {frames::load-db $savefile} err]} {
        say "There is no saved game to restore."
        return
    }
    set here [frames::fget player location]
    say "The frames remember. Restored."
    look-around
}

proc ::game::do-help {inst} {
    say "Some things to try:"
    say "  look (l), examine <thing>, north/south/east/west/up/down"
    say "  take / drop / put <thing> in <container>"
    say "  open / close / unlock <thing> with <key>"
    say "  light / extinguish <thing>, ring <thing>, read <thing>"
    say "  ask <person> about <topic>, give <thing> to <person>, say <word>"
    say "  view (list framings), view as <role>, view plain"
    say "  look through <thing>, turn <thing> left/right"
    say "  why -- see the frame machinery running on this very place"
    say "  frame, or frame <term> -- Minsky's vocabulary, with house examples"
    say "  inventory (i), score, wait (z), save, restore, quit"
    say "Pronouns work: \"take lamp\" then \"light it\"."
    say "When something is in the way, I may propose a plan -- answer yes or no."
    say "Plans can even cross rooms: ask to take a thing elsewhere and I'll find the route."
}

proc ::game::do-quit {inst} {
    set ::game::running 0
}

# ===========================================================================
# MAIN LOOP
# ===========================================================================

# boot -- load the world and open the first room. Safe to call once.
proc ::game::boot {} {
    variable here
    variable running
    set running 1
    say "THE FRAMEWORK"
    say "An adventure assembled entirely from Minsky frames."
    say "Type \"help\" for a list of verbs."
    set here [frames::fget player location]
    look-around
}

# submit -- one player command, one turn. Returns 0 once the game has quit.
proc ::game::submit {line} {
    variable running
    if {!$running} { return 0 }
    if {[catch {execute $line} err]} {
        say "Something went wrong inside a frame: $err"
    }
    if {$running} { tick }
    return $running
}

proc ::game::start {} {
    variable here
    variable running
    set running 1
    say "THE FRAMEWORK"
    say "An adventure assembled entirely from Minsky frames."
    say "Type \"help\" for a list of verbs."
    set here [frames::fget player location]
    look-around
    while {$running} {
        emit-n prompt "\n> "
        if {[gets stdin line] < 0} { break }
        if {![submit $line]} { break }
    }
    say "Goodbye."
}

proc ::game::emit-n {tag text} {
    puts -nonewline $text
    flush stdout
}
