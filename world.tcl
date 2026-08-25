# ============================================================================
# world.tcl -- the demonstration world
#
# First come the STEREOTYPES: generic frames whose defaults and attached
# procedures describe what one normally expects of a thing, a room, a
# container, a key, a person. Then come the INDIVIDUALS, each AKO some
# stereotype, overriding only the terminals where reality differs from
# expectation. This is Minsky's central economy: store knowledge once, at
# the most general frame that holds, and let everything below inherit it.
#
# The map:
#
#                  [Observatory]   (the troll guards this stair)
#                       |
#                   [Landing]
#                       |
#     [Study] --- [Hallway] --- [Library] --- [Vault]
#                       |                  (the ritual opens this door)
#                   [Cellar]    (dark)
#
# The chain of dependencies: the lamp lights the cellar; the key opens the
# chest (the tome); the bone appeases the troll; past the troll lies the
# candle; the curator knows the word; bell + candle + word open the vault;
# the amulet leaves its pedestal with a warning gong; the curator rewards
# whoever brings it to him. Five points in all.
# ============================================================================

# ---------------------------------------------------------- stereotypes ---

frames::defframe thing {
    short         {default "thing"}
    names         {default {}}
    location      {default limbo}
    portable      {default 1}
    scenery       {default 0}
    lit           {default 0}
    light-source  {default 0}
    container     {default 0}
    open          {default 0}
    locked        {default 0}
    lockable      {default 0}
    ringable      {default 0}
    turnable      {default 0}
    viewer        {default 0}
    look-through  {default ""}
    lens-notes    {default {}}
    animate       {default 0}
    hostile       {default 0}
    blocks        {default {}}
    haunts        {default {}}
    wants         {default ""}
    topics        {default {}}
    teaches       {default {}}
    reading       {default ""}
    prize         {default 0}
    scored        {default 0}
    each-turn     {default ""}
    goal          {default ""}
    choose-goal   {default ""}
    lair          {default ""}
    gait          {default "pads"}
    shiny         {default 0}
    worth         {default 1}  ;# how dear a thing is -- a finer discrimination than mere glitter
    believes      {default 0}  ;# 1 = a fallible mind that plans over what it has seen
    beliefs       {default {}} ;# this mind's private map: object -> where it thinks it is
    seen          {default {}} ;# memory of sightings: object -> rooms seen in, newest first
    rival         {default ""} ;# another mind this one models (reads its beliefs)
    nests         {default {}} ;# preferred hiding rooms, in order
    stash-target  {default ""} ;# the hiding place currently committed to
    post          {default ""} ;# where this mind returns to lurk when idle
    bait          {default ""} ;# a trifle kept about it, to be spent on a ruse
    bait-want     {default ""} ;# a trifle it has set out to pocket
    spent         {default {}} ;# props already used -- never coveted again
    scenario-role {default ""}
    description   {default "You see nothing special about it."}
}

frames::defframe room {
    ako      {value thing}
    portable {default 0}
    lit      {default 1}
    exits    {default {}}
}

frames::defframe container {
    ako         {value thing}
    container   {default 1}
    portable    {default 0}
    open        {default 0  if-added ::game::on-open-change}
    description {if-needed ::game::describe-container}
}

frames::defframe key {
    ako {value thing}
}

frames::defframe person {
    ako           {value thing}
    portable      {default 0}
    animate       {default 1}
    greet         {default "There is no reply."}
    default-reply {default "There is no reply."}
    satisfied     {default 0  if-added ::game::on-npc-satisfied}
    satisfied-msg {default ""}
    accept-msg    {default ""}
}

# --------------------------------------------------------------- player ---

frames::defframe player {
    ako       {value thing}
    short     {value "yourself"}
    portable  {value 0}
    animate   {value 1}
    location  {value study  if-added ::game::on-move}
    focus     {default ""}
    viewpoint {default plain}
    lenses    {default plain}
    score     {value 0      if-added ::game::on-score}
    max-score {value 12}
}

