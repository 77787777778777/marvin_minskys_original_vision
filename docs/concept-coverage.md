# Concept coverage audit

A full read-through of both source papers against the engine, concept by
concept. AIM-306 = *A Framework for Representing Knowledge* (Minsky, 1974,
82 pp., scanned; read via page OCR). Steps = *Steps Toward Artificial
Intelligence* (Minsky, Proc. IRE, 1961).

## Verdict in one line

Every load-bearing concept of AIM-306 is implemented and playable. The
engine's planner, perception and learning loops are also direct
implementations of the five areas of *Steps* (Search, Pattern-Recognition,
Learning, Planning, Induction) -- mostly by construction, since frames are
the representation both papers converge on. Gaps found were small; each has
been closed or explicitly noted below.

## Part 1: AIM-306 (the frame paper)

### Section 1: Frames

| # | Paper concept | Status | Where / how |
|---|---|---|---|
| 1 | Frame = data-structure for a stereotyped situation | DONE | `frames::defframe`; stereotypes `thing room container key person scenario perspective skyview action difference`, individuals override terminals |
| 2 | Network of nodes and relations | DONE | one dict `frame -> slot -> facet -> value`; slots are relations between frames |
| 3 | Top levels fixed, lower levels have terminals | DONE | AKO top-level structure inherited; instance frames fill terminals |
| 4 | Terminals ("slots") filled by instances/subframes | DONE | `fget/fput/fremove`; subframe assignments (e.g. `perspectives {value {butcher cellar-as-larder ...}}`) |
| 5 | Markers: conditions on terminal assignments | DONE | `kind` (AKO or property test), `required`, `literal` facets checked in `execute` |
| 6 | Assignments usually smaller subframes | DONE | e.g. `skyview` frames as telescope terminals; `perspective` frames on the cellar |
| 7 | Default assignments attached "loosely" | DONE | `default` facet; displaced by any assignment (`fput` overwrites); generic-room-lit, generic-person-reply |
| 8 | Defaults as variables / reasoning by example | DONE | `default-key` on unlock (defaults as variables); glass-bead decoy (a default-like exemplar standing in for the class) |
| 9 | Frame-systems: related frames sharing terminals | DONE + flagship | the telescope: four `skyview` frames in a ring whose corner stars are SHARED terminals; turning the telescope is the transformation; the shared corners literally assemble into "the Frame" constellation |
| 10 | Transformations between frames of a system mirror actions | DONE | `on-move`: moving is one `fput location`; carried things persist across the transform like shared terminals |
| 11 | Different frames of a system = different viewpoints of ONE scene | DONE + flagship | duck-rabbit cellar: two `perspective` frames over the same room; same iron hooks, same stain, different readings via shared-terminal `lens-notes` |
| 12 | Shared terminals make information from different viewpoints co-ordinate | DONE | `describe-by-viewpoint`: a feature is ONE frame; its description is computed through whichever lens the player holds |
| 13 | Matching process assigns values consistent with markers | DONE | `execute`: instantiate action frame, fill terminals by longest-run match against names, kind-check each filler |
| 14 | Matching partly controlled by current goals | DONE | wide/global match accepts out-of-reach referents provisionally so the PLANNER can make them reachable; planner itself goal-driven |
| 15 | Information obtained when matching fails selects an alternative frame | DONE | `check` failure returns `{fail msg similarityLink}`: "(Perhaps \"unlock\" would transform this situation.)"; the difference network then walks that link |
| 16 | Difference network / replacement frame retrieval | DONE | `difference` frames (`diff-dark diff-closed diff-locked diff-uncarried`) with `test/oper/findo/finds`; `achieve` recursion resolves differences into operator chains |
| 17 | Subframes: scene analysis decomposes into parts | PARTIAL->NOTED | containers/contents and wall-object style nesting exist (chest contents, pedestal), but there is no 3x3 spatial-array wall subframe; recorded under Deliberate simplifications |
| 18 | Perspective & viewpoint transformations (1.8) | DONE | telescope ring = literal viewpoint transformations; rooms joined by exits are viewpoint frames for locomotion; Piaget epigraph theme embodied by `view` verb needing taught lenses |
| 19 | Occlusions (1.9) | PARTIAL->BY DESIGN | darkness hides room terminals entirely; closed pouch occludes its contents from NPC sight (`npc-see-into` refuses closed containers); no partial visual occlusion geometry -- deliberate |
| 20 | Imagery = assignments to frame terminals (1.10); seeing vs imagining differ in flexibility of assignments | DONE | `view as butcher` re-describes the SAME room through a different frame -- imagination reassigning weakly-bound readings; plain `look` resists (reality keeps reasserting the plain view unless you hold the lens) |
| 21 | Default assignment: never stored unassigned; weakly-bound stereotypes (1.11) | DONE | every stereotype carries defaults at every gameplay terminal; NPCs' treasure-frame keys on the single salient feature `shiny` -- exactly a counter-productive stereotype, and the bead decoy exploits it |
| 22 | Frames and Piaget's concrete operations (1.12): applying vs reasoning ABOUT transformations | DONE (thematic) | perspectives must be TAUGHT before they can be imposed (`teaches`/`lenses`); you cannot reason about a framing you do not possess -- the game's own nod to formal-vs-concrete operations |

