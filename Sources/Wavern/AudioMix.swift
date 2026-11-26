import Accelerate
import CoreAudio

/// Realtime mix of a process tap into the output device. Runs on the IO
/// thread: no allocation, no locks, no logging.
enum AudioMix {
    /// Mixa o tap (último buffer de entrada) para todos os buffers de saída.
    /// `gainState[0]` = ganho alvo (escrito pela UI); `gainState[1]` = último
    /// ganho aplicado (só o IO escreve). Rampa linear de [1] para [0] ao longo
    /// do buffer. Retorna true se a entrada tinha alguma amostra != 0.
    static func render(input: UnsafeMutableAudioBufferListPointer,
                       output: UnsafeMutableAudioBufferListPointer,
                       gainState: UnsafeMutablePointer<Float>) -> Bool {
        let target = gainState[0]
        let start = gainState[1]
        gainState[1] = target
        for i in 0..<output.count where output[i].mData != nil {
            memset(output[i].mData!, 0, Int(output[i].mDataByteSize))
        }
        // ponytail: assume tap = último stream de entrada; se o log mostrar outra ordem, procurar o stream pelo kAudioStreamPropertyStartingChannel do tap
        guard input.count > 0, output.count > 0 else { return false }
        let inBuf = input[input.count - 1], outBuf = output[0]
        guard let srcRaw = inBuf.mData, let dstRaw = outBuf.mData,
              inBuf.mNumberChannels > 0, outBuf.mNumberChannels > 0 else { return false }
        let src = srcRaw.assumingMemoryBound(to: Float.self)
        let dst = dstRaw.assumingMemoryBound(to: Float.self)
        let inCh = Int(inBuf.mNumberChannels), outCh = Int(outBuf.mNumberChannels)
        let inFloats = Int(inBuf.mDataByteSize) / MemoryLayout<Float>.size
        let outFloats = Int(outBuf.mDataByteSize) / MemoryLayout<Float>.size

        var peak: Float = 0
        vDSP_maxmgv(src, 1, &peak, vDSP_Length(inFloats))

        let frames = min(inFloats / inCh, outFloats / outCh)
        guard frames > 0 else { return peak > 0 }
        let step = (target - start) / Float(frames)
        for f in 0..<frames {
            let g = start + step * Float(f)
            let l = src[f * inCh]
            let r = inCh >= 2 ? src[f * inCh + 1] : l
            if outCh == 1 {
                dst[f] = (l + r) * 0.5 * g
            } else {
                dst[f * outCh] = l * g
                dst[f * outCh + 1] = r * g
            }
        }
        return peak > 0
    }
}
