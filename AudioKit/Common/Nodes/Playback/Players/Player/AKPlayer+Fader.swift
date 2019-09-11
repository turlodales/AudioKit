//
//  AKPlayer+Fader.swift
//  AudioKit
//
//  Created by Ryan Francesconi on 6/12/18.
//  Copyright © 2018 AudioKit. All rights reserved.
//

/// The Fader is also used for the gain stage of the player
extension AKPlayer {
    public struct Fade {
        /// So that the Fade struct can be used outside of AKPlayer
        public init() {}

        /// a constant
        public static var minimumGain: Double = 0.0002

        /// the value that the booster should fade to, settable
        public var maximumGain: Double = 1

        public var inTime: Double = 0 {
            willSet {
                if newValue != inTime { needsUpdate = true }
            }
        }

        // TODO:
        public var inRampType: AKSettings.RampType = .linear {
            willSet {
                if newValue != inRampType { needsUpdate = true }
            }
        }

        // TODO:
        public var outRampType: AKSettings.RampType = .linear {
            willSet {
                if newValue != outRampType { needsUpdate = true }
            }
        }

        // if you want to start midway into a fade
        public var inTimeOffset: Double = 0

        // Currently Unused
        public var inStartGain: Double = minimumGain

        public var outTime: Double = 0 {
            willSet {
                if newValue != outTime { needsUpdate = true }
            }
        }

        public var outTimeOffset: Double = 0

        // Currently Unused
        public var outStartGain: Double = 1

        // the needsUpdate flag is used by the buffering scheme
        var needsUpdate: Bool = false
    }

    internal func createFader() {
        // only do this once when needed
        guard faderNode == nil else { return }

        AKLog("Creating fader")
        faderNode = AKFader()
        faderNode?.gain = gain
        // faderNode?.rampType = rampType

        initialize()
    }

    internal func scheduleFader(at audioTime: AVAudioTime?, hostTime: UInt64?, frameOffset: AVAudioFramePosition = 512) {
        guard let audioTime = audioTime, let faderNode = faderNode else { return }

        // AKLog(fade, faderNode?.rampDuration, faderNode?.gain, audioTime, hostTime)
        // 4 render cycles in the future in order to put after AUEventSampleTimeImmediate events

        // reset automation if it is running
        faderNode.stopAutomation()

        let inTimeInSamples: AUEventSampleTime = frameOffset

        var inTime = fade.inTime
        if inTime > 0 {
            let value = fade.maximumGain
            var fadeFrom = Fade.minimumGain

            // starting in the middle of a fade in
            if fade.inTimeOffset > 0 && fade.inTimeOffset < inTime {
                let ratio = fade.inTimeOffset / inTime
                fadeFrom = value * ratio
                inTime -= fade.inTimeOffset

                AKLog("In middle of a fade IN... adjusted inTime to", inTime)
            } else {
                // set immediately to 0
                faderNode.gain = Fade.minimumGain
            }

            let rampSamples = AUAudioFrameCount(inTime * sampleRate)

            AKLog("Scheduling fade IN to value:", value, "at inTimeInSamples", inTimeInSamples, "rampDuration", rampSamples, "fadeFrom", fadeFrom, "fade.inTimeOffset", fade.inTimeOffset)

            // inTimeInSamples
            faderNode.addAutomationPoint(value: fadeFrom, at: AUEventSampleTimeImmediate, anchorTime: audioTime.sampleTime, rampDuration: AUAudioFrameCount(0), rampType: fade.inRampType)

            // then fade it in
            faderNode.addAutomationPoint(value: value, at: inTimeInSamples, anchorTime: audioTime.sampleTime, rampDuration: rampSamples, rampType: fade.inRampType)
        }

        var outTime = fade.outTime
        if outTime > 0 {
            // when the start of the fade out should occur
            var timeTillFadeOut = (duration - startTime) - (duration - endTime) - outTime

            // adjust the scheduled fade out based on the playback rate
            if _rate != 1 {
                timeTillFadeOut /= _rate
            }
            var outTimeInSamples = inTimeInSamples + AUEventSampleTime(timeTillFadeOut * sampleRate)
            var outOffset: AUEventSampleTime = 0

            // starting in the middle of a fade out
            if fade.outTimeOffset > 0, fade.outTimeOffset > duration - outTime {
                // just fade now the remainder of the segment
                var newOutTime = duration - startTime
                if endTime < duration {
                    newOutTime -= (duration - endTime)
                }

                AKLog("In middle of a fade out... adjusted outTime to", newOutTime)

                outTimeInSamples = 0

                let ratio = newOutTime / outTime
                let fadeFrom = fade.maximumGain * ratio
                faderNode.addAutomationPoint(value: fadeFrom, at: outTimeInSamples, anchorTime: audioTime.sampleTime, rampDuration: AUAudioFrameCount(0), rampType: fade.inRampType)

                outTime = newOutTime
                outOffset = frameOffset

            } else if inTime == 0 {
                AKLog("reset to ", fade.maximumGain, "if there is no fade in or are past it")
                // inTimeInSamples
                faderNode.addAutomationPoint(value: fade.maximumGain, at: AUEventSampleTimeImmediate, anchorTime: audioTime.sampleTime, rampDuration: AUAudioFrameCount(0), rampType: fade.inRampType)
            }

            // must adjust for _rate
            let fadeLengthInSamples = AUAudioFrameCount((outTime / _rate) * sampleRate)

            let value = Fade.minimumGain

            AKLog("Scheduling fade OUT (\(outTime) sec) to value:", value, "at outTimeInSamples", outTimeInSamples, "fadeLengthInSamples", fadeLengthInSamples)
            faderNode.addAutomationPoint(value: value, at: outTimeInSamples + outOffset, anchorTime: audioTime.sampleTime, rampDuration: fadeLengthInSamples, rampType: fade.outRampType)
        }
    }
}