# A perspective is a frame imposed on a scene: a way of regarding it. The
# scene's features are shared between perspectives; only the reading differs.
frames::defframe perspective {
    of      {default ""}
    of-name {default "the place"}
    label   {default "another way of looking"}
    blurb   {default ""}
}

# ---------------------------------------------------------------- rooms ---

frames::defframe study {
    ako         {value room}
    short       {value "The Study"}
    description {value "Bookshelves sag under decades of dust. A draft slips beneath the door to the north, and a faint smell of old paper hangs in the air."}
    exits       {value {north hallway}}
}

frames::defframe hallway {
    ako         {value room}
    short       {value "The Hallway"}
    description {value "A long hallway papered in faded green. The study lies south and an archway opens east into a library. A narrow stone stairway descends into darkness; a grander one climbs to a landing above."}
    exits       {value {south study  down cellar  east library  up landing}}
}

frames::defframe cellar {
    ako          {value room}
    short        {value "The Cellar"}
    lit          {value 0}
    description  {value "A low stone cellar, cool and quiet. The stairway climbs back up toward the light. A row of iron hooks lines one wall, and a dark stain spreads across the flagstones."}
    exits        {value {up hallway}}
    perspectives {value {
        butcher  cellar-as-larder
        larder   cellar-as-larder
        meat     cellar-as-larder
        merchant cellar-as-cellar
        wine     cellar-as-cellar
        cellar   cellar-as-cellar
        vintner  cellar-as-cellar
    }}
}

# The same cellar, framed two ways. The blurb re-describes the WHOLE scene;
# the shared features below are reinterpreted to match.
frames::defframe cellar-as-larder {
    ako     {value perspective}
    of      {value cellar}
    of-name {value "the cellar"}
    label   {value "a butcher's eye"}
    blurb   {value "Seen as a cold-store, it all snaps into purpose: a killing-room, cool the year round. The iron hooks along the wall are working steel for swinging carcasses, and the dark patch underfoot is the drain-stain of long use. A good larder, this -- if a grim one."}
}

frames::defframe cellar-as-cellar {
    ako     {value perspective}
    of      {value cellar}
    of-name {value "the cellar"}
    label   {value "a wine-merchant's eye"}
    blurb   {value "Seen as a wine cellar, the room turns gracious: cool, still air, exactly as the vintages would have wanted. The iron along the wall resolves into an empty wine rack, and the stain on the flagstones is the ghost of a bottle dropped and shattered a generation ago."}
}

frames::defframe library {
    ako         {value room}
    short       {value "The Library"}
    description {value "Galleries of books rise into shadow. The east wall is bare stone, carved with an inscription, and oddly seamless -- as if it expects to be a door."}
    exits       {value {west hallway}}
}

frames::defframe landing {
    ako         {value room}
    short       {value "The Landing"}
    description {value "A broad landing at the top of the stairs. A narrow flight continues north, up toward a domed roof."}
    exits       {value {down hallway  north observatory}}
}

frames::defframe observatory {
    ako         {value room}
    short       {value "The Observatory"}
    description {value "A round room under a cracked dome of glass. Star charts curl on the walls."}
    exits       {value {south landing}}
}

frames::defframe vault {
    ako         {value room}
    short       {value "The Vault"}
    description {value "A small chamber of fitted black stone, silent as held breath. The secret door stands open to the west."}
    exits       {value {west library}}
}

# ------------------------------------------------------------- the cast ---

