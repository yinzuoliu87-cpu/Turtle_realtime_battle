# 只读解析 LoL PROP .bin(ritobin 格式), 找出娜美大招的 VfxSystemDefinitionData 并打印成可读的树
import glob
import json
import os
import struct
import sys

sys.stdout.reconfigure(encoding="utf-8")


def fnv(s):
	h = 0x811C9DC5
	for c in s.lower().encode():
		h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF
	return h


NAMES = """VfxSystemDefinitionData VfxEmitterDefinitionData complexEmitterDefinitionData simpleEmitterDefinitionData particleName particlePath
emitterName texture particleLifetime lifetime birthColor color birthScale0 scale0 birthVelocity velocity blendMode rate birthRotation0 rotation0
birthRotationalVelocity0 emitterPosition primitive mMesh mSimpleMeshName mMeshName erosionDefinition erosionDriveCurve erosionMapName erosionSliceWidth
particleColorTexture texDiv isSingleParticle particleLinger timeBeforeFirstEmission bindWeight worldAcceleration birthDrag drag constantValue dynamics
times values birthUvoffset birthUvScrollRate uvScrollRate texAddressModeBase colorLookUpTypeX colorLookUpTypeY alphaRef isUniformScale scaleEmitterOffsetByBoundsSize
emissionSurfaceDefinition shape birthAcceleration acceleration disabled importance soundOnCreateDefault flags visibilityRadius particleIsLocalOrientation
isDirectionOriented direction orientation miscRenderFlags pass depthBiasFactors isRandomStartFrame numFrames frameRate startFrame uvMode
birthFrameRate textureMult texDivMult particleColorLookupScale particleColorLookupOffset modulationFactor filtering alphaErosionTextureName
birthTranslation translation birthOrbitalVelocity reflectionDefinition fresnel fresnelColor reflectionOpacityDirect reflectionMapTexture
emitterLinger emitterLifetime isFollowingTerrain chance meshRenderFlags textureFlipU textureFlipV hasPostRotateOrientation useNavmeshMask
VfxPrimitiveMesh VfxPrimitiveArbitraryQuad VfxPrimitiveCameraUnbound VfxPrimitiveCameraTrail VfxPrimitiveArbitraryTrail VfxPrimitiveBeam VfxMeshDefinitionData
ValueFloat ValueVector2 ValueVector3 ValueColor ValueVector4 VfxAnimatedFloatVariableData VfxAnimatedVector3fVariableData VfxAnimatedColorVariableData
VfxProbabilityTableData VfxEmitterLegacySimple VfxEmissionSurfaceData VfxAlphaErosionDefinitionData VfxShape VfxShapeLegacy VfxShapeBox VfxShapeSphere VfxShapeCylinder
emitOffset emitRotationAngles emitRotationAxes radius height flags keyName probabilityTables singleValue VfxFieldCollectionDefinitionData fieldCollectionDefinition
fieldAccelerationDefinitions fieldDragDefinitions fieldNoiseDefinitions VfxFieldNoiseDefinitionData frequency velocityDelta axisFraction
mAnimationName mAnimationLoops mAnimationRate mAnimationVariants mSubmeshesToDraw mLockMeshToAttachment mMeshSkeletonName meshSkeletonName
scaleBirthScaleByBoundObjectSize postRotateOrientation0 headScale tailScale mTrail mBirthTilingSize mCutoff mMode mMaxAddedPerFrame
childParticleSetDefinition childrenIdentifiers childEmitOnDeath ChildParticleSetDefinitionData VfxChildIdentifier effect effectKey effectName
material MaterialInstanceDef StaticMaterialDef paramValues name value textureName samplerValues soundPersistentDefault
tex0 texture1 textureMult0 particleUVScrollRate particleUvRotateRate uvRotation uvScale0 uvTransformCenter""".split()
NM = {fnv(n): n for n in NAMES}
TY = {0: "none", 1: "bool", 2: "i8", 3: "u8", 4: "i16", 5: "u16", 6: "i32", 7: "u32", 8: "i64", 9: "u64", 10: "f32", 11: "vec2", 12: "vec3",
      13: "vec4", 14: "mtx44", 15: "rgba", 16: "string", 17: "hash", 18: "file", 0x80: "list", 0x81: "list2", 0x82: "pointer", 0x83: "embed",
      0x84: "link", 0x85: "option", 0x86: "map", 0x87: "flag"}


