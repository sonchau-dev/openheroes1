extends RefCounted

## Sound effects. 169 entries, headerless raw PCM, signed 8-bit mono.
##
## The Python extractor wrote them as 16-bit signed, which fused every pair of
## samples into one and played the result at double speed. Three things say
## 8-bit: 91 of the 169 payloads have an odd byte length, which a 16-bit mono
## stream cannot; the even and odd byte subsequences are equally smooth, where
## a 16-bit reading would make one noisy and one smooth; and read as signed
## 8-bit the mean sample sits on zero and fills the range.
##
## The rate is stored nowhere. No entry carries the "82M " magic the notes
## describe, so 22050 Hz is out-of-band knowledge, confirmed by ear against the
## DOS original.
##
## WAV stores 8-bit PCM unsigned, so every sample gains a 128 bias on the way
## out.

const BIAS := 128


## Returns {ok, error, pcm}, where `pcm` is unsigned 8-bit ready for a WAV
## data chunk.
static func decode(data: PackedByteArray) -> Dictionary:
	if data.is_empty():
		return {"ok": false, "error": "payload is empty", "pcm": PackedByteArray()}
	var pcm := data.duplicate()
	for i in pcm.size():
		pcm[i] = (pcm[i] + BIAS) & 0xFF
	return {"ok": true, "error": "", "pcm": pcm}