frames::defframe curator {
    ako           {value person}
    short         {value "stooped curator"}
    names         {value {curator man librarian keeper}}
    location      {value library}
    description   {value "A stooped old man in a moth-eaten cardigan, dusting books that immediately re-dust themselves. He looks like he knows things."}
    greet         {value "The curator peers at you over his spectacles. \"Ask me about something, dear visitor. The archive is at your disposal.\""}
    default-reply {value "The curator strokes his chin. \"On that subject, I'm afraid, the archive is silent.\""}
    wants         {value silver-amulet}
    accept-msg    {value "The curator takes the amulet with trembling hands. \"The Amulet of K-lines! After all these years!\" He fastens it about his neck and seems to stand a little straighter."}
    satisfied-msg {value "\"You have my eternal gratitude,\" he says. \"The collection is complete.\""}
    teaches       {value {cellar cellar-as-cellar  wine cellar-as-cellar  vintage cellar-as-cellar}}
    topics        {value {
        frames  "\"A frame,\" he says, warming instantly, \"is a remembered stereotype of a situation. One arrives somewhere new, selects a frame, and bends it until it fits.\""
        frame   "\"A frame,\" he says, warming instantly, \"is a remembered stereotype of a situation. One arrives somewhere new, selects a frame, and bends it until it fits.\""
        minsky  "\"Ah, the author of the framework itself. This whole house is rather in his debt.\""
        ritual  "He lowers his voice. \"Bell, candle, word -- in that order, before the inscription. And the word, since you will ask, is 'frame'.\""
        word    "\"The word is 'frame',\" he whispers. \"What else could it be?\""
        inscription "\"Instructions, plainly given: ring, kindle, speak. The wall has been waiting a long time for someone to follow them.\""
        amulet  "His eyes gleam. \"The silver Amulet of K-lines, sealed in the vault beyond the east wall. Bring it to me, and you shall have done a great thing.\""
        vault   "\"Beyond the east wall. The ritual on the inscription is the only key.\""
        troll   "\"Harmless enough, that one, though immovable. Trolls are single-minded creatures -- fond, above all, of bones.\""
        bone    "\"Trolls are fond, above all, of bones. I believe something of the sort was left in the cellar.\""
        chest   "\"The old oak chest? The iron key in the study has always opened it.\""
        key     "\"The iron key in the study. It fits the chest in the cellar.\""
        tome    "\"A slim volume of 1974, and the most important book in the house. Do read it.\""
        book    "\"A slim volume of 1974, and the most important book in the house. Do read it.\""
        candle  "\"There should be a wax taper up in the observatory, if the troll will let you by.\""
        bell    "\"The brass bell is here in the library somewhere. Mind you ring it before the candle.\""
        cat     "\"She wanders as she pleases. The house is more hers than mine.\""
        cellar  "\"The cellar? In my grandfather's day it was the finest wine cellar in the county. Cool, still, perfect for the bottles. Stand in it and picture the racks, and you'll see it as he did.\""
        wine    "\"The cellar held the finest vintages in the county, once. Picture it as a wine cellar and the whole room makes a different kind of sense.\""
        stars   "\"Ah, the observatory. If the troll lets you by, look through the old telescope -- but you must sweep it clear across the sky. No single field shows more than two corners of the figure up there.\""
        telescope "\"A fine old instrument. Turn it slowly, field by field, all the way round. The figure it hides is called the Frame, and you'll only ever see it whole.\""
        figure  "\"The Frame, the charts call it -- a quadrilateral of four bright stars, each one shared between two fields of view. Sweep the whole sky and you'll join them.\""
        himself "\"Merely the keeper of the frames, dear visitor.\""
        curator "\"Merely the keeper of the frames, dear visitor.\""
    }}
}

