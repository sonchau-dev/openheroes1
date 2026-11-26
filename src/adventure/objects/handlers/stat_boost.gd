extends RefCounted
## Once-per-hero / per-battle stat boosters: Gazebo (+1000
## exp), Fountain / Faerie Ring (+1 luck), Oasis (+1 morale), Statue (+2 morale)
## — values cited from data/knowledge_base/adventure-object-catalog.md.
##
## Duration semantics: the note says Gazebo is a TRUE one-time-per-hero grant
## (permanent), while the Fountain/Faerie Ring/Oasis/Statue family is really
## "+N until the hero's next battle, then resets" — NOT a permanent one-time.
## Per-battle morale/luck values live in HeroModel's temporary fields. Battle
## completion clears those fields and reopens each visited object's gate.
##
## The handler READS `params.once`. `once == "per_hero"`
## (Gazebo) and `once == "per_battle"` (Fountain/Faerie Ring/Oasis/Statue)
## both use visited_by to prevent stacking before combat; only per_battle visits
## are recorded on the hero for reopening afterward. An unknown/missing `once`
## value defaults to per_hero gating and emits a push_warning.

## Authentic flavor text (human-supplied reference screenshot of this
## project's own Statue visit dialog — same corroboration precedent as
## weekly_pickup.gd's windmill/watermill strings). Keyed by obj.type; types
## with no entry yet fall back to the generic "+N stat" line.
const MSG_STATUE := "A large statue of an angel towers above you. Abruptly, the angel's eyes open and your troops celebrate a great increase in their morale."

## Native Fountain copy, confirmed by the supplied HOMM1 screenshot.
const MSG_FOUNTAIN := "As you drink the sweet water, you gain luck for your next battle."
const MSG_FOUNTAIN_REVISITED := "You drink from the enchanted fountain, but nothing happens."

## Native Faerie Ring copy, confirmed by the supplied HOMM1 video. Both the
## grant and no-op forms use the same titled, text-only event window.
const MSG_FAERIE_RING := "Upon entering the mystical faerie ring, your army gains luck for its next battle."
const MSG_FAERIE_RING_REVISITED := "You enter the faerie ring, but nothing happens."

## Native Gazebo copy, confirmed by the supplied HOMM1 screenshot and executable.
const MSG_GAZEBO := "An old knight appears on the steps of the gazebo. \"My liege, I will teach you all that I know to aid you in your travels.\""
const MSG_GAZEBO_REVISITED := "An old knight appears on the steps of the gazebo. \"I am sorry, my liege, I have taught you all I can.\""

## Authentic revisit flavor text (human-supplied reference screenshot): same
## "Statue" dialog title/art, but the no-op body once already visited.
const MSG_STATUE_REVISITED := "A large statue of an angel towers above you. Your army encircles the statue, but there appears to be nothing special about it."

## Native Oasis copy from heroes.exe.
const MSG_OASIS := "A nomad merchant, traveling on foot, hails you and says his horse had spooked and left him stranded. For safe passage he takes your army to an oasis, raising your morale for one battle."
const MSG_OASIS_REVISITED := "You spot an oasis, but the well is dry and you depart empty-handed."

## Native Buoy copy from heroes.exe.
const MSG_BUOY := "Your men spot a navigational buoy, confirming that you are on course and increasing their morale."
const MSG_BUOY_REVISITED := "Your men spot a navigational buoy, confirming that you are on course."

func visit(obj: MapObject, ctx: VisitContext) -> VisitResult:
	var r := VisitResult.new()
	if obj.was_visited_by(ctx.hero_id):
		match obj.type:
			"statue": r.message = MSG_STATUE_REVISITED
			"fountain": r.message = MSG_FOUNTAIN_REVISITED
			"faerie_ring": r.message = MSG_FAERIE_RING_REVISITED
			"gazebo": r.message = MSG_GAZEBO_REVISITED
			"oasis": r.message = MSG_OASIS_REVISITED
			"buoy": r.message = MSG_BUOY_REVISITED
			_: r.message = "You have already visited this site."
		r.show_dialog = true
		r.already_visited = true
		return r
	var stat := String(obj.params.get("stat", ""))
	var amount := int(obj.params.get("amount", 0))
	var once := String(obj.params.get("once", ""))
	match once:
		"per_hero":
			pass  # Gazebo family: true permanent one-time-per-hero grant.
		"per_battle":
			pass  # Fountain/Faerie Ring/Oasis/Statue: until next battle.
		_:
			push_warning("stat_boost: object id=%d type=%s has unknown/missing 'once' param (%s); defaulting to per_hero (permanent) gating" % [obj.id, obj.type, once])
	if ctx.hero_model != null:
		match stat:
			"exp":
				ctx.hero_model.grant_experience(amount, Game.rng)
			"luck":
				if once == "per_battle":
					var tag := ""
					match obj.type:
						"faerie_ring": tag = "Faerie ring visited +%d" % amount
						"fountain": tag = "Fountain visited +%d" % amount
						_: tag = "%s visited +%d" % [obj.type.capitalize(), amount]
					ctx.hero_model.add_temporary_luck_modifier(tag, amount)
				else:
					ctx.hero_model.luck += amount
			"morale":
				if once == "per_battle":
					var tag := ""
					match obj.type:
						"oasis": tag = "Oasis visited +%d" % amount
						"statue": tag = "Statue visited +%d" % amount
						"buoy": tag = "Buoy visited +%d" % amount
						_: tag = "%s visited +%d" % [obj.type.capitalize(), amount]
					ctx.hero_model.add_temporary_morale_modifier(tag, amount)
				else:
					ctx.hero_model.morale += amount
		if once == "per_battle":
			ctx.hero_model.record_battle_booster_visit(obj.id, ctx.hero_id)
	obj.mark_visited(ctx.hero_id)
	match obj.type:
		"statue": r.message = MSG_STATUE
		"fountain": r.message = MSG_FOUNTAIN
		"faerie_ring": r.message = MSG_FAERIE_RING
		"gazebo": r.message = MSG_GAZEBO
		"oasis": r.message = MSG_OASIS
		"buoy": r.message = MSG_BUOY
		_: r.message = _grant_message(stat, amount)
	r.show_dialog = true
	# NOT consumed: boosters stay on the map (visited_by, not obj.consumed, is
	# what gates re-collection per hero).
	return r

static func _grant_message(stat: String, amount: int) -> String:
	match stat:
		"exp":
			return "+%d experience" % amount
		"luck":
			return "+%d luck" % amount
		"morale":
			return "+%d morale" % amount
		_:
			return ""
