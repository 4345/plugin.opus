package plugin.opus;

import com.ansca.corona.CoronaEnvironment;
import com.ansca.corona.CoronaLua;
import com.ansca.corona.CoronaRuntime;
import com.ansca.corona.CoronaRuntimeListener;
import com.naef.jnlua.JavaFunction;
import com.naef.jnlua.LuaState;
import com.naef.jnlua.NamedJavaFunction;

public class LuaLoader implements JavaFunction, CoronaRuntimeListener {
	static {
		System.loadLibrary("plugin_opus");
	}

	// Native method declarations
	private static native long encoderCreate(int sampleRate, int channels, int application);
	private static native byte[] encoderEncode(long encPtr, byte[] pcmBytes, int frameSize);
	private static native int encoderSetDtx(long encPtr, boolean useDtx);
	private static native void encoderDestroy(long encPtr);

	private static native long decoderCreate(int sampleRate, int channels);
	private static native byte[] decoderDecode(long decPtr, byte[] packetBytes, int frameSize, int channels);
	private static native void decoderDestroy(long decPtr);
	private static native byte[] resample(byte[] pcmBytes, int fromRate, int toRate, int channels);
	private static native byte[] normalize(byte[] pcmBytes, double targetRatio);

	// Handles of native objects must never cross into Lua as raw pointers.
	// Lua numbers are doubles with a 53-bit mantissa, while Android 11 and
	// later tag native heap pointers: malloc returns addresses with a
	// non-zero top byte. Such an address does not survive the round trip
	// through a double. It comes back rounded - still non-zero, so a null
	// check passes - but pointing at unrelated memory, and opus then kills
	// the whole process on its hardening check (assertion failed:
	// st->channels == 1 || st->channels == 2). Devices on older Android
	// were unaffected only because their pointers stayed below 2^53.
	// Lua now gets a small sequential id; the pointer never leaves Java.
	private static final java.util.HashMap<Long, Long> sNativeHandles =
		new java.util.HashMap<Long, Long>();
	private static long sNextHandleId = 0;

	private static synchronized long registerHandle(long ptr) {
		if (ptr == 0) {
			return 0;
		}
		sNativeHandles.put(++sNextHandleId, ptr);
		return sNextHandleId;
	}

	private static synchronized long handlePointer(long id) {
		Long ptr = sNativeHandles.get(id);
		return (ptr == null) ? 0 : ptr;
	}

	// Also makes a repeated destroy harmless: the id is gone after the
	// first one, so __gc running after an explicit destroy() cannot free
	// the same pointer twice.
	private static synchronized long releaseHandle(long id) {
		Long ptr = sNativeHandles.remove(id);
		return (ptr == null) ? 0 : ptr;
	}

	public LuaLoader() {
		CoronaEnvironment.addRuntimeListener(this);
	}

	@Override
	public int invoke(LuaState L) {
		NamedJavaFunction[] jniFunctions = new NamedJavaFunction[] {
			new EncoderCreate(),
			new EncoderEncode(),
			new EncoderSetDtx(),
			new EncoderDestroy(),
			new DecoderCreate(),
			new DecoderDecode(),
			new DecoderDestroy(),
			new Resample(),
			new Normalize(),
		};
		String libName = L.toString(1);
		L.register("plugin.opus.raw", jniFunctions);

		// Execute Lua wrapper script to expose object-oriented API
		L.load(
			"local raw = package.loaded['plugin.opus.raw']\n" +
			"local M = {}\n" +
			"function M.encoder_create(sampleRate, channels, application)\n" +
			"    local ptr = raw.encoderCreate(sampleRate, channels, application)\n" +
			"    if not ptr or ptr == 0 then return nil, 'failed to create encoder' end\n" +
			"    local enc = setmetatable({ _ptr = ptr }, {\n" +
			"        __gc = function(t)\n" +
			"            if t._ptr then\n" +
			"                raw.encoderDestroy(t._ptr)\n" +
			"                t._ptr = nil\n" +
			"            end\n" +
			"        end\n" +
			"    })\n" +
			"    function enc:encode(pcm, frameSize)\n" +
			"        return raw.encoderEncode(self._ptr, pcm, frameSize)\n" +
			"    end\n" +
			"    function enc:set_dtx(dtx)\n" +
			"        return raw.encoderSetDtx(self._ptr, dtx)\n" +
			"    end\n" +
			"    function enc:destroy()\n" +
			"        if self._ptr then\n" +
			"            raw.encoderDestroy(self._ptr)\n" +
			"            self._ptr = nil\n" +
			"        end\n" +
			"    end\n" +
			"    return enc\n" +
			"end\n" +
			"function M.decoder_create(sampleRate, channels)\n" +
			"    local ptr = raw.decoderCreate(sampleRate, channels)\n" +
			"    if not ptr or ptr == 0 then return nil, 'failed to create decoder' end\n" +
			"    local dec = setmetatable({ _ptr = ptr, _channels = channels }, {\n" +
			"        __gc = function(t)\n" +
			"            if t._ptr then\n" +
			"                raw.decoderDestroy(t._ptr)\n" +
			"                t._ptr = nil\n" +
			"            end\n" +
			"        end\n" +
			"    })\n" +
			"    function dec:decode(packet, frameSize)\n" +
			"        return raw.decoderDecode(self._ptr, packet, frameSize, self._channels)\n" +
			"    end\n" +
			"    function dec:destroy()\n" +
			"        if self._ptr then\n" +
			"            raw.decoderDestroy(self._ptr)\n" +
			"            self._ptr = nil\n" +
			"        end\n" +
			"    end\n" +
			"    return dec\n" +
			"end\n" +
			"function M.resample(pcm, fromRate, toRate, channels)\n" +
			"    return raw.resample(pcm, fromRate, toRate, channels)\n" +
			"end\n" +
			"function M.normalize(pcm, targetRatio)\n" +
			"    return raw.normalize(pcm, targetRatio)\n" +
			"end\n" +
			"package.loaded['plugin.opus'] = M\n" +
			"return M\n",
			"opus_wrapper"
		);
		L.call(0, 1);

		return 1;
	}

