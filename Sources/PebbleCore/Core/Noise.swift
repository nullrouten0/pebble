// Simplex noise 2D/3D with seeded permutation, FBM stacks, splines.
// Bit — (same shuffle, same normalization constants)
// so worldgen produces the same worlds for the same seeds as the golden baselines.

import Foundation

// Lookup tables live in raw buffers, not Swift arrays: gen threads share one
// generator, and every array read retains/releases the buffer — an atomic on a
// shared refcount that serialized chunk gen above ~4 threads.
private let GRAD3_TABLE: UnsafeMutablePointer<Double> = {
    let g: [Double] = [
        1, 1, 0, -1, 1, 0, 1, -1, 0, -1, -1, 0,
        1, 0, 1, -1, 0, 1, 1, 0, -1, -1, 0, -1,
        0, 1, 1, 0, -1, 1, 0, 1, -1, 0, -1, -1,
    ]
    let p = UnsafeMutablePointer<Double>.allocate(capacity: g.count)
    p.initialize(from: g, count: g.count)
    return p
}()

private let F2 = 0.5 * (3.0.squareRoot() - 1)
private let G2 = (3 - 3.0.squareRoot()) / 6
private let F3 = 1.0 / 3.0
private let G3 = 1.0 / 6.0

public final class SimplexNoise {
    private let perm = UnsafeMutablePointer<Int>.allocate(capacity: 512)
    private let permMod12 = UnsafeMutablePointer<Int>.allocate(capacity: 512)
    private let GRAD3 = UnsafePointer(GRAD3_TABLE)

    public init(_ seed: UInt32) {
        var rng = RandomX(seed)
        var p = [Int](repeating: 0, count: 256)
        for i in 0..<256 { p[i] = i }
        var i = 255
        while i > 0 {
            let j = rng.nextInt(i + 1)
            p.swapAt(i, j)
            i -= 1
        }
        for k in 0..<512 {
            perm[k] = p[k & 255]
            permMod12[k] = perm[k] % 12
        }
    }

    deinit {
        perm.deallocate()
        permMod12.deallocate()
    }

    public func noise2(_ xin: Double, _ yin: Double) -> Double {
        var n0 = 0.0, n1 = 0.0, n2 = 0.0
        let s = (xin + yin) * F2
        let i = Int((xin + s).rounded(.down)), j = Int((yin + s).rounded(.down))
        let t = Double(i + j) * G2
        let x0 = xin - (Double(i) - t), y0 = yin - (Double(j) - t)
        let i1: Int, j1: Int
        if x0 > y0 { i1 = 1; j1 = 0 } else { i1 = 0; j1 = 1 }
        let x1 = x0 - Double(i1) + G2, y1 = y0 - Double(j1) + G2
        let x2 = x0 - 1 + 2 * G2, y2 = y0 - 1 + 2 * G2
        let ii = i & 255, jj = j & 255
        var t0 = 0.5 - x0 * x0 - y0 * y0
        if t0 >= 0 {
            let gi0 = permMod12[ii + perm[jj]] * 3
            t0 *= t0
            n0 = t0 * t0 * (GRAD3[gi0] * x0 + GRAD3[gi0 + 1] * y0)
        }
        var t1 = 0.5 - x1 * x1 - y1 * y1
        if t1 >= 0 {
            let gi1 = permMod12[ii + i1 + perm[jj + j1]] * 3
            t1 *= t1
            n1 = t1 * t1 * (GRAD3[gi1] * x1 + GRAD3[gi1 + 1] * y1)
        }
        var t2 = 0.5 - x2 * x2 - y2 * y2
        if t2 >= 0 {
            let gi2 = permMod12[ii + 1 + perm[jj + 1]] * 3
            t2 *= t2
            n2 = t2 * t2 * (GRAD3[gi2] * x2 + GRAD3[gi2 + 1] * y2)
        }
        return 70.14805770654148 * (n0 + n1 + n2)
    }

