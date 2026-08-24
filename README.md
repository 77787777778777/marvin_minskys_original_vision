# The Framework

A text adventure engine in Tcl whose entire architecture is taken from
Marvin Minsky's *A Framework for Representing Knowledge* (MIT AI Memo 306,
1974). Everything in the game — rooms, objects, the player, the NPCs, the
verbs, even the unfolding of a ritual — is a Minsky frame, and every game
mechanic is one of the paper's mechanisms.

## Running it

```
tclsh adventure.tcl
```

Requires only a stock Tcl 8.5+ interpreter.

## The game

Seven rooms, three characters, six points:

```
                 [Observatory]      <- the troll guards this stair;
                      |                the telescope hides a frame-system
                  [Landing]
                      |
    [Study] --- [Hallway] --- [Library] --- [Vault]
                      |                  <- the ritual opens this door
                  [Cellar]   (dark; a duck-rabbit if you know how to look)
```

The lamp lights the cellar; the iron key opens the chest (read the tome,
+1); the old bone appeases the troll (+1); past the troll, sweeping the
telescope across the whole sky assembles a hidden constellation (+1); the
candle waits up there too; the curator in the library knows the word; bell
+ candle + word, performed in order before the inscription, open the vault
(+1); the silver amulet leaves its pedestal to the sound of a warning gong
(+1); the curator rewards whoever brings it to him (+1, and the game is
won). A spoiler-free hint system is built in: ask the curator about almost
anything. The cellar can be *re-seen* once the troll and curator lend you
their frames — try `view` there.

<details>
<summary>Full walkthrough (spoilers)</summary>

```
take key / take lamp / north / down / light lamp / take bone
unlock chest / open chest / take tome / read tome
up / up / give bone to troll
north / look through telescope / turn telescope right (x3) / take candle
south / down / east / ask curator about ritual
ring bell / light candle / say frame
east / take amulet / west / give amulet to curator
```
Optional, to see the duck-rabbit cellar: `ask curator about wine`, then on
the landing `ask troll about larder`, then in the cellar `view as merchant`
and `view as butcher`.
</details>

To watch the planner walk the difference network, descend into the cellar
*without lighting the lamp first* (just `take key`, `take lamp`, `north`,
`down`) and type `take tome`. The chest is closed and locked, the tome is
inside it, and the room is pitch dark — yet the engine works out the whole
sequence:

> It is too dark to see and the oak chest is closed. I can light the brass
> lamp, unlock the oak chest with the iron key, and open the oak chest,
> then take the dusty tome. Shall I? (yes/no)

Answer `yes` and it carries out all four operators in order. (Drop the key
on the floor first and it adds *take the iron key* to the front of the
plan; leave the key behind entirely and it can't plan, so it falls back to
the older static hint.)

The planner also routes *across rooms*. Standing in the study with the lamp
and key, type `take tome` (the tome is two rooms away, in a dark cellar,
inside a locked chest):

> It is too dark to see and the oak chest is closed. I can go north, go
> down, light the brass lamp, unlock the oak chest with the iron key, and
> open the oak chest, then take the dusty tome. Shall I? (yes/no)

And a barred edge is just another difference. With nothing in hand but the
key and the lamp, ask from the study for the candle that lies beyond the
troll — whose bone is still down in the dark cellar:

> It is dark along the way and the surly troll bars the way. I can light
> the brass lamp, go north, go down, take the old bone, go up, go up, give
> the old bone to the surly troll, and go north, then take the wax candle.
> Shall I? (yes/no)

That is the whole expedition, assembled by recursion: to take the candle
it must pass the troll; to pass the troll it must give the bone; to give
the bone it must first go and fetch it from the cellar; to see in the
cellar it must light the lamp. The planner works this out by reasoning over
a *projected* world-state — an overlay of the changes its own steps would
make — so that picking the bone up is understood to make the troll's
staircase passable. (It still plans only with what exists and is reachable,
gives the player the whole plan to approve, and leaves the ritual to be
performed deliberately.)