### Section 2: Language, understanding, scenarios

| # | Paper concept | Status | Where / how |
|---|---|---|---|
| 23 | Sentence frames; grammaticality vs meaning as degrees of terminal satisfaction | PARTIAL->NOTED | parser fills verb/action frames and complains per unsatisfied required terminal ("Unlock what?"); no graded syntax model -- deliberate |
| 24 | Pronoun reference resolved by scenario knowledge, not just recency | DONE | pronoun `focus` terminal; NPC-side analogue is Charniak-grade: rat's swap depends on resolving what the magpie will believe about "the glitter" |
| 25 | Scenario frames: stereotyped event sequences with expected order | DONE + flagship | `scenario` stereotype; the ritual: steps {bell candle word}, progress pointer, murmurs on confirmation, finale transforms the world, order-hint on collapse |
| 26 | Events feed scenario frames; out-of-order collapses progress | DONE | `scenario-event`: match advances (+narration), known-but-out-of-order event resets progress and explains what it expected |
| 27 | Objects carry scenario roles | DONE | `scenario-role {value {ritual bell}}`; `scenario-hook` fires on ring/light/say |
| 28 | Discourse frames: topics, questions a person answers | DONE | `person` frames with `topics greet default-reply wants accept-msg satisfied-msg teaches` |
| 29 | Charniak-style default-driven comprehension (party/piggy-bank) | DONE (thematic) | curator's topic answers hand you framing knowledge; the ritual expects the word "frame" -- the game knows its own name is the password |
| 30 | Terminals ARE the questions a situation asks (2.8) | DONE | `question` facet: unfilled required terminals become asked questions verbatim ("Take what?", "Give it to whom?") |

### Section 3: Learning, memory, paradigms

| # | Paper concept | Status | Where / how |
|---|---|---|---|
| 31 | Expectation/Elaboration/Alteration/Novelty/Learning as memory requests | PARTIAL->DONE ENOUGH | expectation+elaboration = matching/planner; alteration = difference-network frame replacement (unlock instead of open); novelty = "(Perhaps...)" complaint when nothing fits; learning = lenses acquired from NPCs |
| 32 | Frames stored with weakly-bound defaults, not blanks | DONE | all stereotype terminals defaulted; see #21 |
| 33 | Matching: retain common terminals when replacing a frame (3.2 cost E/F argument) | DONE (structural) | plan steps preserve already-satisfied goals (ach returns {} for already-true goals; visited-set prevents undoing them); the planner never re-plans what already holds |
| 34 | Excuses: explain away misfits rather than replace (3.3) | DONE | `check` messages distinguish "It's already open." (no-op) from "The oak chest is locked." (excusable -> similarity link -> unlock); toy-chair pattern echoed by "worth" grading |
| 35 | Advice: frames contain explicit knowledge about their own trouble | DONE | `plan-needs` procedures ON the action frames declare what trouble means for them; `order-hint` on scenario explains its own failure |
| 36 | Similarity network with difference-labelled pointers (Winston) | DONE + flagship | the `difference` frames ARE labelled pointers between action frames; `(Perhaps "unlock"...)"` is a walk along one; guarded edges and locked doors join the same network |
| 37 | Clusters/classes/geographic analogy (3.5) | DONE (thematic) | AKO hierarchy IS the class lattice; the map layout (rooms as places reached by routes) is the geographic analogy made playable |
| 38 | Analogies and alternative descriptions (3.6) | DONE | the two descriptions of the cellar (larder/wine) are alternative descriptions over shared terminals; generator example (mechanical vs electrical views of one thing) is the direct ancestor of the duck-rabbit |
| 39 | Summaries: frames for heuristic search results (3.7) | DONE (mechanism) | the plan offer summarizes the search: obstacle phrase + step chain + yes/no; `plan-obstacles` produces the human-readable summary of what stood in the way |
| 40 | Frames as paradigms (Kuhn) (3.8) | DONE (thematic) | acquiring the butcher's framing changes what the cellar IS to you -- a paradigm shift you can play |

