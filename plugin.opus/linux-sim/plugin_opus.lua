local Library = require "CoronaLibrary"

-- Create library
local lib = Library:new{ name='plugin.opus', publisherId='ovh.azi' }

lib.encoder_create = function(sampleRate, channels, application)
    print("WARNING: plugin.opus.encoder_create is a stub on this platform.")
    local enc = {}
    function enc:encode(pcm, frameSize) return "" end
    function enc:set_dtx(dtx) return 0 end
    function enc:destroy() end
    return enc
end

lib.decoder_create = function(sampleRate, channels)
    print("WARNING: plugin.opus.decoder_create is a stub on this platform.")
    local dec = {}
    function dec:decode(packet, frameSize) return "" end
    function dec:destroy() end
    return dec
end

lib.resample = function(pcm, fromRate, toRate, channels)
    print("WARNING: plugin.opus.resample is a stub on this platform.")
    return pcm
end

lib.normalize = function(pcm, targetRatio)
    print("WARNING: plugin.opus.normalize is a stub on this platform.")
    return pcm
end

return lib