And the very same planner runs the characters. Step into the hallway and
wait a few turns:

> You can see a black cat here.
> The black cat slips away.
> The black cat pads in, carrying a toy mouse.
> The black cat deposits the toy mouse at your feet, with an air of
> enormous accomplishment.

The cat holds a `{bring toy-mouse player}` goal. Each turn its `pursue-goal`
demon points the planner's *actor* at the cat and asks for a plan toward
the goal — routing to the library where the toy lies, picking it up,
routing back to wherever you now are — and takes one step of it. Because
every projected predicate reads through the current actor, the planner is
reasoning about the cat's position and the cat's paws; only the execution
differs. (It tracks you if you wander, gives up gracefully if you go
somewhere it can't follow — past the troll, say — and once it has made its
delivery it returns to ordinary aloof prowling.)

A character can also *react* — and only to what it can actually see. A
thieving magpie perches in the hallway, the crossroads every route runs
through, watching for a glint. Pick up the silver coin in the study, carry
it out to the hallway, and linger:

> You can see a thieving magpie here.
> The thieving magpie snatches the silver coin from your grasp and makes off with it!
> The thieving magpie slips away.

The magpie carries no fixed goal; it carries a `choose-goal` policy it runs
each turn — frame-selection applied to what to want. But it is a *fallible*
mind: it plans over a private map of where it believes things are, built only
from what it has seen. It does not know the coin is in your hands until it
sees it there. Once it does, it forms the goal of taking it and hands that to
the same planner; holding loot, it forms the goal of fleeing to its library
lair, where you can plan your own way and `take coin` to snatch it back.

The trick is that it knows only your *last-seen* whereabouts. Walk past it
with the coin and keep moving — up the stairs, say — and it pursues you to
where it last saw you, finds the trail cold, and gives up; your silver is
safe as long as you don't dawdle in its sight. (Only the coin tempts it;
nothing on the critical path is shiny, so the quest itself is never at its
mercy.)

There is a quieter way to beat it, by working the limits of what it can
perceive. In the study, with the silver coin, is a velvet pouch:

> take coin
> take pouch
> put coin in pouch
> close pouch

Now carry the closed pouch right past the magpie and stand there as long as
you like. It sees you, it sees the pouch — but a closed box is opaque, so it
cannot see the coin, forms no belief about it, and concludes you are carrying
nothing worth taking. Open the pouch in front of it and the coin springs back
into view; the magpie sees it at once and plucks it from your open pouch. The
thing was never out of the room — only out of sight. A frame's terminal is
filled by what can be observed, and what cannot be observed simply isn't
there to be wanted.

And once one mind can be blinded, minds can work against each other. A pack
rat lurks in the library — which is exactly where the magpie carries its
loot to gloat. Let the magpie rob you of the coin and then watch what
becomes of it:

> The thieving magpie snatches the silver coin from you and makes off with it!
> ...
> The pack rat scurries in, carrying a silver coin.

Off in the library, the rat has robbed the robber — and it has done something
stranger and cleverer first. Watch the whole scene by following the magpie
east (the theft happens a beat after you arrive):

> The pack rat lets the scrap of tinsel fall, quite carelessly, just where it stands.
> The pack rat wrests the silver coin from the thieving magpie and is gone!
> The thieving magpie picks up the scrap of tinsel.

That is a *swap*, and it is laid in advance. The rat grades what it covets by
`worth` — the coin is dear, the tinsel in its cheek is trash — but it knows
its rival's treasure-frame has no such terminal: to the magpie, anything
shiny fills the slot. So, about to rob the magpie of something dearer than
the bauble it carries, the rat first lets the bauble fall *on that very
spot*. When the magpie finds itself robbed, the nearest glitter is already
waiting to console it: it seizes the tinsel, counts itself whole, and never
searches at all — while the coin sits glittering, perfectly safe, in the lit
study. The rat has planned over what the other mind will *take itself to have
found* — a belief about a belief — and afterwards it reasons the same way
about its hiding place: with the bait spent onto the magpie's trail, the
search dies there, and rooms the magpie remembers become safe again. Then it
quietly pockets the glass bead from its own hoard, so it has a prop ready for
next time.

