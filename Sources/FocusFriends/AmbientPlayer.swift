import AVFoundation
import Foundation

/// Il generatore: rumore filtrato in tempo reale (niente file). Gira sul thread audio: niente allocazioni.
private final class NoiseSynth {
    /// 0 nessuno, 1 pioggia, 2 marrone, 3 vento. Scritto dal thread principale, letto dal thread audio.
    var kind: Int32 = 0
    var targetGain: Float = 0
    var fadeSeconds: Float = 2

    private var gain: Float = 0
    private let sampleRate: Float
    private var seedL: UInt32 = 0x1234ABCD
    private var seedR: UInt32 = 0x9E3779B9
    private var seedD: UInt32 = 0x2545F491

    private var brownL: Float = 0, brownR: Float = 0
    private var lpL: Float = 0, lpR: Float = 0, hpL: Float = 0, hpR: Float = 0
    private var dropEnv: Float = 0, dropPhase: Float = 0, dropFreq: Float = 2000, dropPan: Float = 0.5
    private var rainPhase: Float = 0
    private var wind1L: Float = 0, wind2L: Float = 0, wind1R: Float = 0, wind2R: Float = 0
    private var lfoA: Float = 0, lfoB: Float = 1.3

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
    }

    @inline(__always)
    private func white(_ s: inout UInt32) -> Float {
        s ^= s << 13
        s ^= s >> 17
        s ^= s << 5
        return Float(Int32(bitPattern: s)) / Float(Int32.max)
    }

    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        let step = 1 / (sampleRate * max(fadeSeconds, 0.05))
        let twoPi = Float.pi * 2
        for i in 0..<frames {
            // Dissolvenza lineare verso il volume voluto
            if gain < targetGain { gain = min(gain + step, targetGain) } else if gain > targetGain { gain = max(gain - step, targetGain) }
            if gain == 0 && targetGain == 0 {
                left[i] = 0
                right[i] = 0
                continue
            }
            let wl = white(&seedL), wr = white(&seedR)
            var l: Float = 0, r: Float = 0
            switch kind {
            case 1: // pioggia: fruscio a banda media + gocce
                lpL += 0.35 * (wl - lpL); hpL += 0.02 * (lpL - hpL)
                lpR += 0.35 * (wr - lpR); hpR += 0.02 * (lpR - hpR)
                rainPhase += twoPi * 0.05 / sampleRate
                if rainPhase > twoPi { rainPhase -= twoPi }
                let level = 0.88 + 0.12 * sin(rainPhase)
                let d = white(&seedD)
                if abs(d) > 0.9988 {                       // circa 25 gocce al secondo
                    dropEnv = 0.18 + 0.32 * abs(white(&seedD))
                    dropFreq = 1500 + 2500 * abs(white(&seedD))
                    dropPhase = 0
                    dropPan = 0.5 + 0.4 * white(&seedD)
                }
                let drop = dropEnv * sin(dropPhase)
                dropPhase += twoPi * dropFreq / sampleRate
                if dropPhase > twoPi { dropPhase -= twoPi }
                dropEnv *= 0.9991
                l = (lpL - hpL) * 0.55 * level + drop * (1 - dropPan)
                r = (lpR - hpR) * 0.55 * level + drop * dropPan
            case 2: // rumore marrone: voce bassa e avvolgente
                brownL = (brownL + 0.02 * wl) / 1.02
                brownR = (brownR + 0.02 * wr) / 1.02
                l = brownL * 3.2
                r = brownR * 3.2
            case 3: // vento: rumore passa-basso che respira
                lfoA += twoPi * 0.07 / sampleRate
                lfoB += twoPi * 0.19 / sampleRate
                if lfoA > twoPi { lfoA -= twoPi }
                if lfoB > twoPi { lfoB -= twoPi }
                let swell = 0.55 + 0.35 * sin(lfoA) + 0.10 * sin(lfoB)
                let a = 0.012 + 0.020 * (0.5 + 0.5 * sin(lfoB))
                wind1L += a * (wl - wind1L); wind2L += a * (wind1L - wind2L)
                wind1R += a * (wr - wind1R); wind2R += a * (wind1R - wind2R)
                l = wind2L * 5 * swell
                r = wind2R * 5 * swell
            default:
                break
            }
            let master: Float = 0.8 * gain
            left[i] = max(-1, min(1, l * master))
            right[i] = max(-1, min(1, r * master))
        }
    }
}