	@Override public void onLoaded(CoronaRuntime runtime) {}
	@Override public void onStarted(CoronaRuntime runtime) {}
	@Override public void onSuspended(CoronaRuntime runtime) {}
	@Override public void onResumed(CoronaRuntime runtime) {}
	@Override public void onExiting(CoronaRuntime runtime) {}

	// NamedJavaFunctions for JNI binding
	private static class EncoderCreate implements NamedJavaFunction {
		@Override public String getName() { return "encoderCreate"; }
		@Override public int invoke(LuaState L) {
			int sampleRate = L.checkInteger(1);
			int channels = L.checkInteger(2);
			int application = L.checkInteger(3);
			L.pushNumber(registerHandle(encoderCreate(sampleRate, channels, application)));
			return 1;
		}
	}

	private static class EncoderEncode implements NamedJavaFunction {
		@Override public String getName() { return "encoderEncode"; }
		@Override public int invoke(LuaState L) {
			long ptr = handlePointer((long) L.checkNumber(1));
			if (ptr == 0) {
				return 0;
			}
			byte[] pcm = L.toByteArray(2);
			int frameSize = L.checkInteger(3);
			byte[] packet = encoderEncode(ptr, pcm, frameSize);
			if (packet != null) {
				L.pushString(packet);
				return 1;
			}
			return 0;
		}
	}

	private static class EncoderSetDtx implements NamedJavaFunction {
		@Override public String getName() { return "encoderSetDtx"; }
		@Override public int invoke(LuaState L) {
			long ptr = handlePointer((long) L.checkNumber(1));
			if (ptr == 0) {
				L.pushInteger(-1);
				return 1;
			}
			boolean dtx = L.toBoolean(2);
			int status = encoderSetDtx(ptr, dtx);
			L.pushInteger(status);
			return 1;
		}
	}

	private static class EncoderDestroy implements NamedJavaFunction {
		@Override public String getName() { return "encoderDestroy"; }
		@Override public int invoke(LuaState L) {
			long ptr = releaseHandle((long) L.checkNumber(1));
			if (ptr != 0) {
				encoderDestroy(ptr);
			}
			return 0;
		}
	}

	private static class DecoderCreate implements NamedJavaFunction {
		@Override public String getName() { return "decoderCreate"; }
		@Override public int invoke(LuaState L) {
			int sampleRate = L.checkInteger(1);
			int channels = L.checkInteger(2);
			L.pushNumber(registerHandle(decoderCreate(sampleRate, channels)));
			return 1;
		}
	}

	private static class DecoderDecode implements NamedJavaFunction {
		@Override public String getName() { return "decoderDecode"; }
		@Override public int invoke(LuaState L) {
			long ptr = handlePointer((long) L.checkNumber(1));
			if (ptr == 0) {
				return 0;
			}
			byte[] packet = L.toByteArray(2);
			int frameSize = L.checkInteger(3);
			int channels = L.checkInteger(4);
			byte[] pcm = decoderDecode(ptr, packet, frameSize, channels);
			if (pcm != null) {
				L.pushString(pcm);
				return 1;
			}
			return 0;
		}
	}

	private static class DecoderDestroy implements NamedJavaFunction {
		@Override public String getName() { return "decoderDestroy"; }
		@Override public int invoke(LuaState L) {
			long ptr = releaseHandle((long) L.checkNumber(1));
			if (ptr != 0) {
				decoderDestroy(ptr);
			}
			return 0;
		}
	}

	private static class Resample implements NamedJavaFunction {
		@Override public String getName() { return "resample"; }
		@Override public int invoke(LuaState L) {
			byte[] pcm = L.toByteArray(1);
			int fromRate = L.checkInteger(2);
			int toRate = L.checkInteger(3);
			int channels = L.checkInteger(4);
			byte[] resampled = resample(pcm, fromRate, toRate, channels);
			if (resampled != null) {
				L.pushString(resampled);
				return 1;
			}
			return 0;
		}
	}

	private static class Normalize implements NamedJavaFunction {
		@Override public String getName() { return "normalize"; }
		@Override public int invoke(LuaState L) {
			byte[] pcm = L.toByteArray(1);
			double targetRatio = L.checkNumber(2);
			byte[] normalized = normalize(pcm, targetRatio);
			if (normalized != null) {
				L.pushString(normalized);
				return 1;
			}
			return 0;
		}
	}
}