frames::defframe troll {
    ako           {value person}
    short         {value "surly troll"}
    names         {value {troll guard brute}}
    location      {value landing}
    hostile       {value 1}
    blocks        {value {landing north}}
    block-msg     {value "The troll plants itself in the stairway, arms folded. \"None shall pass,\" it rumbles, then adds, hopefully: \"...unless bone?\""}
    description   {if-needed ::game::describe-troll}
    greet         {value "The troll grunts. \"None shall pass. Unless... bone?\""}
    default-reply {value "The troll furrows its considerable brow. \"Bone?\" it offers."}
    wants         {value old-bone}
    accept-msg    {value "The troll snatches the bone and cradles it like a long-lost relative."}
    satisfied-msg {value "Gnawing contentedly, it shuffles aside. The stairway north is clear."}
    teaches       {value {cellar cellar-as-larder  larder cellar-as-larder  meat cellar-as-larder}}
    topics        {value {
        bone "\"BONE!\" The troll's eyes light up like festival lanterns."
        pass "\"None shall pass,\" the troll recites, clearly proud of having memorized it."
        cellar "The troll's nose twitches. \"Cold room down there. Good for MEAT. Hooks for hanging, floor for catching.\" Its appetite is contagious; for a moment you find yourself seeing the cellar as a larder too."
        larder "\"Larder!\" the troll agrees, with feeling. \"Hooks. Floor. Cold. Good.\" You catch the butcher's-eye view from it."
        meat "\"MEAT,\" the troll confirms, drooling slightly, and the cold-store snaps into focus in your mind's eye."
    }}
}

frames::defframe black-cat {
    ako           {value person}
    short         {value "black cat"}
    names         {value {cat kitty feline}}
    location      {value hallway}
    haunts        {value {study hallway library landing}}
    each-turn     {value ::game::pursue-goal}
    goal          {value {bring toy-mouse player}}
    description   {value "A small black cat with judgmental yellow eyes. It appears to be supervising."}
    greet         {value "The black cat regards you for a moment, then looks away, unimpressed."}
    default-reply {value "\"Meow,\" the cat explains."}
    topics        {value {
        mouse  "\"Mine,\" the cat says, in the tone of a philosopher stating a self-evident truth."
        toy    "\"Also mine. Everything small is mine. This is my whole philosophy.\""
        cat    "\"Yes?\" The look you receive could end an argument."
        meow   "\"Meow,\" the cat agrees, as if you had finally understood something."
        frames "\"The cat stares at you for a long moment, then at the door, then back. You understand: she is holding a frame of 'door means mouse escapes' and checking it against reality. Cats are natural frame theorists."
        house  "\"The house,\" her expression implies, \"is simply where I keep my things. You are tolerated.\""
    }}
}

frames::defframe magpie {
    ako           {value person}
    short         {value "thieving magpie"}
    names         {value {magpie bird thief}}
    location      {value hallway}
    lair          {value library}
    gait          {value "flutters"}
    haunts        {value {study hallway library landing cellar}}
    believes      {value 1}
    each-turn     {value ::game::pursue-goal}
    choose-goal   {value ::game::thief-policy}
    description   {value "A big, glossy magpie with a larcenous gleam in its eye. It is forever sizing up anything that glints."}
    greet         {value "The magpie cocks its head and looks pointedly at your hands."}
    default-reply {value "The magpie chatters, watching your pockets."}
    topics        {value {
        shiny  "\"Shiny is good,\" the magpie says with total conviction. Its treasure-frame has exactly one terminal, and this fills it."
        silver "\"Silver! Shiny! Good!\" The distinctions you might draw simply have nowhere to land on that frame."
        coin   "\"Round and shiny. The best kind of thing.\""
        nest   "\"There is a place where all the shiny goes.\" It glances east before it can stop itself."
        thief  "The magpie looks deeply unapologetic."
    }}
}

