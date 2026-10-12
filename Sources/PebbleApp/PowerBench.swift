// Hands-free power benchmark (PEBBLE_POWERBENCH=1, with PEBBLE_AUTOLOAD and
// PEBBLE_NEWWORLD=<seed>): plays the same ten minutes every run so builds
// and settings can be compared without anyone holding the device. Record
// it with Instruments' Power Profiler for energy; this logs what the game
// itself can see, every 10 s and per phase:
//
//   explore  fly a straight line through new terrain at sprinting speed,
//            looking side to side (generation, lighting, meshing)
//   revisit  turn around over terrain that's already loaded or saved
//   dig      land and hold dig, looking down, turning slowly
//   pause    the pause menu over the world
//   idle     back in the world, no input
//
// PEBBLE_POWERBENCH=0.2 scales every phase (a 2-minute smoke run);
// PEBBLE_BENCH_PHASES="idle:300" runs just those phases (name:seconds,…),
// e.g. a LAN host standing still while guests explore. Rows go
// to stdout ("[power] …") and <debugOutputDir>/pebble-power.csv; the app
// exits when done.

import Foundation
import QuartzCore
import PebbleCore

final class PowerBench {
    private unowned let rt: GameRuntime
    private var game: GameCore { rt.game }
    private let phases: [(name: String, secs: Double)]
    private var phase = -1
    private var phaseT0 = 0.0
    private var settleFrames = 0
    private var heading = 0.0

    private struct Sample {
        var t: Double, cpu: Double, gpuMs: Double, frames: Int, battery: Double?
    }
    private var frames = 0
    private var rowStart: Sample?
    private var phaseStart: Sample?
    private var phaseMaxThermal = 0
    private var csv = ["t_s,phase,fps,cpu_pct,gpu_pct,gpu_ms_per_frame,thermal,battery_pct,charging,low_power,mem_mb,render_scale,sections"]
    private var summary: [String] = []
    private let t0 = CACurrentMediaTime()
    private let outPath = debugOutputDir() + "/pebble-power.csv"

    init(_ rt: GameRuntime, scale: Double) {
        self.rt = rt
        let s = max(0.05, scale)
        var list: [(String, Double)] = [("explore", 180), ("revisit", 90), ("dig", 90), ("pause", 120), ("idle", 120)]
        if let spec = ProcessInfo.processInfo.environment["PEBBLE_BENCH_PHASES"] {
            list = spec.split(separator: ",").compactMap {
                let kv = $0.split(separator: ":")
                return kv.count == 2 ? (String(kv[0]), Double(kv[1]) ?? 60) : nil
            }
        }
        phases = list.map { ($0.0, $0.1 * s) }
        rt.platform.setBatteryMonitoring(true)
    }

    /// once per frame, before the game advances
    func frame() {
        guard game.hasWorld(), let p = game.player else { return }
        // wait out the loading screen and a few seconds of spawn streaming
        if phase < 0 {
            if rt.ui.hasScreen() { return }
            settleFrames += 1
            if settleFrames == 1 {
                for c in ["/gamemode creative", "/time set 1000", "/weather clear", "/gamerule doDaylightCycle false"] {
                    runCommand(game, c)
                }
            }
            if settleFrames < 180 { return }
            heading = p.yaw
            let st = game.settings
            print("[power] start: \(PEBBLE_BUILD), \(phases.map { "\($0.name) \(Int($0.secs))s" }.joined(separator: ", "))")
            print("[power] settings: maxFps \(st.maxFps), shadows \(st.shadows), battery saver \(st.batterySaver == true), bloom \(st.bloom), render distance \(st.renderDistance)")
            begin(0)
            return
        }
        frames += 1
        let now = CACurrentMediaTime()
        let t = now - phaseT0
        phaseMaxThermal = max(phaseMaxThermal, ProcessInfo.processInfo.thermalState.rawValue)
        drive(p, t)
        if let r = rowStart, now - r.t >= 10 { row() }
        if t >= phases[phase].secs {
            if rowStart.map({ now - $0.t >= 1 }) ?? false { row() }
            endPhase()
            if phase + 1 < phases.count { begin(phase + 1) } else { finish() }
        }
    }

    // MARK: - the scripted session