    public func noise3(_ xin: Double, _ yin: Double, _ zin: Double) -> Double {
        var n0 = 0.0, n1 = 0.0, n2 = 0.0, n3 = 0.0
        let s = (xin + yin + zin) * F3
        let i = Int((xin + s).rounded(.down)), j = Int((yin + s).rounded(.down)), k = Int((zin + s).rounded(.down))
        let t = Double(i + j + k) * G3
        let x0 = xin - (Double(i) - t), y0 = yin - (Double(j) - t), z0 = zin - (Double(k) - t)
        let i1: Int, j1: Int, k1: Int, i2: Int, j2: Int, k2: Int
        if x0 >= y0 {
            if y0 >= z0 { i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 1; k2 = 0 }
            else if x0 >= z0 { i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 0; k2 = 1 }
            else { i1 = 0; j1 = 0; k1 = 1; i2 = 1; j2 = 0; k2 = 1 }
        } else {
            if y0 < z0 { i1 = 0; j1 = 0; k1 = 1; i2 = 0; j2 = 1; k2 = 1 }
            else if x0 < z0 { i1 = 0; j1 = 1; k1 = 0; i2 = 0; j2 = 1; k2 = 1 }
            else { i1 = 0; j1 = 1; k1 = 0; i2 = 1; j2 = 1; k2 = 0 }
        }
        let x1 = x0 - Double(i1) + G3, y1 = y0 - Double(j1) + G3, z1 = z0 - Double(k1) + G3
        let x2 = x0 - Double(i2) + 2 * G3, y2 = y0 - Double(j2) + 2 * G3, z2 = z0 - Double(k2) + 2 * G3
        let x3 = x0 - 1 + 3 * G3, y3 = y0 - 1 + 3 * G3, z3 = z0 - 1 + 3 * G3
        let ii = i & 255, jj = j & 255, kk = k & 255
        var t0 = 0.6 - x0 * x0 - y0 * y0 - z0 * z0
        if t0 >= 0 {
            let gi0 = permMod12[ii + perm[jj + perm[kk]]] * 3
            t0 *= t0
            n0 = t0 * t0 * (GRAD3[gi0] * x0 + GRAD3[gi0 + 1] * y0 + GRAD3[gi0 + 2] * z0)
        }
        var t1 = 0.6 - x1 * x1 - y1 * y1 - z1 * z1
        if t1 >= 0 {
            let gi1 = permMod12[ii + i1 + perm[jj + j1 + perm[kk + k1]]] * 3
            t1 *= t1
            n1 = t1 * t1 * (GRAD3[gi1] * x1 + GRAD3[gi1 + 1] * y1 + GRAD3[gi1 + 2] * z1)
        }
        var t2 = 0.6 - x2 * x2 - y2 * y2 - z2 * z2
        if t2 >= 0 {
            let gi2 = permMod12[ii + i2 + perm[jj + j2 + perm[kk + k2]]] * 3
            t2 *= t2
            n2 = t2 * t2 * (GRAD3[gi2] * x2 + GRAD3[gi2 + 1] * y2 + GRAD3[gi2 + 2] * z2)
        }
        var t3 = 0.6 - x3 * x3 - y3 * y3 - z3 * z3
        if t3 >= 0 {
            let gi3 = permMod12[ii + 1 + perm[jj + 1 + perm[kk + 1]]] * 3
            t3 *= t3
            n3 = t3 * t3 * (GRAD3[gi3] * x3 + GRAD3[gi3 + 1] * y3 + GRAD3[gi3 + 2] * z3)
        }
        return 32.69587493801679 * (n0 + n1 + n2 + n3)
    }
}

/// fractal brownian motion over simplex octaves
public final class FBM {
    public let octaves: [SimplexNoise]
    // raw mirrors of octaves/amps/freqs for the hot loops (see GRAD3_TABLE);
    // `octaves` keeps the noise objects alive, so the refs here are unretained
    private let octRefs: UnsafeMutablePointer<Unmanaged<SimplexNoise>>
    private let amps: UnsafeMutablePointer<Double>
    private let freqs: UnsafeMutablePointer<Double>
    private let count: Int
    private let norm: Double

    public init(_ seed: UInt32, _ numOctaves: Int, _ baseFreq: Double, lacunarity: Double = 2, persistence: Double = 0.5) {
        var o: [SimplexNoise] = []
        var a: [Double] = []
        var f: [Double] = []
        var amp = 1.0, freq = baseFreq, total = 0.0
        for i in 0..<numOctaves {
            o.append(SimplexNoise(seed &+ UInt32(truncatingIfNeeded: i * 1013)))
            a.append(amp)
            f.append(freq)
            total += amp
            amp *= persistence
            freq *= lacunarity
        }
        octaves = o
        count = numOctaves
        octRefs = .allocate(capacity: max(1, numOctaves))
        amps = .allocate(capacity: max(1, numOctaves))
        freqs = .allocate(capacity: max(1, numOctaves))
        for i in 0..<numOctaves {
            octRefs[i] = Unmanaged.passUnretained(o[i])
            amps[i] = a[i]
            freqs[i] = f[i]
        }
        norm = 1 / total
    }

    deinit {
        octRefs.deallocate()
        amps.deallocate()
        freqs.deallocate()
    }

    public func sample2(_ x: Double, _ z: Double) -> Double {
        var v = 0.0
        for i in 0..<count {
            let f = freqs[i]
            v += octRefs[i]._withUnsafeGuaranteedRef { $0.noise2(x * f, z * f) } * amps[i]
        }
        return v * norm
    }

    public func sample3(_ x: Double, _ y: Double, _ z: Double) -> Double {
        var v = 0.0
        for i in 0..<count {
            let f = freqs[i]
            v += octRefs[i]._withUnsafeGuaranteedRef { $0.noise3(x * f, y * f, z * f) } * amps[i]
        }
        return v * norm
    }

    /// ridged variant: (1 - |n|)², summed
    public func ridge2(_ x: Double, _ z: Double) -> Double {
        var v = 0.0
        for i in 0..<count {
            let f = freqs[i]
            let n = 1 - abs(octRefs[i]._withUnsafeGuaranteedRef { $0.noise2(x * f, z * f) })
            v += n * n * amps[i]
        }
        return v * norm
    }
}

/// piecewise smoothstep-interpolated spline (vanilla-style terrain shaping)
public struct Spline {
    private let xs: [Double]
    private let ys: [Double]

    public init(_ points: [(Double, Double)]) {
        xs = points.map { $0.0 }
        ys = points.map { $0.1 }
    }

    public func at(_ x: Double) -> Double {
        let n = xs.count
        if x <= xs[0] { return ys[0] }
        if x >= xs[n - 1] { return ys[n - 1] }
        var lo = 0, hi = n - 1
        while hi - lo > 1 {
            let mid = (lo + hi) >> 1
            if xs[mid] <= x { lo = mid } else { hi = mid }
        }
        let t = (x - xs[lo]) / (xs[hi] - xs[lo])
        let st = t * t * (3 - 2 * t)
        return ys[lo] + (ys[hi] - ys[lo]) * st
    }
}