frames::defframe pack-rat {
    ako           {value person}
    short         {value "pack rat"}
    names         {value {rat rodent vermin}}
    location      {value library}
    lair          {value cellar}
    nests         {value {study landing}}
    rival         {value magpie}
    post          {value library}
    gait          {value "scurries"}
    haunts        {value {library hallway cellar study landing}}
    believes      {value 1}
    bait          {value scrap-of-tinsel}
    each-turn     {value ::game::pursue-goal}
    choose-goal   {value ::game::rat-policy}
    description   {value "A scruffy, bright-eyed pack rat with a cunning, calculating way of watching the other thieves in the house. It keeps a scrap of tinsel tucked in its cheek, the way a cardsharp keeps an ace."}
    greet         {value "The pack rat freezes, watching you with glittering eyes."}
    default-reply {value "The pack rat twitches its whiskers and ignores you."}
    topics        {value {
        magpie "\"A fool,\" the rat says of its rival. \"Sees a gleam, must have it. A mind like that can be led anywhere -- you just put the gleam where you want it to look.\""
        shiny  "\"Shiny is not one thing to everyone. To HER it is one thing. That is her whole weakness, spelled out in four letters.\""
        plan   "\"Everything I do is two moves ahead of what she thinks I am doing. Sometimes three. The trick is modelling your model of me.\""
        tinsel "\"Worthless,\" it says, with the expression of someone holding a winning card."
        cellar "\"Dark. Quiet. No eyes down there at all.\""
    }}
}

frames::defframe toy-mouse {
    ako         {value thing}
    short       {value "toy mouse"}
    names       {value {mouse toy}}
    location    {value library}
    description {value "A small felt mouse, somewhat the worse for love, with one ear chewed off."}
}

proc ::game::describe-troll {frame slot} {
    if {[frames::fget $frame hostile] eq "1"} {
        return "A boulder of a creature wedged into the north stairway, radiating stubbornness. It sniffs the air now and then, as if hoping for something."
    }
    return "The troll sits against the wall, gnawing its bone with an expression of profound contentment."
}

# --------------------------------------------------------------- things ---

frames::defframe brass-lamp {
    ako          {value thing}
    short        {value "brass lamp"}
    names        {value {lamp lantern brass}}
    location     {value study}
    light-source {value 1}
    lit          {default 0  if-added ::game::on-lamp}
    description  {value "A small brass oil lamp, dented but serviceable."}
}

frames::defframe iron-key {
    ako         {value key}
    short       {value "iron key"}
    names       {value {key iron}}
    location    {value study}
    description {value "A heavy iron key, cold to the touch. It looks like it would fit something large."}
}

frames::defframe silver-coin {
    ako         {value thing}
    short       {value "silver coin"}
    names       {value {coin penny}}
    location    {value study}
    shiny       {value 1}
    worth       {value 2}
    description {value "A bright silver coin, worn smooth. It catches what little light there is -- and, it turns out, the eye of every magpie in the house."}
}

frames::defframe scrap-of-tinsel {
    ako         {value thing}
    short       {value "scrap of tinsel"}
    names       {value {tinsel scrap foil}}
    location    {value pack-rat}
    shiny       {value 1}
    description {value "A crinkled scrap of silver foil, worth nothing at all. It flashes in the light exactly like something precious -- which, to a certain kind of eye, is the same as being precious."}
}

frames::defframe velvet-pouch {
    ako         {value container}
    short       {value "velvet pouch"}
    names       {value {pouch bag purse}}
    location    {value study}
    open        {value 1}
    portable    {value 1}
    description {value "A small drawstring pouch of worn blue velvet. Drawn shut, whatever is inside is quite out of sight."}
}

frames::defframe glass-bead {
    ako         {value thing}
    short       {value "glass bead"}
    names       {value {bead glass bauble}}
    location    {value study}
    shiny       {value 1}
    description {value "A faceted glass bead on a snapped thread. Cheap as dirt -- but it flashes in the light exactly like something precious, which is the whole of what a magpie troubles to know."}
}

frames::defframe oak-chest {
    ako          {value container}
    short        {value "oak chest"}
    names        {value {chest oak trunk}}
    location     {value cellar}
    locked       {value 1}
    lockable     {value 1}
    unlocks-with {value iron-key}
    material      {default wood}
    contents-kind {default keepsakes}
}