The magpie is no pushover, though: the deception only exists because the
searching mind it works on is real. Rob it of something and it does not give
up — it returns to each room it remembers the thing being in, newest lead
first, until it finds it or its leads run out. You can watch this play out
two ways. Steal past it with the *bead* and the rat, unwilling to swap a
bauble for a bauble, simply robs and hides it — and the magpie hunts: it
casts about the hallway where it last saw its prize, baffled, before giving
up. Or strip the rat of its tinsel and the coin heist itself reverts to pure
evasion: the rat consults the magpie's beliefs, whereabouts, and remembered
rooms — the very rooms it is about to search — and carries the coin to a lit
room that appears in none of them, falling back on the dark cellar only when
no lit room is safe. Either way the dust settles, the rat returns to its
post, and you can walk in and pick your property up.

The magpie has one more weakness worth knowing. Its frame for treasure
matches on a single feature — anything *shiny* — and so it cannot tell silver
from glass. Carry the worthless glass bead from the study past it:

> The thieving magpie snatches the glass bead from you and makes off with it!

It snatches the bauble as greedily as it would the coin, and bears it off to
gloat over a piece of junk. A frame recognises by its salient features, and
whatever fills those features it will take to be the thing — which is exactly
what lets a decoy work.

## How the paper maps onto the code

