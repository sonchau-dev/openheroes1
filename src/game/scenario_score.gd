class_name ScenarioScore
extends RefCounted

## Calculates scenario points and final score per authentic HOMM1 formula.
## Reference: data/knowledge_base/score.md (HandbookHMM.ru / AlexSPl).

## Base points earned based on the number of elapsed game days (heroes.exe 0x86318).
static func points(days: int) -> int:
	var n := maxi(1, days)
	var pts: int
	if n <= 60:
		pts = 200 - n
	elif n <= 120:
		pts = int(floor(170.0 - float(n) / 2.0))
	elif n <= 360:
		pts = int(floor(140.0 - float(n) / 4.0))
	elif n <= 592:
		pts = int(floor(95.0 - float(n) / 8.0))
	else:
		pts = 20
	return maxi(20, pts)

## Final score = points * rating / 100 in integers, truncated (heroes.exe
## 0xcd997). rating_percent is the integer percentage, e.g. 60 for 60%.
static func calculate(days: int, rating_percent: int) -> int:
	return points(days) * rating_percent / 100