frames::defframe dusty-tome {
    ako         {value thing}
    short       {value "dusty tome"}
    names       {value {tome book volume framework}}
    location    {value oak-chest}
    prize       {value 1}
    description {value "A slim, dust-covered volume. The spine reads: \"A Framework for Representing Knowledge\"."}
    reading     {value "The tome argues that a mind meets each new moment by selecting a remembered stereotype -- a frame -- and bending it to fit: its empty terminals fill with the particulars at hand, its defaults stand in for whatever goes unobserved, and when expectations fail, the mind slides along links of similarity to a better frame. As you read, the cellar around you seems to resolve into slots, markers, and defaults."}
}

frames::defframe old-bone {
    ako         {value thing}
    short       {value "old bone"}
    names       {value {bone femur}}
    location    {value cellar}
    description {value "A large, well-aged soup bone. Somewhere, something would treasure this."}
    size        {default large}
    chewy       {default 1}
}

# One physical feature, two framings: examining it returns a reading keyed
# to the perspective the player currently holds. The frame is shared; the
# meaning is supplied by the observer.
frames::defframe iron-hooks {
    ako         {value thing}
    short       {value "row of iron hooks"}
    names       {value {hooks hook rack iron}}
    location    {value cellar}
    portable    {value 0}
    scenery     {value 1}
    description {if-needed ::game::describe-by-viewpoint}
    lens-notes  {value {
        plain            "A row of heavy iron hooks bolted along the wall, all of them empty."
        cellar-as-larder "Meat hooks: the cold-store's working steel, scoured bright, each one shaped to take the weight of a swung carcass."
        cellar-as-cellar "A wine rack of wrought iron, cradle after cradle of it, every one empty -- the vintages it was built for are decades gone."
    }}
}

frames::defframe dark-stain {
    ako         {value thing}
    short       {value "dark stain"}
    names       {value {stain patch blood flagstones floor mark}}
    location    {value cellar}
    portable    {value 0}
    scenery     {value 1}
    description {if-needed ::game::describe-by-viewpoint}
    lens-notes  {value {
        plain            "A dark stain spread across the flagstones, its origin long since unknowable."
        cellar-as-larder "A bloodstain, scrubbed at for years and never quite lifted, fanning out from where the drain must once have been."
        cellar-as-cellar "A wine stain, purple-black and broad, where some priceless bottle slipped and broke a lifetime ago."
    }}
}

frames::defframe brass-bell {
    ako           {value thing}
    short         {value "brass bell"}
    names         {value {bell brass handbell}}
    location      {value library}
    ringable      {value 1}
    scenario-role {value {ritual bell}}
    description   {value "A small brass handbell with a worn wooden handle, polished by long use."}
}

frames::defframe wax-candle {
    ako           {value thing}
    short         {value "wax candle"}
    names         {value {candle wax taper}}
    location      {value observatory}
    light-source  {value 1}
    lit           {default 0  if-added ::game::on-lamp}
    scenario-role {value {ritual candle}}
    description   {value "A stout wax taper, half-burned, smelling faintly of beeswax and old ceremonies."}
}

frames::defframe inscription {
    ako         {value thing}
    short       {value "carved inscription"}
    names       {value {inscription carving letters wall writing}}
    location    {value library}
    portable    {value 0}
    description {value "Letters chiselled deep into the east wall, in a confident antique hand."}
    reading     {value "The inscription reads: \"RING THE BELL. KINDLE THE CANDLE. SPEAK THE WORD. IN THIS ORDER IS THE WAY MADE PLAIN.\""}
}

frames::defframe telescope {
    ako          {value thing}
    short        {value "bronze telescope"}
    names        {value {telescope bronze scope eyepiece}}
    location     {value observatory}
    portable     {value 0}
    turnable     {value 1}
    viewer       {value 1}
    look-through {value ::game::peer-telescope}
    aim          {value vp-north}
    ring         {value {vp-north vp-east vp-south vp-west}}
    seen         {value {}}
    figure-found {value 0}
    description  {value "A great bronze telescope on a clawed tripod, aimed through the cracked dome. Peer through it (\"look through telescope\"), and turn it (\"turn telescope right\") to sweep across the sky, field by field."}
}