| Minsky's concept | Where it lives | What it does in the game |
|---|---|---|
| Frames as stereotyped situations | `frames.tcl`, `defframe` | `thing`, `room`, `container`, `key`, `person`, `scenario` are stereotypes; `oak-chest` and the troll are individuals |
| Terminals (slots) and assignments | slot/facet dict, `fget`/`fput`/`fremove` | `location`, `lit`, `exits`, `topics`, `wants`... |
| Default assignments, "loosely attached" | the `default` facet | a generic room is lit, a generic person replies "There is no reply."; individuals override only where reality differs |
| AKO hierarchy / inheritance | `ako` slot, `ako-chain` | `troll` → `person` → `thing`; defaults and demons are found by climbing the chain, nearest frame first |
| Procedural attachment: *if-needed* | `if-needed` facet | the chest's, pedestal's, and troll's descriptions are computed from their state at the moment you look |
| Procedural attachment: *if-added* demons | `if-added` facet, fired by `fput` | lighting the lamp narrates itself; opening a container reveals its contents; moving the player redraws the world; satisfying an NPC fires its gratitude; scoring announces itself |
| Procedural attachment: *if-removed* demons | `if-removed` facet, fired by `fremove` | lifting the amulet from its pedestal sounds a gong — `take` retracts the old `location` value before assigning the new one, so removal demons act as traps |
| Markers and conditions on terminals | `kind`, `required`, `literal` facets | `unlock` demands a `lockable` object and a `key`; `ask` takes an `animate` object and a raw-word topic |
| Matching / instantiation | `::game::execute` | each command instantiates an action frame and fills its terminals from your words and the things in view |
| Best-fit matching and clarification | `match-run` | "brass lamp" outscores a single-word match; a tie produces *"Which do you mean: the brass lamp or the brass bell?"* — the system asking which stereotype to instantiate |
| Focus of attention / current frame | the player's `focus` terminal | pronouns resolve against the frame you last referred to: "take lamp" then "light it" |
| Default assignment during matching | `if-needed` on action terminals | "unlock chest" assumes whatever key you're carrying (`default-key`) |
| Frames ask about unconfirmed expectations | `question` facet | an unfillable required terminal becomes a question: "Unlock what?", "Give it to whom?", "Say what?" |
| Excuses when expectations fail | `check` procedures | "The oak chest is locked." |
| Similarity network with difference links | third element of a `check` failure | a failed `open` points along its difference link: *(Perhaps "unlock" would transform this situation.)* |
| The matching process: walking the difference network | `try-plan`, `achieve`, the `difference` frames | when an action can't be performed, the engine recursively resolves the blocking differences and assembles the chain of operators that would make it possible — means-ends analysis grounded in frames |
| Operators with their own preconditions | `plan-needs` facet on action frames | each operator the planner proposes is itself an action frame whose preconditions are sub-differences, resolved by the same recursion (the flagship: in a dark cellar, "take tome" plans *light the lamp → unlock the chest → open it → take the tome*) |
| Transforming the situation until it fits | the yes/no plan offer, `run-plan` | the assembled transformation sequence is offered to the player and, on assent, performed operator by operator, each step's demons firing as it goes |
| Composing transformations across place-frames | `room-of`, `find-route`, `cross-plan` | name a thing in another room and the planner BFS-routes there over the `exits` graph, then resolves the access differences at the destination — navigation and the difference network unified |
| A barred edge as a difference on a transformation | `edge-guard`, guard-gives in `find-route` | the troll-blocked staircase is an edge the route-finder will only cross by first giving the troll the bone it wants, exactly as a locked door is crossed by unlocking |
| Planning over a projected world-state | the `p-*` predicates, `apply-op`, `ach`/`plan2` | to see that picking up the bone makes the troll's edge passable, the planner reasons over an evolving overlay of the changes its own steps would make, rather than against the world as it is now |
| Setting up the conditions a transformation needs | recursive sub-goals (fetch → light → take → give) | from the study, "take candle" plans the whole expedition — *go down to the dark cellar, light the lamp, take the bone, climb back up, give it to the troll, then go and take the candle* — fetching a sub-goal item across rooms to enable a later step |
| Agents pursuing goals of their own | the `actor` variable, NPC `goal` terminals, `pursue-goal` | every projected predicate reads through a current *actor*, so the same planner reasons for an NPC; the black cat carries a `{bring toy-mouse player}` goal and works it out one step per turn |
| One model, many minds | `npc-goals`, `npc-do` | deciding the next step is the shared planner with the actor swapped; only execution differs, so the cat's fetch-and-carry *is* the player's expedition, run for a cat |
| Choosing which goal to hold | the `choose-goal` policy, `thief-policy` | a reactive character re-selects its goal each turn from what it perceives — frame-selection applied to *what to want* — so the magpie that sees something shiny in your hands forms, on the spot, the goal of coming to take it |
| Two agents contending over one world | the magpie's steal-and-flee loop, reclaim via `do-take` | the magpie plans to seize the coin you carry and flee to its lair; you can plan your way to its lair and snatch it back — two planners pulling on the same objects, each over the same world |
| A frame is an expectation, not the truth | the `beliefs` slot, `usebeliefs` in `p-loc` | a fallible mind plans over a *private* map of where it thinks things are; about anything it has never seen it has no idea, and cannot plan to reach it |
| Filling a frame from observation | `npc-perceive`, `npc-sees` | each turn the mind learns the true location of everything it can see in its lit room — believing what it sees, and nothing it can't |
| When the expected and the observed disagree | the contradiction sweep in `npc-perceive`, the reality check in `npc-do` | expecting the coin in a room and not finding it, the mind is *surprised* and forgets; reaching for a thing already gone, it grasps only air — and updates |
| Acting on stale knowledge | `pursue-goal` perceiving *after* it acts | a creature you just walked past gets a beat to notice you, and one that has lost sight of you pursues only your last-known whereabouts — so keep moving and the thief loses your trail |
| A terminal filled only by what's observable | `npc-sees`, `npc-see-into` | perception descends through open containers and into hands, but a closed box is opaque — what it holds is, to a watching mind, simply not there |
| Defeating a mind by working its blind spots | the velvet pouch + the sight-based reality check in `npc-do` | drop the coin in a closed pouch and the magpie, staring right at you, cannot perceive it, forms no belief about it, and leaves you be — deception by concealment, not by force |
| Two fallible minds over one world | the magpie and the pack rat, each with its own `beliefs` and policy | the magpie covets what it sees in your hands; the rat covets what it sees in *anyone's* hands, the magpie included — so it lurks where the magpie hoards and robs the robber (`wrests` it away) |
| A frame that models another mind | `rat-hideout` reading the magpie's `beliefs`, location, and sighting-memory | the rat doesn't merely flee the magpie's eyes — it reads the magpie's mind, and hides the coin in a lit room the magpie is not in, does not believe the coin to be, and does not *remember* seeing it: somewhere outside the magpie's whole search |
| Searching a remembered structure | `thief-policy`'s search branch + the `seen` sighting-memory in `npc-perceive` | rob the magpie and it does not give up — it returns to the rooms it recalls the coin being in, newest lead first, looking room by room, and gives up only when its memory of leads is spent |
| Deception that plans over a mind, not past it | the choice in `rat-hideout`, falling back to the dark `lair` | the rat hides the coin one step ahead of the magpie's search; only when its model says every lit room will be searched does it resort to burying the loot in the dark, where senses fail outright |
| Two frames for one thing, one finer than the other | the `worth` terminal + `rat-policy`'s grading of loot | the rat's frame discriminates worth; the magpie's matches on bare glitter — and the swap lives precisely in that gap, because to the coarser frame a scrap of tinsel *is* the recovered treasure |
| A belief about a belief | the pre-planted swap in `rat-policy`; trail neutralization in `rat-hideout` | about to rob the magpie, the rat first drops its bauble on that very spot, planning over what the robbed magpie will take itself to have found — then reasons that the search dies at the bait, so rooms deeper down the remembered trail are safe again |
| Matching on a salient feature, and being fooled | the `glass-bead` decoy + the `shiny`-keyed policies | the magpie's "loot" frame matches on one feature — *shiny* — so a worthless glass bead fills the slot as well as silver does, and the magpie will snatch and treasure the bauble exactly as if it were the coin |
| Frame transformations between viewpoints | `location` slot + `on-move` demon | moving between rooms is literally one `fput`; what you carry persists across the transformation, like shared terminals between Minsky's room frames |
| Different frames over one scene (the duck-rabbit) | the `perspective` stereotype, the `view` verb | the cellar is one room with one set of features; framed as a larder its iron is meat-hooks and its stain is blood, framed as a wine cellar the same iron is an empty rack and the same stain is spilled wine |
| Shared terminals read from many viewpoints | a feature is one frame; `describe-by-viewpoint` | the hooks and the stain are single frames whose meaning is supplied by whichever frame the observer holds — one terminal, many readings |
| Frames are acquired, not innate | `teaches` facet on NPCs | you cannot adopt the butcher's framing until the troll lends it to you, nor the merchant's until the curator does |
| Frame-systems: members joined by transformations | the telescope (`aim`, `ring`, `skyview` frames) | the night sky is a ring of view-frames; turning the telescope is a transformation to an adjacent member of the system |
| Shared terminals as the structure of a system | `sky-shared`, the four corner stars | adjacent sky-views share a boundary star; those four shared stars are exactly the corners of the constellation "the Frame" — the shared terminals *are* the figure |
| Object permanence through a transformation | the hinge narration in `do-turn` | the shared star visibly slides from one edge of the field to the other as you rotate, the one thing both frames hold in common |
| Scripts / scenarios | the `scenario` stereotype, `scenario-event` | the ritual is an ordered expectation (bell, candle, word): confirmed steps are narrated, an out-of-order event collapses the half-built structure and the frame explains what it expected, and completion transforms the world (a door appears) |
| Discourse frames | `person` terminals: `topics`, `greet`, `default-reply`, `wants` | "ask curator about frames" is a dict lookup on a discourse frame; "give bone to troll" satisfies an NPC's `wants` expectation and fires its demon |
| Expectation vs. observation | darkness handling | in an unlit room the room frame's terminals are invisible; only your carried frames remain in scope |
| The world as one knowledge base | `save` / `restore` | the entire game state is the frame database — one dict — so persistence is writing it to `framework.sav` and reading it back |

