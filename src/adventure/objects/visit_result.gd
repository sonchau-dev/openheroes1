class_name VisitResult
extends RefCounted

## What an object's on_visit() tells the adventure map to do next.

var consumed: bool = false        # remove the object after this visit
var start_battle: ArmyData = null # non-null → launch a battle vs this army
var enter_town: bool = false      # open the town screen
var granted: Dictionary = {}      # resources to add, e.g. {"gold": 800, "wood": 4}
var join_unit: String = ""        # dwelling troops to add to the hero army
var join_count: int = 0
var recruit_dwelling: Dwelling = null # paid dwelling -> encounter/recruit modal
var free_dwelling: Dwelling = null    # free dwelling -> confirmation join modal
var join_offer_stack: NeutralStack = null # neutral stack -> followers confirmation join modal
var grant_artifact: String = ""   # artifact id -> hero_model.artifacts.append()
var grant_exp: int = 0            # -> hero_model.experience += grant_exp
var choice: Dictionary = {}       # {"prompt": String, "options": [{"label",
                                   # "granted"?, "exp"?, "pay"? (gold DEDUCTED via
                                   # apply_choice), "destroy_hero"? (sets destroy_hero
                                   # below so the resolver fires the hero-death fn)}]}
var destroy_hero: bool = false    # Demon Cave ransom refusal:
                                   # apply_choice sets this true when the chosen option
                                   # carries destroy_hero; InteractionResolver._show_choice's
                                   # callback then calls _player_hero_death_fn. UI-free —
                                   # headless tests assert this flag directly.
var continue_visit: bool = false  # choice accepted an encounter-entry prompt;
                                  # resolver immediately visits source_object again
var message: String = ""          # status-bar text (optional)
var show_dialog: bool = false     # resolver pops MapDialogs.info with `message`
var teleport_to: Vector2i = Vector2i(-1, -1)  # != (-1,-1) -> resolver calls its
                                               # teleport_fn(teleport_to)
                                               # (stone_liths random pool)
var reveal_map: bool = false      # Obelisk: true ->
                                   # resolver calls its reveal_fn (human explore_all()
                                   # + FogLayer.explore_everything()), mirroring the
                                   # teleport_fn wiring above. Fires only for the
                                   # single-obelisk-on-the-map special case.
var open_oracle: bool = false     # Oracle/Shrine: resolver opens the blind-seer
                                   # introduction, then calls _open_oracle_fn for
                                   # the complete player-ranking screen. The
                                   # object is repeatable and never consumed.
var already_visited: bool = false # true when this visit hit the was_visited_by
                                   # early-return (stat_boost.gd) -- no stat was
                                   # granted this time, so the themed dialog
                                   # should suppress its "just granted" icon.
var source_object: MapObject = null # choice/persistence source (paid artifacts)