# The night sky as a frame-system: four overlapping fields arranged in a
# ring. Each field's first and last stars are bright "corners"; the middle
# is faint. Crucially the corner strings are SHARED with the neighbouring
# fields (north's right corner Altair is east's left corner, and so on), so
# the four corners are each shared terminals -- and they are exactly the
# four corners of the constellation called the Frame.
frames::defframe skyview { label {default "a field of stars"} stars {default {}} }

frames::defframe vp-north {
    ako   {value skyview}
    label {value "the northern field"}
    stars {value {Vega {a faint nameless star} Altair}}
}
frames::defframe vp-east {
    ako   {value skyview}
    label {value "the eastern field"}
    stars {value {Altair {a dim reddish star} Deneb}}
}
frames::defframe vp-south {
    ako   {value skyview}
    label {value "the southern field"}
    stars {value {Deneb {a flickering pale star} Rigel}}
}
frames::defframe vp-west {
    ako   {value skyview}
    label {value "the western field"}
    stars {value {Rigel {a smudge of starlight} Vega}}
}

frames::defframe star-charts {
    ako         {value thing}
    short       {value "curling star charts"}
    names       {value {charts chart map maps star stars}}
    location    {value observatory}
    portable    {value 0}
    scenery     {value 1}
    description {value "Faded charts of the night sky. One is ringed in ink: a quadrilateral of four bright stars labelled THE FRAME, with a marginal note -- \"seen whole only by him who sweeps the whole sky; no single field holds more than two of her corners.\""}
}

frames::defframe pedestal {
    ako         {value container}
    short       {value "black pedestal"}
    names       {value {pedestal plinth stand}}
    location    {value vault}
    open        {value 1}
    description {if-needed ::game::describe-pedestal}
}

proc ::game::describe-pedestal {frame slot} {
    set txt "A waist-high pedestal of polished black stone, its top worn into a shallow cradle."
    set inside {}
    foreach f [contents $frame] { lappend inside [an $f] }
    if {[llength $inside]} {
        append txt " Resting upon it: [join $inside {, }]."
    } else {
        append txt " It stands empty, and somehow disapproving."
    }
    return $txt
}

frames::defframe silver-amulet {
    ako         {value thing}
    short       {value "silver amulet"}
    names       {value {amulet silver medallion}}
    location    {value pedestal  if-removed ::game::on-amulet-taken}
    description {value "A silver amulet on a fine chain, engraved with a web of lines converging on a single node. It is heavier than it looks."}
}

proc ::game::on-amulet-taken {frame slot old} {
    if {$old ne "pedestal" || [frames::fget $frame scored] eq "1"} { return }
    frames::fput $frame scored 1
    say "As the amulet leaves its cradle, a deep gong reverberates through the stone -- once, twice -- and then a silence that feels like attention."
    add-score
}

# ---------------------------------------------------------- the ritual ---
#
# A scenario frame: Minsky's script. The expected sequence is bell,
# candle, word -- performed in the library. Each confirmed expectation is
# narrated; an out-of-order event collapses the attempt; completing the
# sequence opens the secret door.

frames::defframe ritual {
    ako        {value scenario}
    steps      {value {bell candle word}}
    place      {value library}
    word       {value frame}
    progress   {value 0  if-added ::game::on-scenario-progress}
    murmurs    {value {
        "The bell's note hangs in the air far longer than it should. The carved letters seem to deepen."
        "The candle flame stands perfectly still, like a held breath. The east wall is listening."
    }}
    finale     {value "At the word, the seamless wall splits along invisible joints and swings inward with a grinding sigh. A doorway stands open to the east."}
    order-hint {value "The inscription is firm about the order: first the bell, then the candle, then the word."}
    on-complete {value ::game::ritual-complete}
}

proc ::game::ritual-complete {scn} {
    set ex [frames::fget library exits]
    frames::fput library exits [dict merge $ex {east vault}]
    add-score
}