## The three layers

**`frames.tcl` (~200 lines)** — the knowledge representation, with no game
knowledge in it at all. Frames are entries in one dict mapping
`frame → slot → facet → value`. Retrieval (`fget`) follows Minsky's
preference order *within* each frame — explicit value, then default, then
if-needed procedure — climbing the AKO chain from most to least specific.
Assignment (`fput`) and retraction (`fremove`) fire the nearest attached
demon. `save-db`/`load-db` serialize the whole world.

**`engine.tcl`** — the adventure machinery. Verbs are action frames; the
parser is a frame matcher with longest-run noun matching, ambiguity
questions, pronoun focus, and literal terminals for topics and spoken
words. Scenario frames implement scripts; the `view` verb imposes a
perspective on a scene; the telescope is navigated as a frame-system; and
a difference network lets the engine *walk* the similarity links — when an
action can't be performed, the planner recursively resolves the blocking
differences into a chain of operators, routing across rooms and even
fetching the items a later step will need (reasoning over a projected
world-state), then offers to carry it out. The same planner, with its actor
swapped, drives the NPCs: a character with a `goal` takes one planned step
toward it each turn, one with a `choose-goal` policy re-decides that goal
each turn, and one marked `believes` plans over a *private, fallible* map of
where it thinks things are — `usebeliefs` makes the planner read object
locations through that map instead of the truth — updating it from what it
perceives, so the magpie reacts only to loot it has actually seen in your
hands — and never to a coin shut inside a closed pouch, since perception
descends through open containers but a closed box is opaque. Two such minds
run side by side — the magpie and the pack rat — each with its own beliefs
and a `seen` memory of where it has spotted shiny things. The magpie, robbed,
*searches* that memory room by room rather than giving up; the rat grades
loot by `worth` (a terminal the magpie's coarser frame lacks), keeps a
worthless bauble tucked out of sight in its cheek — a pocket is a closed
container — and, robbing the magpie of a treasure, drops the bauble on the
spot first, so the robbed bird seizes the glitter, counts itself whole, and
never searches. Failing that ruse, the rat hides its loot in a lit room
outside the magpie's whole remembered search; and a worthless `shiny` bead
fools the magpie's treasure-frame as readily as silver. After
every command, `tick` fires the `each-turn` demon of any frame that
declares one — which is the entire implementation of the wandering cat.
The main loop is: tokenize, select an action frame by verb, instantiate
it, fill terminals by matching, fall back on terminal defaults, complain
about unmet expectations or offer a plan, run the precondition check (with
similarity links on failure), perform, discard the instance, tick.

**`world.tcl`** — almost pure declaration: stereotypes, then individuals
that override a handful of terminals each. The only procedures are demons
and if-needed describers referenced from slots. The curator's entire
knowledge of the world is one `topics` dict on his frame; the two ways of
seeing the cellar are two `perspective` frames over the same room; the
night sky is four `skyview` frames in a ring.

## Extending the world

A new room is a frame, and re-calling `defframe` extends an existing one,
so wiring in a door is one line:

```tcl
frames::defframe attic {
    ako         {value room}
    short       {value "The Attic"}
    description {value "Cobwebs and one round window."}
    exits       {value {down landing}}
}
frames::defframe landing { exits {value {down hallway  north observatory  up attic}} }
```

A new character is a frame with discourse terminals:

```tcl
frames::defframe ghost {
    ako           {value person}
    short         {value "translucent ghost"}
    names         {value {ghost spirit}}
    location      {value attic}
    greet         {value "\"Whooo,\" the ghost offers, half-heartedly."}
    default-reply {value "The ghost shrugs, which takes visible effort."}
    topics        {value { house "\"I only haunt it. I never understood it.\"" }}
    wants         {value dusty-tome}
    accept-msg    {value "The ghost clutches the tome and begins, at last, to read."}
    satisfied-msg {value "It fades contentedly into the rafters."}
}
```

A new puzzle is usually just a demon: attach `if-added` (or `if-removed`)
to some slot and let assigning a value do the storytelling. A new
multi-step puzzle is a `scenario` frame: list the `steps`, give each
participating object a `scenario-role`, and write the narration.

A new way of seeing a room is a `perspective` frame plus a shared feature
or two that reinterpret themselves through it:

```tcl
frames::defframe attic-as-nursery {
    ako   {value perspective}
    of    {value attic}        ;# which scene this frames
    of-name {value "the attic"}
    label {value "a parent's eye"}
    blurb {value "Seen as a nursery-in-waiting, the clutter resolves into furniture under sheets..."}
}
frames::defframe attic { perspectives {value {nursery attic-as-nursery}} }
# and a scenery feature whose description is computed by viewpoint:
frames::defframe dust-sheets {
    ako         {value thing}
    location    {value attic}   portable {value 0}   scenery {value 1}
    names       {value {sheets dust cloths}}
    description {if-needed ::game::describe-by-viewpoint}
    lens-notes  {value {
        plain             "White sheets thrown over shapeless mounds."
        attic-as-nursery  "A crib and a rocking-chair, sleeping under dust."
    }}
}
```

Have an NPC `teaches` it (`teaches {value {nursery attic-as-nursery}}`) and
the framing becomes something the player must be *given*, not something
they start with.

A new obstacle the planner can route around is a `difference` frame plus a
`plan-needs` procedure on the actions it blocks. A difference says how to
detect itself, which operator removes it, and how to fill that operator's
terminals:

```tcl
frames::defframe diff-barred {
    ako  {value difference}
    test {value ::game::dp-barred}   ;# present? proc {target}->bool
    oper {value lift}                ;# the action frame that removes it
    desc {value ::game::dd-barred}   ;# obstacle phrase proc {target}->string
}
proc ::game::plan-needs-go {obj second} {
    # if a portcullis bars the way, the planner will route through `lift`
    if {[dp-barred $obj]} { return [list [list diff-barred $obj]] }
    return {}
}
frames::defframe go { plan-needs {value ::game::plan-needs-go} }
```

A self-directed character needs only a `goal` and the `pursue-goal` demon:

```tcl
frames::defframe ghost {
    ako       {value person}
    short     {value "translucent ghost"}
    names     {value {ghost spirit}}
    location  {value attic}
    each-turn {value ::game::pursue-goal}
    goal      {value {follow player}}   ;# or {bring O dest}, {fetch O}, {goto R}
}
```

It will plan toward that goal one step per turn, using the same machinery
the player's commands do. Because the planner reads the world through the
current actor, the ghost reasons about its own position and possessions; if
the goal becomes impossible (you slip somewhere it cannot reach) it waits.

To make it *react*, give it a `choose-goal` policy instead of a fixed goal —
a procedure that returns the goal to hold this turn:

```tcl
proc ::game::guard-policy {self} {
    # come looking whenever the player is somewhere the guard can reach
    if {[room-of player] ne [frames::fget $self location]} {
        return [list goto [room-of player]]
    }
    return [list goto [frames::fget $self lair]]   ;# else return to post
}
frames::defframe guard {
    ako {value person}  each-turn {value ::game::pursue-goal}
    choose-goal {value ::game::guard-policy}  lair {value gatehouse}
}
```

Add `believes {value 1}` and the guard becomes *fallible*: it plans over a
private map updated only from what it sees, so `guard-policy` should consult
`[frames::fget $self beliefs]` rather than the true world. Now it comes
looking only where it last glimpsed you, can be given the slip, and is
surprised to arrive and find you gone.

A hiding place is just a container — and against a fallible mind any closed
container is one, because `npc-sees` will not look inside it. Make it
`portable {value 1}` (like the velvet pouch) and you can carry your secret
through a watcher's very room; leave it `portable {value 0}` (like the oak
chest) and it is a strongbox bolted to the floor. Either way, what is shut
inside is, to every fallible mind, not there to be wanted.