/// Il suono ambiente del focus: parte con il focus, si spegne a fine focus (con una dissolvenza), a volume basso.
final class AmbientPlayer {
    static let shared = AmbientPlayer()

    private let engine = AVAudioEngine()
    private let synth: NoiseSynth
    private var sourceNode: AVAudioSourceNode?
    private var isConfigured = false
    private var stopTimer: Timer?
    private var previewTimer: Timer?

    private(set) var sound: AmbientSound
    private(set) var volume: Double
    /// C'è un focus in corso (con il suono acceso si sente).
    private(set) var focusActive = false

    private static let fade: Float = 2

    init() {
        let saved = AmbientSettings.load()
        sound = saved.sound
        volume = saved.volume
        synth = NoiseSynth(sampleRate: 44100)
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.restartIfNeeded()
        }
    }

    // MARK: - Comandi

    /// Il focus comincia o finisce.
    func setFocusActive(_ active: Bool) {
        focusActive = active
        apply(previewing: false)
    }

    func setSound(_ new: AmbientSound, preview: Bool = true) {
        sound = new
        AmbientSettings.save(sound: sound, volume: volume)
        apply(previewing: preview && !focusActive)
    }

    func setVolume(_ new: Double, preview: Bool = false) {
        volume = AmbientSettings.clamp(new)
        AmbientSettings.save(sound: sound, volume: volume)
        apply(previewing: preview && !focusActive, quick: true)
    }

    // MARK: - Motore

    private func kindValue(_ sound: AmbientSound) -> Int32 {
        switch sound {
        case .none: return 0
        case .rain: return 1
        case .brown: return 2
        case .wind: return 3
        }
    }

    /// Mette il motore nello stato giusto: acceso (al volume scelto) solo se c'è un focus e un suono, o in anteprima.
    private func apply(previewing: Bool, quick: Bool = false) {
        previewTimer?.invalidate()
        previewTimer = nil
        let wanted = sound != .none && (focusActive || previewing)
        if wanted {
            stopTimer?.invalidate()
            stopTimer = nil
            guard startEngine() else { return }
            synth.kind = kindValue(sound)
            // Un cambio di volume si sente subito; l'accensione (e lo spegnimento) sfumano piano.
            synth.fadeSeconds = quick ? 0.25 : Self.fade
            synth.targetGain = Float(volume)
            if previewing {
                // Qualche secondo di anteprima, poi si spegne da solo.
                previewTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
                    self?.apply(previewing: false)
                }
            }
        } else {
            synth.fadeSeconds = Self.fade
            synth.targetGain = 0
            // Dopo la dissolvenza il motore si ferma del tutto (niente CPU per un suono che non c'è).
            stopTimer?.invalidate()
            stopTimer = Timer.scheduledTimer(withTimeInterval: Double(Self.fade) + 0.3, repeats: false) { [weak self] _ in
                guard let self, self.synth.targetGain == 0 else { return }
                self.engine.pause()
            }
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) else { return }
        let synth = self.synth
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            synth.render(frames: Int(frameCount), left: left, right: right)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
        isConfigured = true
    }

    @discardableResult
    private func startEngine() -> Bool {
        configureIfNeeded()
        guard isConfigured else { return false }
        if engine.isRunning { return true }
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    /// Cambiato il dispositivo audio (cuffie, altoparlanti): riparte se doveva suonare.
    private func restartIfNeeded() {
        guard synth.targetGain > 0 else { return }
        _ = startEngine()
    }
}