def nm(h):
	return NM.get(h, "#%08x" % h)


class R:
	def __init__(s, b, p=0):
		s.b = b
		s.p = p

	def u(s, fmt):
		v = struct.unpack_from("<" + fmt, s.b, s.p)
		s.p += struct.calcsize("<" + fmt)
		return v if len(v) > 1 else v[0]

	def val(s, t):
		if t == 0: return None
		if t == 1 or t == 3 or t == 0x87: return s.u("B")
		if t == 2: return s.u("b")
		if t == 4: return s.u("h")
		if t == 5: return s.u("H")
		if t == 6: return s.u("i")
		if t == 7: return s.u("I")
		if t == 8: return s.u("q")
		if t == 9 or t == 18: return "0x%016x" % s.u("Q")
		if t == 10: return round(s.u("f"), 4)
		if t == 11: return [round(x, 3) for x in s.u("2f")]
		if t == 12: return [round(x, 3) for x in s.u("3f")]
		if t == 13: return [round(x, 3) for x in s.u("4f")]
		if t == 14: return [round(x, 3) for x in s.u("16f")]
		if t == 15: return list(s.u("4B"))
		if t == 16:
			n = s.u("H")
			v = s.b[s.p:s.p + n].decode("utf-8", "replace")
			s.p += n
			return v
		if t == 17 or t == 0x84: return nm(s.u("I"))
		if t in (0x80, 0x81):
			vt = s.u("B"); size = s.u("I"); cnt = s.u("I")
			return [s.val(vt) for _ in range(cnt)]
		if t in (0x82, 0x83):
			ch = s.u("I")
			if ch == 0: return None
			size = s.u("I"); fc = s.u("H")
			o = {"_class": nm(ch)}
			for _ in range(fc):
				fh = s.u("I"); ft = s.u("B")
				o[nm(fh)] = s.val(ft)
			return o
		if t == 0x85:
			vt = s.u("B"); c = s.u("B")
			return s.val(vt) if c else None
		if t == 0x86:
			kt = s.u("B"); vt = s.u("B"); size = s.u("I"); cnt = s.u("I")
			out = {}
			for _ in range(cnt):
				k = s.val(kt); out[str(k)] = s.val(vt)
			return out
		raise ValueError("type %d at %d" % (t, s.p))


def parse(b):
	r = R(b)
	assert r.u("4s") == b"PROP"
	ver = r.u("I")
	if ver >= 2:
		lc = r.u("I")
		for _ in range(lc):
			n = r.u("H"); r.p += n
	ec = r.u("I")
	types = [r.u("I") for _ in range(ec)]
	ents = {}
	for i in range(ec):
		ln = r.u("I"); start = r.p
		key = r.u("I"); fc = r.u("H")
		o = {"_class": nm(types[i])}
		try:
			for _ in range(fc):
				fh = r.u("I"); ft = r.u("B")
				o[nm(fh)] = r.val(ft)
		except Exception as ex:
			o["_err"] = str(ex)
		r.p = start + ln
		ents[key] = o
	return ents


want = {fnv("Characters/Nami/Skins/Skin0/Particles/Nami_Base_R_" + s): s for s in
        ["cas_02", "curl", "indicator", "mis", "splash", "splash_end", "tar"]}
found = {}
for fn in sorted(glob.glob(os.path.join(sys.argv[1], "*.bin"))):
	b = open(fn, "rb").read()
	if b[:4] != b"PROP":
		continue
	try:
		ents = parse(b)
	except Exception as ex:
		continue
	for k, v in ents.items():
		if k in want and want[k] not in found:
			found[want[k]] = v
			print("found", want[k], "in", os.path.basename(fn))
json.dump(found, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("systems", len(found))