Rivals are free. Give a second creature `believes {value 1}`, its own
`choose-goal` policy, and a `lair`, and it plans over its own private world
alongside the first — the engine runs each in turn with the actor and belief
map swapped. Every believing mind also keeps a `seen` memory — object →
rooms-seen-in, newest first — which `npc-perceive` fills as it spots things
and prunes as it looks and finds them gone. The magpie's `thief-policy` uses
that memory to *search*: with no current lead it walks its remembered rooms
one per turn until it finds the thing or runs out. The pack rat goes a step
further: a `rival` slot names the mind it models, and `rat-hideout` reads
*that mind's* beliefs, location, and `seen` memory to pick, from its `nests`,
a lit room the rival will neither occupy, expect, nor search — hiding its loot
past the other's whole search rather than its senses, and falling back to the
dark `lair` only when cornered. A `post` slot sends it back to its lurking
ground when idle, so it never camps on its cache.

The ruse takes four slots more. Give things a `worth` and a mind that reads
it, and give the schemer a `bait` pocket (whatever it holds there is hidden
from other eyes, like any closed container, and omitted from what it visibly
carries), a `bait-want` for the bauble it has set out to pocket, and a
`spent` list of props it will never covet again. `rat-policy` then does the
rest: coveting something *dearer* than its pocketed bauble in the rival's
own grasp, it drops the bauble on that spot first and robs second — never
like-for-like, a bauble is not spent to win a bauble — and `rat-hideout`,
seeing a spent prop believed planted at the head of the rival's trail (or
already clutched in its claw), strikes the neutralized rooms from the set it
must avoid. When idle and empty-cheeked, the policy quietly re-provisions:
it pockets the cheapest bauble it believes in, raiding even its own hoard
for props. And a decoy needs no code at
all: a `glass-bead` with `shiny {value 1}` fills the same terminal the coin
does, so any mind whose policy keys on `shiny` will covet the bead exactly as
much — point that at the magpie and you have a lure.

## Things deliberately kept simple

Single inheritance, one value per terminal, a small fixed set of terminal
names per verb, and clarification questions that ask you to retype rather
than holding a pending frame open (the one exception is the planner's
yes/no, which does hold a frame open). The planner reasons over a projected
world-state and can route across rooms, fetch the items a later step needs,
and drive an NPC toward a goal of its own — fixed, chosen afresh each turn,
or pursued over a private and fallible picture of where things are, a picture
you can defeat by hiding a thing from its sight — but it plans only with what
exists and is reachable, and it leaves the social and ritual puzzles for the
player to solve deliberately. The fallible mind tracks only object locations
(extended just far enough that a closed box hides what it holds); it takes the
rest of the world — which doors are locked, which rooms are lit — on faith.
Natural next steps: multi-valued terminals (a slot holding several fillers at
once); an optimiser that prunes the occasional redundant step from a long
plan; beliefs about *more* than location, so a creature could be wrong about
a locked door or a dark room and plan around the mistake; or minds that
trade rather than steal — a curator who *pays* in something a thief-frame
values, so that worth stops being private arithmetic and becomes a price.
The swap the rat plays on the magpie already reaches one level down into
another mind's future belief; each of these is one small frame further.
