/* -------------------------------------------------------------------------- */

import std_;
import W32_ = core.sys.windows.windows;

/* -------------------------------------------------------------------------- */

/* decoder for FL Studio 8 envelope state files (.fnv) */

struct Stateº {
	Prologueº Prol;
	Epilogueº Epil;
	Pointº[] Points;
};

struct Prologueº {
	FileTypeº Type;
	uint Version; /* 2: FL8 */
	uint PointCount;
};

enum FileTypeº : uint {
	Envelope = 1,
	Lfo,
	Map,
};

struct Pointº {
	double Time = 0; /* beats or half-seconds */
	double Value = 0; /* 0.0 to 1.0 */
	float Tension = 0; /* -1.0 to 1.0 */
	Shapeº Shape;
};

enum Shapeº : uint {
	SingleCurve,
	DoubleCurve,
	Hold,
	Stairs,
	SmoothStairs,
};

struct Epilogueº {
	uint IsTempoBased;
	uint IsEnabled = uint.max;
	uint DecayIdx = uint.max;
	uint SustainStartIdx = uint.max;
	uint SustainEndIdx = uint.max;

	uint AttackTimeScale = 0x80;
	uint DecayTimeScale = 0x80;
	uint SustainOffset;
	uint ReleaseTimeScale = 0x80;
};

void main(in string[] Params) {
	if (Params.length != 3) {
		writeln_(`Converts an FL Studio 8 envelope state file `~
			`between tempo-based time and absolute time.`);
		writeln_(``);
		writeln_(`fnvconv.exe 175 "source.fnv"`);
		writeln_(``);
		writeln_('\t'~`Only integral BPMs are supported.`);
		writeln_('\t'~`Envelopes with timescale knobs at non-default values `~
			`are not supported.`);
		return;
	};

	auto SrcFilePath = Params[2];
	uint Bpm = Params[1].to_!uint;
	enforce_(Bpm > 0, `invalid tempo`);

	Stateº Src = File_(SrcFilePath)
		.byChunk(4096)
		.joiner_
		.decode;

	try {
		validate(Src);
	} catch (Exception X) {
		auto Y = new Exception(`malformed or unsupported input file`);
		Y.next = X;
		throw Y;
	};

	auto DstFilePath = SrcFilePath
		.stripExtension_
		.chain_(Src.Epil.IsTempoBased ? `-absolute-time` : `-tempo-time`)
		.byUTF_!char
		.array_
		.setExtension_(SrcFilePath.extension_);

	auto DstFile = File_(DstFilePath, `wb`);
	Src.convert(Bpm)
		.encode
		.copy_(DstFile.lockingBinaryWriter);
	DstFile.close();

	writeln_(`Converted envelope written to "`, DstFilePath, `".`);
};

/* ubyte range -> Stateº */
Stateº decode(Tº)(Tº Srcª) if (
	isInputRange_!Tº && is(ElementType_!Tº == ubyte)
) {
	scope Src = inputRangeObject_(&Srcª);

	auto f(Xº)() {
		ubyte[Xº.sizeof] Buf;
		foreach (ref X; Buf) {
			enforce_(!Src.empty);
			X = Src.front;
			Src.popFront();
		};
		return raw_cast!Xº(Buf);
	};

	Stateº S;
	S.Prol = f!Prologueº();
	S.Points = iota_(S.Prol.PointCount)
		.map_!(_ => f!Pointº())
		.array_;
	S.Epil = f!Epilogueº();
	return S;
};

/* Stateº -> ubyte range */
auto encode(in Stateº S) {
	return chain_(
		S.Prol.bytes_of.dup,
		S.Points
			.map_!(X => X.bytes_of.dup)
			.joiner_,
		S.Epil.bytes_of.dup
	);
};

/* tempo-based Stateº <-> absolute-time Stateº */
Stateº convert(in Stateº Src, uint Bpm) {
	immutable Bps = Bpm / 60.0;

	Stateº Dst = {Prol : Src.Prol, Epil : Src.Epil};
	Dst.Epil.IsTempoBased = !Src.Epil.IsTempoBased;
	reserve(Dst.Points, Src.Points.length);

	foreach (Pointº P; Src.Points) {/* verify arithmetic */
		enforce_(P.Time >= 0 && P.Time.isFinite_);
		P.Time = Src.Epil.IsTempoBased ?
			(P.Time / Bps) * 2 /* to absolute time (half-seconds) */
		:
			(P.Time / 2) * Bps /* to tempo-based time (beats) */
		;
		Dst.Points ~= P;
	};

	return Dst;
};

void validate(in Stateº S) {
	enforce_(S.Prol.Type == FileTypeº.Envelope);
	enforce_(S.Prol.Version == 2);
	enforce_(S.Prol.PointCount == S.Points.length);

	foreach (P; S.Points) {
		enforce_(isFinite_(P.Time) && P.Time >= 0);
		enforce_(isFinite_(P.Value) && 0 <= P.Value && P.Value <= 1);
		enforce_(P.Shape.among_(EnumMembers_!Shapeº));
	};

	enforce_(S.Epil.IsTempoBased == 0 || S.Epil.IsTempoBased == 1);
	enforce_(S.Epil.IsEnabled == 0 || S.Epil.IsEnabled == uint.max);

	enforce_(S.Epil.DecayIdx < S.Prol.PointCount ||
		S.Epil.DecayIdx == uint.max);
	enforce_(S.Epil.SustainStartIdx < S.Prol.PointCount ||
		S.Epil.SustainStartIdx == uint.max);
	enforce_(S.Epil.SustainEndIdx < S.Prol.PointCount ||
		S.Epil.SustainEndIdx == uint.max);

	/* timescale knobs not supported */
	enforce_(S.Epil.AttackTimeScale == 0x80);
	enforce_(S.Epil.DecayTimeScale == 0x80);
	enforce_(S.Epil.SustainOffset == 0);
	enforce_(S.Epil.ReleaseTimeScale == 0x80);
};

/* --- miscellaneous -------------------------------------------------------- */

auto ref raw_cast(Toº, Fromº)(auto ref Fromº X) @trusted if (
	Toº.sizeof == Fromº.sizeof
) {
	return *(cast(Toº*) &X);
};

auto ref bytes_of(Xº)(auto ref Xº X) @trusted {
	return raw_cast!(ubyte[X.sizeof])(X);
};

/* -------------------------------------------------------------------------- */

/+
































+/

/* -------------------------------------------------------------------------- */