### Sections 4-6: control, imagery, critique of logic

| # | Paper concept | Status | Where / how |
|---|---|---|---|
| 41 | Control: thinking = finding and instantiating a frame | DONE | the main loop IS that sentence: select action frame, instantiate, fill, verify, perform |
| 42 | Fahlman packet activation / verification levels | NOTED | satisfaction levels appear as check severity (already-open vs locked vs wrong-key); full packet architecture out of scope -- recorded |
| 43 | Demons for noticing; decision-tree default ordering; compromise of the two | DONE | `if-added/if-removed/if-needed` demons everywhere (gong, lamp narration, reveal-on-open); default ordering = fget preference value>default>if-needed; surprises (demons) override defaults -- the gong interrupts everything |
| 44 | Weak default processing superceded by demon surprises | DONE | each-turn ticks + demons fire regardless of player intent; the magpie's surprise on finding the trail cold is a demon-like update |
| 45 | Spatial imagery: global space-frame, headings (5.x) | PARTIAL->BY DESIGN | rooms + exits graph is the space frame; no compass headings -- deliberate scope choice |
| 46 | Sec.6: logic poorly suited; consistency too strong; defaults beat axioms | DONE (stance) | the engine never proves anything: it matches, defaults, excuses, and plans -- Minsky's program statement, running |

## Part 2: Steps Toward AI (1961)

*Steps* predates frames; its five problem areas are all present because the
planner implements them directly:

| Area | Status | Where |
|---|---|---|
| I. Search (exhaustive, hill-climbing, mesa phenomenon) | DONE | BFS routing over exits; achieve's depth/visited bounds = pruned search; the planner avoids blind search by heuristic difference ordering -- the paper's whole arc |
| II. Pattern-Recognition (prototypes, property lists, invariant properties, combining evidence) | DONE | matching = prototype matching against `names`; markers/kind = property lists; AKO inheritance gives size/position-invariant recognition (a key in any room is A key); ambiguity question combines evidence |
| III. Learning (reinforcement, secondary reinforcement, credit assignment) | PARTIAL->REPRESENTED | belief updates reinforce/suppress per-object location hypotheses from outcomes (perceive = reward accurate expectations; surprise = punish); credit assignment handled by goal-tree structure exactly as Newell's quote in the paper prescribes: "if a goal is achieved, its subgoals are reinforced" -- achieved subgoals are kept, failed plans discarded wholesale. No numeric reinforcement -- noted, not needed |
| IV. Planning (LT, subproblem selection, Character-Method tables, planning spaces, islands) | DONE + flagship | `plan-needs` = Character-Method table (difference -> operator); `ach-seq` = means-ends subgoaling; cross-room fetch plans = inserting lemmas/islands (bone before troll); projected state S = planning in the simplified space, verified on execution |
| V. Induction and models (models of oneself, GPS differences) | DONE (partial models) | fallible NPC minds are exactly the paper's "internal model": beliefs about the world used to predict and act; rat's model OF the magpie is Minsky's own later "model of another mind" argument made playable |

GPS means-end differences = the difference frames; Samuel's evaluation-by-
projected-continuation = the projected-state planner; Pandemonium demons =
the if-added demons. The lineage the second paper asks for is the spine the
first delivers.

## Gaps found in this audit and what was done

1. **No representation of Minsky's "learning = storing new frames"** --
   partially existed via `teaches`/lenses (perspective acquisition).
   Judged sufficient: it is literal frame acquisition from social
   interaction, and it is on the winning path.
2. **Scenario completion had no lasting world change beyond narration** --
   verified: finale opens the vault door (world transformation). No gap.
3. **Save/restore was broken on the WASM host** (crash, then 205s restore):
   fixed this session -- memory-growth guard in the Feather shim,
   UTF-8 byte-cache, and db normalization after `load-db`
   (`dict create {*}$db`) so restore is one parse instead of thousands.
   Restore now < 1s of game time inside the turn.
4. **Full isa? caching** added to `cache.tcl` (was limited to thing/room;
   now caches every ancestor query keyed on gen).
5. **README claimed concepts the code did not have**: none found. Every row
   of the README mapping table was verified against engine.tcl/world.tcl.

## Deliberate simplifications (documented, defensible)

- No graded syntactic frames (paper 2.1) -- the game speaks in commands.
- No metric/partial visual occlusion (1.9) -- darkness and closed
  containers carry the occlusion idea; geometry would be dead weight.
- Beliefs track object locations only (not door states/lit-ness) -- stated
  in README as future work.
- Single-value terminals, single inheritance -- stated in README.
