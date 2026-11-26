class_name VisitContext
extends RefCounted

## Everything an object handler may need about the visiting side.

var player_side: int = 0
var hero_model: HeroModel = null
var player_state: PlayerState = null
var map: MapData = null
var hero_id: int = 0   # HeroModel.visit_id() of the visiting hero: the key
                        # once-per-hero boosters store in visited_by.
var occupied_tiles: Array = []  # tiles currently held by any live hero, Vector2i
                        # (stone_liths excludes occupied destinations).
                        # Set at BOTH construction sites: InteractionResolver.visit()
                        # (human — root.occupied_hero_tiles(): ALL live human hero
                        # nodes, active AND inactive, + the AI hero) and AITurnRunner.
                        # AIArrival pickups (AI's own tile only). Defaults to []
                        # because AITurnRunner's dispatch never routes to the
                        # "teleport" handler today (its match only special-cases a
                        # few kinds + a generic "handler_id == pickup" fallback —
                        # stone_liths' handler is "teleport", so AI visits are a
                        # no-op there); an empty default is therefore a safe no-op
                        # for that path, not a silently-wrong one.

## Pre-v7 saves keyed visits by roster slot, so a recruit who took a dead
## hero's slot inherited its visits. Kept only for SaveGame's migration.
static func legacy_hero_id(side: int, hero_idx: int) -> int:
	return side * 100 + hero_idx

static func of(side: int, hero: HeroModel = null) -> VisitContext:
	var c := VisitContext.new()
	c.player_side = side
	c.hero_model = hero
	c.hero_id = hero.visit_id() if hero != null else 0
	return c