    private func begin(_ i: Int) {
        phase = i
        phaseT0 = CACurrentMediaTime()
        phaseMaxThermal = 0
        let s = sample()
        rowStart = s; phaseStart = s
        guard let p = game.player else { return }
        switch phases[i].name {
        case "explore", "revisit":
            if phases[i].name == "revisit" { heading += .pi }
            p.flying = true
            p.noClip = true   // straight through mountains, so every run flies the same line
            p.setPos(p.x, 120, p.z)
            game.analogMove = (0.5, 0)
        case "dig":
            game.analogMove = nil
            p.noClip = false
            p.flying = false
            p.setPos(p.x, Double(game.world.surfaceY(Int(p.x.rounded(.down)), Int(p.z.rounded(.down)))), p.z)
            game.mouseDown(0)
        case "pause":
            game.mouseUp(0)
            rt.host.openPauseScreen()
        case "idle":
            if rt.ui.current() is PauseScreen { rt.ui.closeTop(game) }
        default: break
        }
        print(String(format: "[power] phase %@ at %.0f %.0f %.0f", phases[i].name, p.x, p.y, p.z))
        fflush(stdout)
    }

    private func drive(_ p: Player, _ t: Double) {
        switch phases[phase].name {
        case "explore", "revisit":
            // look ±0.4 rad around the heading; the average course stays straight
            p.yaw = heading + 0.4 * sin(t * 2 * .pi / 10)
            p.pitch = 0.25
            p.y = 120; p.vy = 0
        case "dig":
            p.yaw = heading + 0.2 * t
            p.pitch = 1.3
        case "idle":
            p.pitch = 0.2
        default: break
        }
    }

    // MARK: - measurement

    private func sample() -> Sample {
        var ru = rusage()
        getrusage(RUSAGE_SELF, &ru)
        let cpu = Double(ru.ru_utime.tv_sec + ru.ru_stime.tv_sec)
            + Double(ru.ru_utime.tv_usec + ru.ru_stime.tv_usec) / 1e6
        return Sample(t: CACurrentMediaTime(), cpu: cpu, gpuMs: rt.gpuMsTotal, frames: frames,
                      battery: rt.platform.battery?.level)
    }

    private func rates(_ a: Sample, _ b: Sample) -> (fps: Double, cpu: Double, gpu: Double, gpuPerFrame: Double) {
        let dt = max(0.001, b.t - a.t), n = max(1, b.frames - a.frames)
        return (Double(b.frames - a.frames) / dt, (b.cpu - a.cpu) / dt * 100,
                (b.gpuMs - a.gpuMs) / (dt * 1000) * 100, (b.gpuMs - a.gpuMs) / Double(n))
    }

    private func row() {
        guard let a = rowStart else { return }
        let b = sample()
        rowStart = b
        let r = rates(a, b)
        let bat = rt.platform.battery
        let line = String(format: "%.0f,%@,%.1f,%.0f,%.0f,%.2f,%d,%@,%@,%d,%d,%.2f,%d",
                          b.t - t0, phases[phase].name, r.fps, r.cpu, r.gpu, r.gpuPerFrame,
                          ProcessInfo.processInfo.thermalState.rawValue,
                          bat.map { String(format: "%.0f", $0.level * 100) } ?? "",
                          bat.map { $0.charging ? "1" : "0" } ?? "",
                          ProcessInfo.processInfo.isLowPowerModeEnabled ? 1 : 0,
                          processFootprintMB(), rt.renderScale, rt.renderer.sections.count)
        csv.append(line)
        print("[power] \(line)")
        fflush(stdout)
    }

    private func endPhase() {
        guard let a = phaseStart else { return }
        let b = sample()
        let r = rates(a, b)
        let thermal = ["nominal", "fair", "serious", "critical"][min(3, phaseMaxThermal)]
        var line = phases[phase].name.padding(toLength: 8, withPad: " ", startingAt: 0)
            + String(format: " %5.1f fps  cpu %4.0f%%  gpu %3.0f%% (%.2f ms/frame)  heat %@",
                     r.fps, r.cpu, r.gpu, r.gpuPerFrame, thermal)
        if let x = a.battery, let y = b.battery { line += String(format: "  battery %.0f%%→%.0f%%", x * 100, y * 100) }
        summary.append(line)
    }

    private func finish() {
        game.analogMove = nil
        game.mouseUp(0)
        print("[power] summary (\(PEBBLE_BUILD)):")
        for s in summary { print("[power]   \(s)") }
        let text = csv.joined(separator: "\n") + "\n\n# " + summary.joined(separator: "\n# ") + "\n"
        try? text.write(toFile: outPath, atomically: true, encoding: .utf8)
        print("[power] wrote \(outPath)")
        print("[power] done")
        fflush(stdout)
        rt.platform.setBatteryMonitoring(false)
        exit(0)
    }
}
